#version 450
#extension GL_EXT_demote_to_helper_invocation : require
#extension GL_GOOGLE_include_directive : require
#extension GL_EXT_control_flow_attributes : require

/**
 * OMSI fixed function lighting override shader.
 * Copyright Thomas Mathieson (c) 2023
 */


//------------------------------------------------------------------------------
// PARAMETERS
//------------------------------------------------------------------------------

// Limit the number of per-pixel lights to 4 for performance
#define OVERRIDE_MAX_LIGHTS 4
// For fake HDR-iness we extend the range of the lights
#define LIGHT_POWER 2.5
#define LIGHT_SCALE 1.6
#define OVERRIDE_ROUGHNESS 0.5
#define OVERRIDE_METALLIC 0.

#include "D3D9_ShaderConsts.glsl"


//------------------------------------------------------------------------------
// UTILITIES
//------------------------------------------------------------------------------

#define saturate(x) clamp(x, 0., 1.)
#define PI 3.14159265

// https://www.shadertoy.com/view/ldtcW2
const float kShoulderStrength = 0.32;
const float kLinearStrength   = 0.30;
const float kLinearAngle      = 0.40;
const float kToeStrength      = 0.20;
const float kToeNumerator     = 0.01;
const float kToeDenominator   = 0.20;
vec3 filmicToneMapping(in vec3 color)
{
	return ((color*(kShoulderStrength*color+kLinearAngle*kLinearStrength)+kToeStrength*kToeNumerator) /
 			(color*(kShoulderStrength*color+kLinearStrength)+kToeStrength*kToeDenominator))-kToeNumerator/kToeDenominator;
}

//------------------------------------------------------------------------------
// BRDF
//------------------------------------------------------------------------------

float pow5(float x) {
    float x2 = x * x;
    return x2 * x2 * x;
}

float D_GGX(float linearRoughness, float NoH, const vec3 h) {
    // Walter et al. 2007, "Microfacet Models for Refraction through Rough Surfaces"
    float oneMinusNoHSquared = 1.0 - NoH * NoH;
    float a = NoH * linearRoughness;
    float k = linearRoughness / (oneMinusNoHSquared + a * a);
    float d = k * k * (1.0 / PI);
    return d;
}

float V_SmithGGXCorrelated(float linearRoughness, float NoV, float NoL) {
    // Heitz 2014, "Understanding the Masking-Shadowing Function in Microfacet-Based BRDFs"
    float a2 = linearRoughness * linearRoughness;
    float GGXV = NoL * sqrt((NoV - a2 * NoV) * NoV + a2);
    float GGXL = NoV * sqrt((NoL - a2 * NoL) * NoL + a2);
    return 0.5 / (GGXV + GGXL);
}

vec3 F_Schlick(const vec3 f0, float VoH) {
    // Schlick 1994, "An Inexpensive BRDF Model for Physically-Based Rendering"
    return f0 + (vec3(1.0) - f0) * pow5(1.0 - VoH);
}

float F_Schlick(float f0, float f90, float VoH) {
    return f0 + (f90 - f0) * pow5(1.0 - VoH);
}

float Fd_Burley(float linearRoughness, float NoV, float NoL, float LoH) {
    // Burley 2012, "Physically-Based Shading at Disney"
    float f90 = 0.5 + 2.0 * linearRoughness * LoH * LoH;
    float lightScatter = F_Schlick(1.0, f90, NoL);
    float viewScatter  = F_Schlick(1.0, f90, NoV);
    return lightScatter * viewScatter * (1.0 / PI);
}

float Fd_Lambert() {
    return 1.0 / PI;
}


//------------------------------------------------------------------------------
// LIGHTING
//------------------------------------------------------------------------------

vec3 computeLighting(vec3 baseColor, float roughness, vec3 transmission)
{
    vec3 lighting = consts.GlobalAmbient.xyz;
    [[unroll]]
    for(int i = 0; i < OVERRIDE_MAX_LIGHTS; i++)
    {
        // Much of this is derived from: https://www.shadertoy.com/view/XlKSDR
        vec3 n = normalize(in_Normal0.xyz);
        vec3 l = -consts.Lights[i].Direction.xyz;
        vec3 v = normalize(in_ViewDir.xyz);
        vec3 h = normalize(l - v);
        float ndotl = saturate(dot(n, l));
        float ndoth = saturate(dot(h, n));
        float ndotv = abs(dot(n, v)) + 1e-5;
        float ldoth = saturate(dot(l, h));
        float spec = pow(saturate(dot(h, n)), 3.);

        float linearRoughness = roughness * roughness;
        vec3 diffuseColor = (1.0 - OVERRIDE_METALLIC) * baseColor.rgb;
        vec3 f0 = 0.04 * (1.0 - OVERRIDE_METALLIC) + baseColor.rgb * OVERRIDE_METALLIC;

        // specular BRDF
        float D = D_GGX(linearRoughness, ndoth, h);
        float V = V_SmithGGXCorrelated(linearRoughness, ndotv, ndotl);
        vec3  F = F_Schlick(f0, ldoth);
        vec3 Fr = (D * V) * F;

        // diffuse BRDF
        vec3 Fd = diffuseColor * Fd_Burley(linearRoughness, ndotv, ndotl, ldoth);
        //color *= (intensity * attenuation * ndotl) * vec3(0.98, 0.92, 0.89);

        vec3 Ft = transmission * pow(saturate((-dot(n, l))*0.5+0.5), 0.7);

        lighting += ((Fd + Fr) * ndotl + Ft) * pow(consts.Lights[i].Diffuse.xyz * LIGHT_SCALE, vec3(LIGHT_POWER)) + consts.Lights[i].Ambient.xyz;
    }

    return lighting;
}


//------------------------------------------------------------------------------
// MAIN
//------------------------------------------------------------------------------

void main()
{
    vec4 mainTex = texture(s0, in_Texcoord0.xy);
    float roughness = mainTex.a * OVERRIDE_ROUGHNESS;
    vec3 transmission = vec3(0.);

    #ifdef TEXTURE_STAGE_2_BOUND
    // Make some assumptions here that we must be rendering a terrain tile
    vec4 diffuse = texture(s1, in_Texcoord1.xy);
    vec4 diffuse1 = texture(s2, in_Texcoord2.xy);

    roughness = diffuse.r * OVERRIDE_ROUGHNESS + 0.35;

    #ifdef TEXTURE_STAGE_0_COLOR_OP_D3DTOP_ADDSMOOTH
        // At night time, add the nightmap...
        mainTex += diffuse * diffuse1;
    #else
        mainTex = diffuse * diffuse1;
    #endif
    #endif

    #if defined(TEXTURE_STAGE_1_BOUND) && !defined(TEXTURE_STAGE_2_BOUND)
        vec4 diffuse = texture(s1, in_Texcoord1.xy);
        #if defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_ADDSMOOTH)
            // Treat mainTex as a nightMap/lightMap and diffuse as the main texture
            mainTex += diffuse;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_LERP)
            // Blend between mainTex and diffuse by the texture factor, dirtmaps?
            mainTex = mix(mainTex, diffuse, consts.textureFactor);
        #else
            // Multiply
            roughness = diffuse.r * OVERRIDE_ROUGHNESS;
            mainTex *= diffuse;
        #endif
        mainTex.a = diffuse.a;
    #endif

    if(isAlphaTestEnabled()) 
    {
        roughness = .8;
        transmission = mix(vec3(0.2), vec3(0.2, 0.6, 0.05), 0.5);
    }

    vec3 light = computeLighting(mainTex.rgb, roughness, transmission);

    #if defined(TEXTURE_STAGE_0_COLOR_OP_D3DTOP_ADDSMOOTH)
        // Treat mainTex as an emmissive texture
        //out_Color0 = vec4(light + mainTex.rgb, 1.0);
        // This seems to make things worse at the moment...
        out_Color0 = vec4(light * mainTex.rgb, 1.0);
    #else
        out_Color0 = vec4(light * mainTex.rgb, 1.0);
    #endif

    // Tonemap for that fake HDR <3
    out_Color0.rgb = filmicToneMapping(pow(out_Color0.rgb, vec3(1.5))) * 1.2;

    out_Color0.a = in_Color0.a * mainTex.a;

    #ifdef TEXTURE_STAGE_3_BOUND
    // Assume we're doing an additional terrain layer which needs blending
    vec4 alpha = texture(s3, in_Texcoord3.xy);
    out_Color0.a = alpha.a;
    #endif

    // The ALPHA_TEST flag is currently buggy
    //#if defined(ALPHA_TEST)
    if(isAlphaTestEnabled() && out_Color0.a < 0.5)
        discard;
    //#endif
}
