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
#define OVERRIDE_MAX_LIGHTS 8
// For fake HDR-iness we extend the range of the lights
#define LIGHT_POWER 2.5
#define LIGHT_SCALE 1.6
#define FLARE_BRIGHTNESS 1.3
#define SPOTLIGHT_SCALE 3.0
// Terrain
#define LIGHTMAP_BRIGHTNESS 1.0
#define SCLIGHTMAP_BRIGHTNESS 0.3
// Scenery
#define NIGHTMAP_BRIGHTNESS 1.2
#define OVERRIDE_ROUGHNESS 0.5
#define OVERRIDE_METALLIC 0.

//#define DEBUG_MATERIAL_TYPE
//#define DEBUG_LIGHT_DATA

#include "D3D9_ShaderConsts.glsl"


//------------------------------------------------------------------------------
// UTILITIES
//------------------------------------------------------------------------------

#define saturate(x) clamp(x, 0., 1.)
#define PI 3.14159265
#define N_LIGHTS min(OVERRIDE_MAX_LIGHTS, MAX_LIGHTS)

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

vec4 debugShaderType(vec3 albedo, vec2 uv)
{
    albedo = vec3(0., 0., 0.5);
    #if defined(TEXTURE_STAGE_3_BOUND)
        albedo.r = 1.;
    #elif defined(TEXTURE_STAGE_2_BOUND)
        albedo.r = 0.67;
    #elif defined(TEXTURE_STAGE_1_BOUND)
        albedo.r = 0.33;
        #if defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_LERP)
            albedo.g = 1.;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_MODULATE)
            albedo.g = 0.75;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_SELECTARG1)
            albedo.g = 0.5;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_BLENDCURRENTALPHA)
            albedo.g = 0.1;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_ADDSMOOTH)
            albedo.g = 0.2;
        #endif
    #else
        albedo.r = 0.;
    #endif

    #if defined(TEXTURE_STAGE_0_ALPHA_OP_D3DTOP_DISABLE) || defined(TEXTURE_STAGE_1_ALPHA_OP_D3DTOP_DISABLE) || defined(TEXTURE_STAGE_2_ALPHA_OP_D3DTOP_DISABLE) || defined(TEXTURE_STAGE_3_ALPHA_OP_D3DTOP_DISABLE)
        albedo *= fract(uv.x*5.);
    #elif defined(TEXTURE_STAGE_0_ALPHA_OP_D3DTOP_MODULATE) || defined(TEXTURE_STAGE_1_ALPHA_OP_D3DTOP_MODULATE) || defined(TEXTURE_STAGE_2_ALPHA_OP_D3DTOP_MODULATE)
        albedo *= fract((uv.x+uv.y)*1.);
        #ifdef TEXTURE_STAGE_0_ALPHA_ARG2_D3DTA_CONSTANT
        albedo *= fract((uv.x)*7.);
        #endif
    #endif

    return vec4(albedo, 1.);
}

vec3 dbgTypeToCol(uint type)
{
    switch(type)
    {
        case 0:
            return vec3(0.2,0.,0.);
        case 1:
            return vec3(1.,0.,0.);
        case 2:
            return vec3(0.,1.,0.);
        case 3:
            return vec3(0.,0.,1.);
        default:
            return vec3(1.);
    }
}

vec4 debugLightData(vec4 col)
{
    vec3 dl = (consts.Lights[2].Position - in_Position0).xyz;
    float dist = length(dl);
    //col.rgb = vec3(consts.Lights[2].Diffuse.r, step(dist, consts.Lights[2].Range), consts.Lights[2].Diffuse.r);
    vec2 uv = (in_Position0.xy/in_Position0.z+0.3)*1.5;
    uv.x += 0.6;
    if(uv.x > 1.)
        return col;
    col.rgb = vec3(fract(uv*10.), 1.);
    for(int i = 0; i < 8; i++)
    {
        if (uv.x < 0. || uv.y < 0. || uv.x > 1. || uv.y > 1.)
            break;
        if(uv.x > float(i)/10.)
        {
            if(uv.y < 0.1)
                col.rgb = consts.Lights[i].Diffuse.rgb;
            else if(uv.y < 0.2)
                col.rgb = consts.Lights[i].Specular.rgb;
            else if(uv.y < 0.3)
                col.rgb = consts.Lights[i].Ambient.rgb;
            else if(uv.y < 0.4)
                col.rgb = fract(consts.Lights[i].Position.rgb);
            else if(uv.y < 0.5)
                col.rgb = consts.Lights[i].Direction.rgb;
            else if(uv.y < 0.6)
                col.rgb = dbgTypeToCol(consts.Lights[i].Type);
            else if(uv.y < 0.7)
                col.rgb = vec3(consts.Lights[i].Range/100., fract(consts.Lights[i].Range/10.), fract(consts.Lights[i].Range));
            else if(uv.y < 0.8)
                col.rgb = vec3(consts.Lights[i].Falloff/100., fract(consts.Lights[i].Falloff/10.), fract(consts.Lights[i].Falloff));
            else if(uv.y < 0.9)
                col.rgb = vec3(consts.Lights[i].Attenuation0, fract(consts.Lights[i].Attenuation1), fract(consts.Lights[i].Attenuation2));
            else if(uv.y < 1.)
                col.rgb = vec3(float(i)/8.);

            if(i > N_LIGHTS)
                col.rgb = mix(vec3(0.), vec3(0.,1.,1.), step(fract(uv.x*80. - uv.y*80.), 0.5));
        }
    }

    col.rgb = mix(col.rgb, vec3(0.5), step(fract(uv.x*10.), 0.06));
    col.rgb = mix(col.rgb, vec3(0.5), step(fract(uv.y*10.), 0.06));
    if(isnan(col.r))
        col.rgb = mix(vec3(0.), vec3(1.,1.,0.), step(fract(uv.x*80. + uv.y*80.), 0.5));

    return col;
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
    for(int i = 0; i < N_LIGHTS; i++)
    {
        if(consts.Lights[i].Type == 0)
            break;

        vec3 l = -consts.Lights[i].Direction.xyz;
        float atten = 1.;
        switch(consts.Lights[i].Type)
        {
            case 1:
                // Point light
                l = (consts.Lights[i].Position - in_Position0).xyz;
                float dist = length(l);
                l = normalize(l);
                if(dist >= consts.Lights[i].Range)
                    continue;
                atten = 1./(consts.Lights[i].Attenuation0 + consts.Lights[i].Attenuation1 * dist + consts.Lights[i].Attenuation2 * dist * dist);
                break;
            case 2:
                // Spot light
                l = (consts.Lights[i].Position - in_Position0).xyz;
                dist = length(l);
                l = normalize(l);
                if(dist >= consts.Lights[i].Range)
                    continue;
                atten = 1./(consts.Lights[i].Attenuation0 + consts.Lights[i].Attenuation1 * dist + consts.Lights[i].Attenuation2 * dist * dist);
                // Penumbra
                atten *= 1.-smoothstep(consts.Lights[i].Theta, consts.Lights[i].Phi, dot(l, -consts.Lights[i].Direction.xyz));
                atten *= SPOTLIGHT_SCALE;
                break;
            case 3:
                // Directional light
                l = -consts.Lights[i].Direction.xyz;
                break;
        }

        // Much of this is derived from: https://www.shadertoy.com/view/XlKSDR
        vec3 n = normalize(in_Normal0.xyz);
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

        lighting += ((Fd + Fr) * ndotl + Ft) * atten * pow(consts.Lights[i].Diffuse.xyz * LIGHT_SCALE, vec3(LIGHT_POWER)) + consts.Lights[i].Ambient.xyz * atten;
    }

    return lighting;
}


//------------------------------------------------------------------------------
// MAIN
//------------------------------------------------------------------------------

void main()
{
    vec4 albedo = texture(s0, in_Texcoord0.xy);
    vec3 emission = vec3(0.);
    float roughness = albedo.a * OVERRIDE_ROUGHNESS;
    vec3 transmission = vec3(0.);

    /////
    // Terrain tile
    #ifdef TEXTURE_STAGE_2_BOUND
    // Make some assumptions here that we must be rendering a terrain tile
    vec4 diffuse = texture(s1, in_Texcoord1.xy);
    vec4 diffuse1 = texture(s2, in_Texcoord2.xy);

    roughness = diffuse.r * OVERRIDE_ROUGHNESS + 0.35;

    #ifdef TEXTURE_STAGE_0_COLOR_OP_D3DTOP_ADDSMOOTH
        // At night time, add the nightmap...
        emission = albedo.rgb * LIGHTMAP_BRIGHTNESS;
        albedo = diffuse * diffuse1;
        emission *= albedo.rgb;
    #else
        albedo = diffuse * diffuse1;
    #endif
    #endif
    /////

    /////
    // Nightmap/lightmapped
    #if defined(TEXTURE_STAGE_1_BOUND) && !defined(TEXTURE_STAGE_2_BOUND)
        vec4 diffuse = texture(s1, in_Texcoord1.xy);
        #if defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_ADDSMOOTH)
            // Treat albedo as a nightMap/lightMap and diffuse as the main texture
            emission = diffuse.rgb * NIGHTMAP_BRIGHTNESS;
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_LERP)
            // Blend between albedo and diffuse by the texture factor, dirtmaps?
            albedo = mix(albedo, diffuse, consts.textureFactor);
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_BLENDCURRENTALPHA)
            albedo = vec4(1.,0.,0.,1.);
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_SELECTARG1)
            albedo = vec4(0.,1.,0.,1.);
        #elif defined(TEXTURE_STAGE_1_COLOR_OP_D3DTOP_MODULATE)
            emission = albedo.rgb * SCLIGHTMAP_BRIGHTNESS;
            albedo = diffuse;//vec4(0.,0.,1.,1.);
        #else
            // Multiply
            roughness = diffuse.r * OVERRIDE_ROUGHNESS;
            albedo *= diffuse;
        #endif
        albedo.a = diffuse.a;
    #endif
    /////

    if(isAlphaTestEnabled()) 
    {
        roughness = .8;
        transmission = mix(vec3(0.2), vec3(0.2, 0.6, 0.05), 0.5);
    }

    #if !defined(TEXTURE_STAGE_1_BOUND) && !defined(TEXTURE_STAGE_0_COLOR_ARG2_D3DTA_DIFFUSE)
    // Unlit path, mostly for light flares
    vec3 light = vec3(consts.textureFactor.rgb * FLARE_BRIGHTNESS);
    #else
    vec3 light = computeLighting(albedo.rgb, roughness, transmission);
    #endif

    out_Color0 = vec4(light * albedo.rgb + emission, albedo.a);

    // Tonemap for that fake HDR <3
    out_Color0.rgb = filmicToneMapping(pow(out_Color0.rgb, vec3(1.5))) * 1.2;
    //out_Color0.rgb = fract(in_Position0.xyz);
    #ifdef DEBUG_MATERIAL_TYPE
    out_Color0 = debugShaderType(albedo.rgb, in_Texcoord0.xy);
    #endif

    #ifdef DEBUG_LIGHT_DATA
    out_Color0 = debugLightData(out_Color0);
    #endif

    /////
    // Handle alpha
    #ifdef TEXTURE_STAGE_3_BOUND
    // Assume we're doing an additional terrain layer which needs blending
    vec4 alpha = texture(s3, in_Texcoord3.xy);
    out_Color0.a = alpha.a;
    #endif

    #ifdef TEXTURE_STAGE_0_ALPHA_ARG2_D3DTA_CONSTANT
    out_Color0.a *= consts.Material_Diffuse.a;
    #endif

    // The ALPHA_TEST flag is currently buggy
    //#if defined(ALPHA_TEST)
    if(isAlphaTestEnabled() && out_Color0.a < 0.5)
        discard;
    //#endif
    /////
}
