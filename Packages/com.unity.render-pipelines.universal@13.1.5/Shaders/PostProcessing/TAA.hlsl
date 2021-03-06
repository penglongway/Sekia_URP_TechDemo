#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
#include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl"
#include "Packages/com.unity.render-pipelines.universal/Shaders/PostProcessing/Common.hlsl"

float4 _Params;
#define _Jitter _Params.xy
#define _Reset _Params.z
float4x4 unity_UnJitteredMatrixVP;
float4x4 unity_PrevMatrixVP;

float2 DecodeVelocityFromTexture(float2 EncodedV)
{
    const float InvDiv = 1.0f / (0.499f * 0.5f);
    float2 V = EncodedV.xy * InvDiv - 32767.0f / 65535.0f * InvDiv;
    return V;
}

Texture2D _CameraDepthTexture;
float4 _CameraDepthTexture_TexelSize;
Texture2D _InputHistoryTexture;
Texture2D _InputTexture;
Texture2D _CameraMotionVectorsTexture;

static const int2 kOffsets3x3[9] =
{
    int2(-1, -1),
    int2( 0, -1),
    int2( 1, -1),
    int2(-1,  0),
    int2( 0,  0),
    int2( 1,  0),
    int2(-1,  1),
    int2( 0,  1),
    int2( 1,  1),
};

float GetSceneColorHdrWeight(float4 SceneColor)
{
    return rcp(SceneColor.x + 4);
}

float3 FastToneMap(in float3 color)
{
    return color.rgb * rcp(color.rgb + 1.0f);
}

float3 FastToneUnmap(in float3 color)
{
    return color.rgb * rcp(1.0f - color.rgb);
}

// Unity自带的转换函数，会在Metal上出错，尚不知道原因
float3 RGB2YCoCg( float3 RGB )
{
    float Y  = dot( RGB, float3(  1, 2,  1 ) );
    float Co = dot( RGB, float3(  2, 0, -2 ) );
    float Cg = dot( RGB, float3( -1, 2, -1 ) );
	
    float3 YCoCg = float3( Y, Co, Cg );
    return YCoCg;
}

float3 YCoCg2RGB( float3 YCoCg )
{
    float Y  = YCoCg.x * 0.25;
    float Co = YCoCg.y * 0.25;
    float Cg = YCoCg.z * 0.25;

    float R = Y + Co - Cg;
    float G = Y + Cg;
    float B = Y - Co - Cg;

    float3 RGB = float3( R, G, B );
    return RGB;
}

float3 TransformColorToTAASpace(float3 Color)
{
    return RGB2YCoCg(Color);
}

//Reinhard Tonemapping
float3 TransformTAASpaceBack(float3 Color)
{
    return YCoCg2RGB(Color);
}

//Cariance Clip：https://zhuanlan.zhihu.com/p/64993622
float3 ClipAABB_ToCenter(float3 aabbMin, float3 aabbMax, float3 prevSample)
{
	float3 p_clip = 0.5 * (aabbMax + aabbMin);
	float3 e_clip = 0.5 * (aabbMax - aabbMin);

	float3 v_clip = prevSample - p_clip;
	float3 v_unit = v_clip.xyz / e_clip;
	float3 a_unit = abs(v_unit);
	float ma_unit = max(a_unit.x, max(a_unit.y, a_unit.z));

	if (ma_unit > 1.0)
		return p_clip + v_clip / ma_unit;
	else
		return prevSample;// point inside aabb
}

float3 ClipHistory(float3 History, float3 BoxMin, float3 BoxMax)
{
    float3 Filtered = (BoxMin + BoxMax) * 0.5f;
    float3 RayOrigin = History;
    float3 RayDir = Filtered - History;
    RayDir = abs( RayDir ) < (1.0/65536.0) ? (1.0/65536.0) : RayDir;
    float3 InvRayDir = rcp( RayDir );
        
    float3 MinIntersect = (BoxMin - RayOrigin) * InvRayDir;
    float3 MaxIntersect = (BoxMax - RayOrigin) * InvRayDir;
    float3 EnterIntersect = min( MinIntersect, MaxIntersect );
    float ClipBlend = max( EnterIntersect.x, max(EnterIntersect.y, EnterIntersect.z ));
    ClipBlend = saturate(ClipBlend);
    return lerp(History, Filtered, ClipBlend);
}

float3 GetPositionWS(float2 screenUV, float deviceDepth, float4x4 invViewProjMatrix)
{
    //屏幕空间的UV转NDC空间 DX平台需要翻转Y
    float4 positionNDC = float4(screenUV * 2.0 - 1.0, deviceDepth, 1.0);
    #if UNITY_UV_STARTS_AT_TOP
        positionNDC.y = -positionNDC.y;
    #endif
    
    //Shader入门精要305页 15.3 再谈全局雾效
    float4 positionWS = mul(invViewProjMatrix, positionNDC);
    return positionWS.xyz / positionWS.w;
}

//计算屏幕空间的前后帧顶点偏移的UV向量
float2 GetMotionVector(float2 screenUV, float deviceDepth)
{
    float3 positionWS = GetPositionWS(screenUV, deviceDepth, UNITY_MATRIX_I_VP);
    float4 curClipPos = mul(unity_UnJitteredMatrixVP, float4(positionWS, 1));
    curClipPos /= curClipPos.w; //需要转换为GL风格平台下的NDC坐标

    float4 preClipPos = mul(unity_PrevMatrixVP, float4(positionWS, 1));
    preClipPos /= preClipPos.w; //需要转换为GL风格平台下的NDC坐标

    float2 motionVector = curClipPos.xy - preClipPos.xy;
    #if UNITY_UV_STARTS_AT_TOP
        motionVector.y = -motionVector.y;
    #endif
    return motionVector * 0.5; //转化为屏幕空间的uv偏移
}

float2 GetClosestFragment(float2 uv, float depth)
{
    float2 k = _CameraDepthTexture_TexelSize.xy;
    const float4 neighborhood = float4(
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv - k, 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + float2(k.x, -k.y), 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + float2(-k.x, k.y), 0).r,
        _CameraDepthTexture.SampleLevel(sampler_PointClamp, uv + k, 0).r
    );
    #if UNITY_REVERSED_Z
    #define COMPARE_DEPTH(a, b) step(b, a)
    #else
    #define COMPARE_DEPTH(a, b) step(a, b)
    #endif
    
    float3 result = float3(0.0, 0.0, depth);
    result = lerp(result, float3(-1.0, -1.0, neighborhood.x), COMPARE_DEPTH(neighborhood.x, result.z));
    result = lerp(result, float3( 1.0, -1.0, neighborhood.y), COMPARE_DEPTH(neighborhood.y, result.z));
    result = lerp(result, float3(-1.0,  1.0, neighborhood.z), COMPARE_DEPTH(neighborhood.z, result.z));
    result = lerp(result, float3( 1.0,  1.0, neighborhood.w), COMPARE_DEPTH(neighborhood.w, result.z));
    return (uv + result.xy * k);
}

