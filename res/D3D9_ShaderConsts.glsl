/**
 * OMSI fixed function lighting override shader uniforms.
 * Copyright Thomas Mathieson (c) 2023
 */

struct light_t {
    vec4 Diffuse;
    vec4 Specular;
    vec4 Ambient;
    vec4 Position;
    vec4 Direction;
    uint Type;
    float Range;
    float Falloff;
    float Attenuation0;
    float Attenuation1;
    float Attenuation2;
    float Theta;
    float Phi;
};

layout(set = 1, binding = 0) uniform D3D9FixedFunctionPS
{
    vec4 textureFactor;
    vec4 GlobalAmbient;
    light_t[8] Lights;
    vec4 Material_Diffuse;
    vec4 Material_Ambient;
    vec4 Material_Specular;
    vec4 Material_Emissive;
    float Material_Power;
} consts;

struct D3D9SharedPS_Stage 
{
    vec4 Constant;
    vec2 BumpEnvMat0;
    vec2 BumpEnvMat1;
    float BumpEnvLScale;
    float BumpEnvLOffset;
    vec2 Padding;
};

layout(set = 1, binding = 1, std140) uniform D3D9SharedPS
{
    D3D9SharedPS_Stage Stages[8];
} D3D9SharedPS_1;

// These have some handy state variables in them, but at the moment accessing them seems to result in a crash,
// I guess the buffer isn't being bound correctly
/*layout(set = 2, binding = 1) uniform spec_state_t
{
    uint dword0;
    uint dword1;
    uint dword2;
    uint dword3;
    uint dword4;
    uint dword5;
    uint dword6;
    uint dword7;
    uint dword8;
    uint dword9;
    uint dword10;
    uint dword11;
    uint dword12;
    uint dword13;
} spec_state;*/

layout(push_constant) uniform render_state_t
{
    vec3 fog_color;
    float fog_scale;
    float fog_end;
    float fog_density;
    uint alpha_ref;
    float point_size;
    float point_size_min;
    float point_size_max;
    float point_scale_a;
    float point_scale_b;
    float point_scale_c;
} render_state;

layout(location = 0) in vec4 in_ViewDir;
layout(location = 1) in vec4 in_Position0;
layout(location = 2) in vec4 in_Normal0;
layout(location = 3) in vec4 in_Texcoord0;
layout(location = 4) in vec4 in_Texcoord1;
layout(location = 5) in vec4 in_Texcoord2;
layout(location = 6) in vec4 in_Texcoord3;
layout(location = 7) in vec4 in_Texcoord4;
layout(location = 8) in vec4 in_Texcoord5;
layout(location = 9) in vec4 in_Texcoord6;
layout(location = 10) in vec4 in_Texcoord7;
layout(location = 11) in vec4 in_Color0;
layout(location = 12) in vec4 in_Color1;
layout(location = 13) in float in_Fog0;
layout(location = 0) out vec4 out_Color0;

layout(set = 0, binding = 0) uniform sampler2D s0;
layout(set = 0, binding = 1) uniform sampler2D s1;
layout(set = 0, binding = 2) uniform sampler2D s2;
layout(set = 0, binding = 3) uniform sampler2D s3;
layout(set = 0, binding = 4) uniform sampler2D s4;
layout(set = 0, binding = 5) uniform sampler2D s5;
layout(set = 0, binding = 6) uniform sampler2D s6;
layout(set = 0, binding = 7) uniform sampler2D s7;

// Utility functions
bool isAlphaTestEnabled()
{
    // This current method isn't really correct and we should try to use the spec state instead
    // That being said, it generally works...
    return render_state.alpha_ref > 8; //(spec_state.dword1 & 0x700000) != 0x400000;
}
