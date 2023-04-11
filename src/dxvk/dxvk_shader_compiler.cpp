#include "dxvk_shader.h"
#include "../spirv/spirv_module.h"
#include "../util/log/log.h"
#include <spirv/unified1/spirv.hpp>
#include <spirv/unified1/GLSL.std.450.h>
#include <glslang/include/glslang/Include/glslang_c_shader_types.h>
#include <glslang/include/glslang/Include/glslang_c_interface.h>
#include <glslang/include/glslang/Public/ShaderLang.h>
#include <glslang/include/glslang/Public/ResourceLimits.h>
#include <glslang/include/glslang/SPIRV/doc.h>
#include <dxvk_dummy_frag.h>

namespace dxvk {
	std::vector<uint32_t> compileShaderToSPIRV_Vulkan(glslang_stage_t stage, const char* shaderSource, const char* fileName, const std::vector<std::string> shaderVariantDefines)
	{
		std::string shaderSourceProc;

		std::stringstream ss(shaderSource);
		std::string line;

		if (shaderSource != NULL) {
			bool foundVersion = false;
			bool doneInserting = false;
			while (std::getline(ss, line, '\n')) {
				if (!doneInserting) {
					if (line.find("#version", 0) != -1 || line.find("#extension") != -1) {
						foundVersion = true;
					}
					else {
						if (foundVersion) {
							foundVersion = false;

							// Now we can append our defines
							for (auto& define : shaderVariantDefines)
								shaderSourceProc.append(str::format("#define ", define, '\n'));

							doneInserting = true;
						}
					}
				}
				shaderSourceProc.append(line + '\n');
			}
		}

		const glslang_input_t input = {
			.language = GLSLANG_SOURCE_GLSL,
			.stage = stage,
			.client = GLSLANG_CLIENT_VULKAN,
			.client_version = GLSLANG_TARGET_VULKAN_1_2,
			.target_language = GLSLANG_TARGET_SPV,
			.target_language_version = GLSLANG_TARGET_SPV_1_5,
			.code = shaderSourceProc.c_str(),
			.default_version = 100,
			.default_profile = GLSLANG_NO_PROFILE,
			.force_default_version_and_profile = false,
			.forward_compatible = false,
			.messages = GLSLANG_MSG_DEFAULT_BIT,
			.resource = reinterpret_cast<const glslang_resource_t*>(GetDefaultResources()),
		};

		glslang_shader_t* shader = glslang_shader_create(&input);

		if (!glslang_shader_preprocess(shader, &input)) {
			Logger::err(str::format("GLSL preprocessing failed: ", fileName));
			Logger::err(glslang_shader_get_info_log(shader));
			Logger::err(glslang_shader_get_info_debug_log(shader));
			Logger::err(input.code);
			glslang_shader_delete(shader);
			return std::vector<uint32_t>(std::begin(dxvk_dummy_frag), std::end(dxvk_dummy_frag));
		}

		if (!glslang_shader_parse(shader, &input)) {
			Logger::err(str::format("GLSL parsing failed: ", fileName));
			Logger::err(glslang_shader_get_info_log(shader));
			Logger::err(glslang_shader_get_info_debug_log(shader));
			Logger::err(glslang_shader_get_preprocessed_code(shader));
			glslang_shader_delete(shader);
			return std::vector<uint32_t>(std::begin(dxvk_dummy_frag), std::end(dxvk_dummy_frag));
		}

		glslang_program_t* program = glslang_program_create();
		glslang_program_add_shader(program, shader);

		if (!glslang_program_link(program, GLSLANG_MSG_SPV_RULES_BIT | GLSLANG_MSG_VULKAN_RULES_BIT)) {
			Logger::err(str::format("GLSL linking failed: ", fileName));
			Logger::err(glslang_program_get_info_log(program));
			Logger::err(glslang_program_get_info_debug_log(program));
			glslang_program_delete(program);
			glslang_shader_delete(shader);
			return std::vector<uint32_t>(std::begin(dxvk_dummy_frag), std::end(dxvk_dummy_frag));
		}

		glslang_program_SPIRV_generate(program, stage);

		std::vector<uint32_t> outShaderModule(glslang_program_SPIRV_get_size(program));
		glslang_program_SPIRV_get(program, outShaderModule.data());

		const char* spirv_messages = glslang_program_SPIRV_get_messages(program);
		if (spirv_messages)
			Logger::err(str::format("(", fileName, ") ", spirv_messages, "\b"));

		glslang_program_delete(program);
		glslang_shader_delete(shader);

		return outShaderModule;
	}

	bool mergeShaderBytecode(SpirvModule& dst, SpirvCodeBuffer& src, uint32_t entryPointFunctionID) {
		// Extract the function we want to insert, update all of it's IDs to not collide with the destination bytcode
		// and then merge it into the following sections: Debug information, annotations, type/variable/const 
		// declarations, functions
		// TODO: In practice this won't break, but it's also not really robust code. It relies on magic.

		// Fill in the data we're going to need later
		spv::Parameterize();

		// Get a new id that hasn't been used yet
		int linkStartId = dst.allocateId();
		int nInstructionsToLink = src.getBoundsId();

		// Find the function we want to link
		//const char* targetFunctionName = "ffOverrideMain(vf4;vf3;vf3;";
		const char* dummyFunctionName = "main";
		uint32_t dummyFunctionId = -1;
		// Cache each segment of the bytecode to link so we can filter it more easily later
		SpirvInstruction** debugInstructions = new SpirvInstruction * [nInstructionsToLink];
		SpirvInstruction** annotationInstructions = new SpirvInstruction * [nInstructionsToLink];
		SpirvInstruction** typeVarConstInstructions = new SpirvInstruction * [nInstructionsToLink];
		std::vector<SpirvInstruction*> functionInstructions;

		uint32_t currentFunctionId = -1;
		for (auto inst : src)
		{
			// We can rely on the fact that the debug information we are relying on here is always at the start of the bytecode
			if (inst.opCode() == spv::OpName)
			{
				if (std::strcmp(inst.chr(2), dummyFunctionName) == 0)
				{
					dummyFunctionId = inst.arg(1);
					Logger::debug("[DXVK FF Shader Compiler] Found dummy function to strip!");
				}
			}

			//TODO: Refactor this using InstructionDesc
			// Get ready for ugly...
			switch (inst.opCode())
			{
				// Debug Instructions
			case spv::OpName:
			case spv::OpMemberName:
			case spv::OpString:
				//case spv::OpLine:
				debugInstructions[inst.arg(1)] = &inst;
				break;
			case spv::OpSourceContinued:
			case spv::OpSource:
			case spv::OpSourceExtension:
			case spv::OpModuleProcessed:
				break;

				// Annotation Instructions
			case spv::OpDecorate:
			case spv::OpMemberDecorate:
			case spv::OpDecorationGroup:
			case spv::OpGroupDecorate:
			case spv::OpGroupMemberDecorate:
			case spv::OpDecorateId:
			case spv::OpDecorateString:
			case spv::OpMemberDecorateString:
				annotationInstructions[inst.arg(1)] = &inst;
				break;

				// Type/Const/Var Instructions
			case spv::OpTypeArray:
			case spv::OpTypeBool:
			case spv::OpTypeDeviceEvent:
			case spv::OpTypeEvent:
			case spv::OpTypeFloat:
			case spv::OpTypeForwardPointer:
			case spv::OpTypeFunction:
			case spv::OpTypeImage:
			case spv::OpTypeInt:
			case spv::OpTypeMatrix:
			case spv::OpTypeNamedBarrier:
			case spv::OpTypeOpaque:
			case spv::OpTypePipe:
			case spv::OpTypePipeStorage:
			case spv::OpTypePointer:
			case spv::OpTypeQueue:
			case spv::OpTypeReserveId:
			case spv::OpTypeRuntimeArray:
			case spv::OpTypeSampledImage:
			case spv::OpTypeSampler:
			case spv::OpTypeStruct:
			case spv::OpTypeVector:
			case spv::OpTypeVoid:
			case spv::OpConstant:
			case spv::OpConstantComposite:
			case spv::OpConstantFalse:
			case spv::OpConstantNull:
			case spv::OpConstantPipeStorage:
			case spv::OpConstantSampler:
			case spv::OpConstantTrue:
			case spv::OpVariable:
				typeVarConstInstructions[inst.arg(1)] = &inst;
				break;

				// Function instructions
			default:
				// Ignore any function instructions which aren't in a function we care about
				if (currentFunctionId == dummyFunctionId)
				{
					functionInstructions.push_back(&inst);
				}
				break;
			}
		}

		bool inDummyFunc = false;
		for (auto inst : functionInstructions) {
			// Skip the dummy function
			if (inDummyFunc)
			{
				if (inst->opCode() == spv::OpFunctionEnd)
					inDummyFunc = false;
				continue;
			}

			if (inst->opCode() == spv::OpFunction && inst->arg(2) == dummyFunctionId)
				inDummyFunc = true;

			// Now copy the new instructions accross and remap any ids as we go
			auto& opDesc = spv::InstructionDesc[inst->opCode()];

			if (opDesc.hasResult())
			{
				inst->incrementArg(1, linkStartId);
				if (opDesc.hasType())
					inst->incrementArg(2, linkStartId);
			}

			//uint32_t opCode = inst->opCode();
			for (int i = 0; i < opDesc.operands.getNum(); i++)
			{
				/*// This is modified from https://github.com/KhronosGroup/glslang/blob/main/SPIRV/SPVRemapper.cpp
				// SpecConstantOp is special: it includes the operands of another opcode which is
				// given as a literal in the 3rd word.  We will switch over to pretending that the
				// opcode being processed is the literal opcode value of the SpecConstantOp.  See the
				// SPIRV spec for details.  This way we will handle IDs and literals as appropriate for
				// the embedded op.
				if (opCode == spv::OpSpecConstantOp) {
					if (i == 0) {
						opCode = inst->arg(1);  // this is the opcode embedded in the SpecConstantOp.
						i++;
					}
				}

				switch (spv::InstructionDesc[opCode].operands.getClass(op)) {
				case spv::OperandId:
				case spv::OperandScope:
				case spv::OperandMemorySemantics:
					idBuffer[idBufferPos] = asId(word);
					idBufferPos = (idBufferPos + 1) % idBufferSize;
					idFn(asId(word++));
					break;

				case spv::OperandVariableIds:
					for (unsigned i = 0; i < numOperands; ++i)
						idFn(asId(word++));
					return nextInst;

				case spv::OperandVariableLiterals:
					// for clarity
					// if (opCode == spv::OpDecorate && asDecoration(word - 1) == spv::DecorationBuiltIn) {
					//     ++word;
					//     --numOperands;
					// }
					// word += numOperands;
					return nextInst;

				case spv::OperandVariableLiteralId: {
					if (opCode == OpSwitch) {
						// word-2 is the position of the selector ID.  OpSwitch Literals match its type.
						// In case the IDs are currently being remapped, we get the word[-2] ID from
						// the circular idBuffer.
						const unsigned literalSizePos = (idBufferPos + idBufferSize - 2) % idBufferSize;
						const unsigned literalSize = idTypeSizeInWords(idBuffer[literalSizePos]);
						const unsigned numLiteralIdPairs = (nextInst - word) / (1 + literalSize);

						if (errorLatch)
							return -1;

						for (unsigned arg = 0; arg < numLiteralIdPairs; ++arg) {
							word += literalSize;  // literal
							idFn(asId(word++));   // label
						}
					}
					else {
						assert(0); // currentely, only OpSwitch uses OperandVariableLiteralId
					}

					return nextInst;
				}

				case spv::OperandLiteralString: {
					const int stringWordCount = literalStringWords(literalString(word));
					word += stringWordCount;
					numOperands -= (stringWordCount - 1); // -1 because for() header post-decrements
					break;
				}

				case spv::OperandVariableLiteralStrings:
					return nextInst;

					// Execution mode might have extra literal operands.  Skip them.
				case spv::OperandExecutionMode:
					return nextInst;
				}*/

				dst.appendInstruction(inst);
			}
		}

		return false;
	}
}