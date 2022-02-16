#ifndef UNIVERSAL_MOTION_VECTOR_INCLUDED
#define UNIVERSAL_MOTION_VECTOR_INCLUDED
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

float4x4 unity_UnJitteredMatrixVP;
float4x4 unity_PrevMatrixVP;

struct Attributes
{
    float4 position     : POSITION;
    float2 texcoord     : TEXCOORD0;
    float3 positionLast : TEXCOORD4;
};

struct Varyings
{
    float4 positionCS   : SV_POSITION;
    float4 transferPos  : TEXCOORD1;
    float4 transferPosOld : TEXCOORD2;
};

float2 EncodeVelocityToTexture(float2 V)
{
    //将-2~2转换到0-1     *1/4 + 0.5
    //0.499f是中间值，表示速度为0，
    //0是Clear值，表示当前没有速度写入，注意区分和速度为0的区别
    float2 EncodeV =  V.xy * (0.499f * 0.5f) + 32767.0f / 65535.0f;
    return EncodeV;
}

Varyings MotionVectorVertex(Attributes input)
{
    Varyings output = (Varyings)0;

    //当前帧抖动后的裁剪空间坐标
    output.positionCS = TransformObjectToHClip(input.position.xyz);
    #if UNITY_REVERSED_Z
        output.positionCS.z -= unity_MotionVectorsParams.z * output.positionCS.w;
    #else
        output.positionCS.z += unity_MotionVectorsParams.z * output.positionCS.w;
    #endif

    //当前帧未抖动过的裁剪空间坐标
    output.transferPos = mul(unity_UnJitteredMatrixVP, mul(GetObjectToWorldMatrix(), float4(input.position.xyz, 1.0)));

    //上一帧未都动过的裁剪空间坐标
    if(unity_MotionVectorsParams.x > 0)
        output.transferPosOld = mul(unity_PrevMatrixVP, mul(unity_MatrixPreviousM, float4(input.positionLast.xyz, 1.0)));
    else
        output.transferPosOld = mul(unity_PrevMatrixVP, mul(unity_MatrixPreviousM, float4(input.position.xyz, 1.0)));
    
    return output;
}

float2 MotionVectorFragment(Varyings input) : SV_TARGET
{
    float2 screenUV_New = (input.transferPos.xyz / input.transferPos.w);
    float3 screenUV_Old = (input.transferPosOld.xyz / input.transferPosOld.w);
    float2 motionVector = screenUV_New - screenUV_Old;
    #if UNITY_UV_STARTS_AT_TOP
        motionVector.y = -motionVector.y;
    #endif

    motionVector *= 0.5f;
    if (unity_MotionVectorsParams.y == 0) //强制无位移
        motionVector = float2(2, 2);
    return EncodeVelocityToTexture(motionVector);
}
#endif
