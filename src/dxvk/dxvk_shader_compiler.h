#pragma once

#include <glslang/include/glslang/Public/ShaderLang.h>
#include <glslang/include/glslang/Include/glslang_c_shader_types.h>
#include "../spirv/spirv_module.h"

namespace dxvk {
	/**
	* \brief Compiles a GLSL shader into SPIR-V bytecode.
	*/
	std::vector<uint32_t> compileShaderToSPIRV_Vulkan(glslang_stage_t stage, const char* shaderSource, const char* fileName, const std::vector<std::string> shaderVariantDefines);
}