#version 450

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
    light_t Light0
    light_t Light1
    light_t Light2;
    light_t Light3;
    light_t Light4;
    light_t Light5;
    light_t Light6;
    light_t Light7;
    vec4 Material_Diffuse;
    vec4 Material_Ambient;
    vec4 Material_Specular;
    vec4 Material_Emissive;
    float Material_Power;
} consts;

layout(location = 1) in vec4 in_Texcoord0;
layout(location = 2) in vec4 in_Texcoord1;
layout(location = 3) in vec4 in_Texcoord2;
layout(location = 4) in vec4 in_Texcoord3;
layout(location = 5) in vec4 in_Texcoord4;
layout(location = 6) in vec4 in_Texcoord5;
layout(location = 7) in vec4 in_Texcoord6;
layout(location = 8) in vec4 in_Texcoord7;
layout(location = 9) in vec4 in_Color0;
layout(location = 10) in vec4 in_Color1;
layout(location = 11) in float in_Fog0;
layout(location = 0) out vec4 out_Color0;

layout(set = 0, binding = 0) uniform sampler2D s0;
layout(set = 0, binding = 1) uniform sampler2D s1;
layout(set = 0, binding = 2) uniform sampler2D s2;
layout(set = 0, binding = 3) uniform sampler2D s3;
layout(set = 0, binding = 4) uniform sampler2D s4;
layout(set = 0, binding = 5) uniform sampler2D s5;
layout(set = 0, binding = 6) uniform sampler2D s6;
layout(set = 0, binding = 7) uniform sampler2D s7;

void main()
{
    out_Color0 = vec4(1., 0., 1., 1.);
}
