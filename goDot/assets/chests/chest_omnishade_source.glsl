#ifdef VERTEX
#version 300 es

#define HLSLCC_ENABLE_UNIFORM_BUFFERS 1
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
#define UNITY_UNIFORM
#else
#define UNITY_UNIFORM uniform
#endif
#define UNITY_SUPPORTS_UNIFORM_LOCATION 1
#if UNITY_SUPPORTS_UNIFORM_LOCATION
#define UNITY_LOCATION(x) layout(location = x)
#define UNITY_BINDING(x) layout(binding = x, std140)
#else
#define UNITY_LOCATION(x)
#define UNITY_BINDING(x) layout(std140)
#endif
uniform 	vec4 hlslcc_mtx4x4unity_CameraToWorld[4];
uniform 	vec4 hlslcc_mtx4x4unity_MatrixVP[4];
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
UNITY_BINDING(0) uniform UnityPerDraw {
#endif
	UNITY_UNIFORM vec4                hlslcc_mtx4x4unity_ObjectToWorld[4];
	UNITY_UNIFORM vec4                hlslcc_mtx4x4unity_WorldToObject[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_LODFade;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_WorldTransformParams;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RenderingLayer;
	UNITY_UNIFORM mediump vec4                unity_LightData;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_LightIndices[2];
	UNITY_UNIFORM vec4                unity_ProbesOcclusion;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_SpecCube0_HDR;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_SpecCube1_HDR;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_BoxMax;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_BoxMin;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_ProbePosition;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_BoxMax;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_BoxMin;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_ProbePosition;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_LightmapST;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_DynamicLightmapST;
	UNITY_UNIFORM mediump vec4                unity_SHAr;
	UNITY_UNIFORM mediump vec4                unity_SHAg;
	UNITY_UNIFORM mediump vec4                unity_SHAb;
	UNITY_UNIFORM mediump vec4                unity_SHBr;
	UNITY_UNIFORM mediump vec4                unity_SHBg;
	UNITY_UNIFORM mediump vec4                unity_SHBb;
	UNITY_UNIFORM mediump vec4                unity_SHC;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RendererBounds_Min;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RendererBounds_Max;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXhlslcc_mtx4x4unity_MatrixPreviousM[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXhlslcc_mtx4x4unity_MatrixPreviousMI[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_MotionVectorsParams;
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
};
#endif
in highp vec4 in_POSITION0;
in highp vec3 in_NORMAL0;
in highp vec4 in_TEXCOORD0;
in highp vec4 in_TEXCOORD1;
out mediump vec4 vs_TEXCOORD0;
out highp vec3 vs_TEXCOORD1;
out mediump float vs_TEXCOORD10;
out mediump vec3 vs_TEXCOORD2;
out mediump vec3 vs_TEXCOORD4;
vec4 u_xlat0;
vec4 u_xlat1;
float u_xlat6;
void main()
{
    u_xlat0 = in_POSITION0.yyyy * hlslcc_mtx4x4unity_ObjectToWorld[1];
    u_xlat0 = hlslcc_mtx4x4unity_ObjectToWorld[0] * in_POSITION0.xxxx + u_xlat0;
    u_xlat0 = hlslcc_mtx4x4unity_ObjectToWorld[2] * in_POSITION0.zzzz + u_xlat0;
    u_xlat0 = u_xlat0 + hlslcc_mtx4x4unity_ObjectToWorld[3];
    u_xlat1 = u_xlat0.yyyy * hlslcc_mtx4x4unity_MatrixVP[1];
    u_xlat1 = hlslcc_mtx4x4unity_MatrixVP[0] * u_xlat0.xxxx + u_xlat1;
    u_xlat1 = hlslcc_mtx4x4unity_MatrixVP[2] * u_xlat0.zzzz + u_xlat1;
    gl_Position = hlslcc_mtx4x4unity_MatrixVP[3] * u_xlat0.wwww + u_xlat1;
    u_xlat0.xy = in_TEXCOORD0.xy;
    u_xlat0.zw = in_TEXCOORD1.xy;
    vs_TEXCOORD0 = u_xlat0;
    u_xlat0.xyz = in_POSITION0.yyy * hlslcc_mtx4x4unity_ObjectToWorld[1].xyz;
    u_xlat0.xyz = hlslcc_mtx4x4unity_ObjectToWorld[0].xyz * in_POSITION0.xxx + u_xlat0.xyz;
    u_xlat0.xyz = hlslcc_mtx4x4unity_ObjectToWorld[2].xyz * in_POSITION0.zzz + u_xlat0.xyz;
    u_xlat0.xyz = u_xlat0.xyz + hlslcc_mtx4x4unity_ObjectToWorld[3].xyz;
    vs_TEXCOORD1.xyz = u_xlat0.xyz;
    u_xlat0.xyz = (-u_xlat0.xyz) + hlslcc_mtx4x4unity_CameraToWorld[3].xyz;
    vs_TEXCOORD4.xyz = u_xlat0.xyz;
    u_xlat0.x = dot(in_NORMAL0.xyz, hlslcc_mtx4x4unity_WorldToObject[0].xyz);
    u_xlat0.y = dot(in_NORMAL0.xyz, hlslcc_mtx4x4unity_WorldToObject[1].xyz);
    u_xlat0.z = dot(in_NORMAL0.xyz, hlslcc_mtx4x4unity_WorldToObject[2].xyz);
    u_xlat6 = dot(u_xlat0.xyz, u_xlat0.xyz);
    u_xlat6 = max(u_xlat6, 1.17549435e-38);
    u_xlat6 = inversesqrt(u_xlat6);
    u_xlat0.xyz = vec3(u_xlat6) * u_xlat0.xyz;
    vs_TEXCOORD2.xyz = u_xlat0.xyz;
    vs_TEXCOORD10 = 0.0;
    return;
}

#endif
#ifdef FRAGMENT
#version 300 es

precision highp float;
precision highp int;
#define HLSLCC_ENABLE_UNIFORM_BUFFERS 1
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
#define UNITY_UNIFORM
#else
#define UNITY_UNIFORM uniform
#endif
#define UNITY_SUPPORTS_UNIFORM_LOCATION 1
#if UNITY_SUPPORTS_UNIFORM_LOCATION
#define UNITY_LOCATION(x) layout(location = x)
#define UNITY_BINDING(x) layout(binding = x, std140)
#else
#define UNITY_LOCATION(x)
#define UNITY_BINDING(x) layout(std140)
#endif
uniform 	vec4 _MainLightPosition;
uniform 	mediump vec4 _MainLightColor;
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
UNITY_BINDING(0) uniform UnityPerDraw {
#endif
	UNITY_UNIFORM vec4                hlslcc_mtx4x4unity_ObjectToWorld[4];
	UNITY_UNIFORM vec4                hlslcc_mtx4x4unity_WorldToObject[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_LODFade;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_WorldTransformParams;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RenderingLayer;
	UNITY_UNIFORM mediump vec4                unity_LightData;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_LightIndices[2];
	UNITY_UNIFORM vec4                unity_ProbesOcclusion;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_SpecCube0_HDR;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedXunity_SpecCube1_HDR;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_BoxMax;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_BoxMin;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube0_ProbePosition;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_BoxMax;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_BoxMin;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_SpecCube1_ProbePosition;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_LightmapST;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_DynamicLightmapST;
	UNITY_UNIFORM mediump vec4                unity_SHAr;
	UNITY_UNIFORM mediump vec4                unity_SHAg;
	UNITY_UNIFORM mediump vec4                unity_SHAb;
	UNITY_UNIFORM mediump vec4                unity_SHBr;
	UNITY_UNIFORM mediump vec4                unity_SHBg;
	UNITY_UNIFORM mediump vec4                unity_SHBb;
	UNITY_UNIFORM mediump vec4                unity_SHC;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RendererBounds_Min;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_RendererBounds_Max;
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXhlslcc_mtx4x4unity_MatrixPreviousM[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXhlslcc_mtx4x4unity_MatrixPreviousMI[4];
	UNITY_UNIFORM vec4 Xhlslcc_UnusedXunity_MotionVectorsParams;
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
};
#endif
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
UNITY_BINDING(1) uniform UnityPerMaterial {
#endif
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_TriplanarSharpness;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_WorldSpaceTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_WorldSpaceTexMask_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_WorldSpaceTexColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_WorldSpaceTexBrightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_WorldSpaceTexAlpha;
	UNITY_UNIFORM mediump vec4                _MainTex_ST;
	UNITY_UNIFORM mediump vec4                _Color;
	UNITY_UNIFORM mediump float                _Brightness;
	UNITY_UNIFORM mediump float                _Contrast;
	UNITY_UNIFORM mediump float                _Saturation;
	UNITY_UNIFORM mediump float                _IgnoreMainTexAlpha;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_TopTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_TopColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_TopBrightness;
	UNITY_UNIFORM mediump float                _DiffuseWrap;
	UNITY_UNIFORM mediump float                _DiffuseBrightness;
	UNITY_UNIFORM mediump float                _DiffuseContrast;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_SpecularTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_SpecularColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_SpecularBrightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_SpecularSmoothness;
	UNITY_UNIFORM mediump vec4                _RimColor;
	UNITY_UNIFORM mediump float                _RimAmount;
	UNITY_UNIFORM mediump float                _RimContrast;
	UNITY_UNIFORM mediump float                _RimInverse;
	UNITY_UNIFORM mediump vec3 Xhlslcc_UnusedX_RimDirection;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_ReflectionTex_HDR;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ReflectionAmount;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_ReflectionColor;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_NormalTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_NormalTex2_ST;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_NormalStrength;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_NormalTopTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_LightmapTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_LightmapTex_HDR;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_LightmapColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_LightmapBrightness;
	UNITY_UNIFORM mediump vec4                _Emissive;
	UNITY_UNIFORM mediump vec4                _EmissiveTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_MatCapTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_MatCapColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_MatCapBrightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_MatCapContrast;
	UNITY_UNIFORM mediump vec3 Xhlslcc_UnusedX_MatCapRot;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_VertexColorsAmount;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_VertexColorsContrast;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_DetailTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_DetailColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_DetailBrightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_DetailContrast;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer1Tex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer1Color;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer1Brightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer1Alpha;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer1VertexColor;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer2Tex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer2Color;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer2Brightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer2Alpha;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer2VertexColor;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer3Tex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_Layer3Color;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer3Brightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer3Alpha;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_Layer3VertexColor;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_TransparencyMaskTex_ST;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_TransparencyMaskAmount;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_TransparencyMaskContrast;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_TransparencyMaskInvert;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_HeightColorsColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_HeightColorsAlpha;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_HeightColorsHeight;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_HeightColorsEdgeThickness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_HeightColorsThickness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_HeightColorsSpace;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_HeightColorsTex_ST;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_ShadowOverlayTex_ST;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ShadowOverlayBrightness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ShadowOverlaySpeedU;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ShadowOverlaySpeedV;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ShadowOverlaySwayAmount;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_OutlineWidth;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_OutlineColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_AnimeThreshold1;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_AnimeColor1;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_AnimeThreshold2;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_AnimeColor2;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_AnimeColor3;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_AnimeSoftness;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_CameraFadeStart;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_CameraFadeEnd;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileDiscardUV;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV3U0;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV3U1;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV3U2;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV3U3;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV2U0;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV2U1;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV2U2;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV2U3;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV1U0;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV1U1;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV1U2;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV1U3;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV0U0;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV0U1;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV0U2;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_UVTileV0U3;
	UNITY_UNIFORM mediump float                _AmbientBrightness;
	UNITY_UNIFORM mediump vec4 Xhlslcc_UnusedX_ShadowColor;
	UNITY_UNIFORM mediump float Xhlslcc_UnusedX_ZOffset;
#if HLSLCC_ENABLE_UNIFORM_BUFFERS
};
#endif
UNITY_LOCATION(0) uniform mediump sampler2D _MainTex;
UNITY_LOCATION(1) uniform mediump sampler2D _EmissiveTex;
in mediump vec4 vs_TEXCOORD0;
in mediump vec3 vs_TEXCOORD2;
in mediump vec3 vs_TEXCOORD4;
layout(location = 0) out mediump vec4 SV_Target0;
mediump vec4 u_xlat16_0;
mediump vec3 u_xlat16_1;
mediump vec4 u_xlat16_2;
mediump vec3 u_xlat16_3;
vec3 u_xlat4;
mediump vec3 u_xlat16_4;
bool u_xlatb4;
vec3 u_xlat5;
bvec3 u_xlatb5;
mediump float u_xlat16_6;
vec3 u_xlat10;
bool u_xlatb10;
mediump float u_xlat16_18;
mediump float u_xlat16_19;
void main()
{
    u_xlat16_0.x = dot(vs_TEXCOORD2.xyz, vs_TEXCOORD2.xyz);
    u_xlat16_0.x = inversesqrt(u_xlat16_0.x);
    u_xlat16_0.xyz = u_xlat16_0.xxx * vs_TEXCOORD2.xyz;
    u_xlat16_1.x = u_xlat16_0.y * u_xlat16_0.y;
    u_xlat16_1.x = u_xlat16_0.x * u_xlat16_0.x + (-u_xlat16_1.x);
    u_xlat16_2 = u_xlat16_0.yzzx * u_xlat16_0.xyzz;
    u_xlat16_3.x = dot(unity_SHBr, u_xlat16_2);
    u_xlat16_3.y = dot(unity_SHBg, u_xlat16_2);
    u_xlat16_3.z = dot(unity_SHBb, u_xlat16_2);
    u_xlat16_1.xyz = unity_SHC.xyz * u_xlat16_1.xxx + u_xlat16_3.xyz;
    u_xlat16_0.w = 1.0;
    u_xlat16_2.x = dot(unity_SHAr, u_xlat16_0);
    u_xlat16_2.y = dot(unity_SHAg, u_xlat16_0);
    u_xlat16_2.z = dot(unity_SHAb, u_xlat16_0);
    u_xlat16_1.xyz = u_xlat16_1.xyz + u_xlat16_2.xyz;
    u_xlat4.xyz = log2(abs(u_xlat16_1.xyz));
    u_xlat4.xyz = u_xlat4.xyz * vec3(0.416666657, 0.416666657, 0.416666657);
    u_xlat4.xyz = exp2(u_xlat4.xyz);
    u_xlat4.xyz = u_xlat4.xyz * vec3(1.05499995, 1.05499995, 1.05499995) + vec3(-0.0549999997, -0.0549999997, -0.0549999997);
    u_xlatb5.xyz = greaterThanEqual(vec4(0.00313080009, 0.00313080009, 0.00313080009, 0.0), u_xlat16_1.xyzx).xyz;
    u_xlat16_1.xyz = u_xlat16_1.xyz * vec3(12.9232101, 12.9232101, 12.9232101);
    {
        vec3 hlslcc_movcTemp = u_xlat4;
        hlslcc_movcTemp.x = (u_xlatb5.x) ? u_xlat16_1.x : u_xlat4.x;
        hlslcc_movcTemp.y = (u_xlatb5.y) ? u_xlat16_1.y : u_xlat4.y;
        hlslcc_movcTemp.z = (u_xlatb5.z) ? u_xlat16_1.z : u_xlat4.z;
        u_xlat4 = hlslcc_movcTemp;
    }
    u_xlat16_1.xyz = max(u_xlat4.xyz, vec3(0.0, 0.0, 0.0));
    u_xlat16_18 = _AmbientBrightness + -0.0799999982;
    u_xlat16_1.xyz = vec3(u_xlat16_18) * u_xlat16_1.xyz;
    u_xlat16_18 = dot(vs_TEXCOORD4.xyz, vs_TEXCOORD4.xyz);
    u_xlat16_18 = inversesqrt(u_xlat16_18);
    u_xlat16_2.xyz = vec3(u_xlat16_18) * vs_TEXCOORD4.xyz;
    u_xlat16_18 = dot(u_xlat16_2.xyz, u_xlat16_0.xyz);
    u_xlat4.x = dot(_MainLightPosition.xyz, u_xlat16_0.xyz);
    u_xlat4.x = max(u_xlat4.x, 0.0);
    u_xlat16_0.x = max(u_xlat16_18, 0.0);
    u_xlat16_6 = (-u_xlat16_0.x) + 1.0;
    u_xlatb10 = _RimInverse==0.0;
    u_xlat16_0.x = (u_xlatb10) ? u_xlat16_6 : u_xlat16_0.x;
    u_xlat16_0.x = log2(u_xlat16_0.x);
    u_xlat16_0.x = u_xlat16_0.x * _RimContrast;
    u_xlat16_0.x = exp2(u_xlat16_0.x);
    u_xlat16_0.x = u_xlat16_0.x * _RimAmount;
    u_xlat16_0.x = min(u_xlat16_0.x, 1.0);
    u_xlat16_0.x = u_xlat16_0.x * _RimColor.w;
    u_xlat10.xyz = u_xlat16_0.xxx * _RimColor.xyz;
    u_xlat16_0.x = (-u_xlat4.x) + 1.0;
    u_xlat16_0.x = _DiffuseWrap * u_xlat16_0.x + u_xlat4.x;
    u_xlat16_0.x = max(u_xlat16_0.x, 0.0);
    u_xlat16_0.x = log2(u_xlat16_0.x);
    u_xlat16_0.x = u_xlat16_0.x * _DiffuseContrast;
    u_xlat16_0.x = exp2(u_xlat16_0.x);
    u_xlat16_6 = _DiffuseBrightness + -0.0700000003;
    u_xlat16_0.x = u_xlat16_6 * u_xlat16_0.x;
    u_xlat5.xyz = _MainLightColor.xyz * unity_ProbesOcclusion.xxx;
    u_xlat5.xyz = u_xlat16_0.xxx * u_xlat5.xyz;
    u_xlatb4 = unity_LightData.z==1.0;
    u_xlat16_0.xyz = (bool(u_xlatb4)) ? u_xlat5.xyz : vec3(0.0, 0.0, 0.0);
    u_xlat16_2.xy = vs_TEXCOORD0.xy * _MainTex_ST.xy + _MainTex_ST.zw;
    u_xlat16_2 = texture(_MainTex, u_xlat16_2.xy);
    u_xlat16_3.xyz = log2(u_xlat16_2.xyz);
    u_xlat16_18 = u_xlat16_2.w;
    u_xlat16_18 = clamp(u_xlat16_18, 0.0, 1.0);
    u_xlat16_3.xyz = u_xlat16_3.xyz * vec3(vec3(_Contrast, _Contrast, _Contrast));
    u_xlat16_3.xyz = exp2(u_xlat16_3.xyz);
    u_xlat16_19 = _Brightness + 0.0500000007;
    u_xlat16_2.xyz = vec3(u_xlat16_19) * u_xlat16_3.xyz;
    u_xlatb4 = _IgnoreMainTexAlpha==0.0;
    u_xlat16_2.w = (u_xlatb4) ? u_xlat16_18 : 1.0;
    u_xlat16_2 = u_xlat16_2 * _Color;
    u_xlat16_0.xyz = u_xlat16_2.xyz * u_xlat16_0.xyz + u_xlat10.xyz;
    u_xlat16_3.xy = vs_TEXCOORD0.xy * _EmissiveTex_ST.xy + _EmissiveTex_ST.zw;
    u_xlat16_4.xyz = texture(_EmissiveTex, u_xlat16_3.xy).xyz;
    u_xlat16_0.xyz = _Emissive.xyz * u_xlat16_4.xyz + u_xlat16_0.xyz;
    u_xlat16_0.xyz = u_xlat16_2.xyz * u_xlat16_1.xyz + u_xlat16_0.xyz;
    SV_Target0.w = u_xlat16_2.w;
    u_xlat16_18 = dot(u_xlat16_0.xyz, vec3(0.212672904, 0.715152204, 0.0721750036));
    u_xlat16_0.xyz = (-vec3(u_xlat16_18)) + u_xlat16_0.xyz;
    SV_Target0.xyz = vec3(vec3(_Saturation, _Saturation, _Saturation)) * u_xlat16_0.xyz + vec3(u_xlat16_18);
    return;
}

#endif
