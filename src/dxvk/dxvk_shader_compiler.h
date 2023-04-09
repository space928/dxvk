#pragma once

#include <glslang/include/glslang/Public/ShaderLang.h>
#include <glslang/include/glslang/Include/glslang_c_shader_types.h>
#include "../spirv/spirv_module.h"

namespace dxvk {
	std::vector<uint32_t> compileShaderToSPIRV_Vulkan(glslang_stage_t stage, const char* shaderSource, const char* fileName);
}