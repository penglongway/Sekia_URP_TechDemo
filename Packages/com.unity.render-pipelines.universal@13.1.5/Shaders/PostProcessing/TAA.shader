Shader "Hidden/Universal Render Pipeline/TAA"
{
    HLSLINCLUDE
    
        #pragma target 3.5
        #include "TAA.hlsl"

        struct ProceduralAttributes
        {
            uint vertexID : VERTEXID_SEMANTIC;
        };
        
        struct ProceduralVaryings
        {
            float4 positionCS : SV_POSITION;
            float2 uv : TEXCOORD;
        };
        
        ProceduralVaryings ProceduralVert (ProceduralAttributes input)
        {
            ProceduralVaryings output;
            //在裁剪空间中画一个等边三角形 垂直边长度为4 刚好覆盖[-1, 1]范围的NDC空间
            //因为DX风格平台的NDC空间是翻转的 同样的顶点坐标导致三角形上下翻转
            //NDC空间的(-1, -1, 1)对于GL平台是左下角 对于DX平台是左上角
            output.positionCS = GetFullScreenTriangleVertexPosition(input.vertexID);
            //差值到frag后 uv用于屏幕采样 在DX和GL风格平台都是左下角为[0, 0]
            output.uv = GetFullScreenTriangleTexCoord(input.vertexID);
            return output;
        }

        float4 TAAFrag(Varyings input) : SV_Target
        {
            //输入颜色 无抖动
            float2 uv = input.uv - _Jitter; //原UV = 抖动后UV - UV偏移
            float3 InputColor = TransformColorToTAASpace(SAMPLE_TEXTURE2D_X(_InputTexture, sampler_LinearClamp, uv).rgb);
            if(_Reset)
                return float4(TransformTAASpaceBack(InputColor), 1);

            float depth = SAMPLE_DEPTH_TEXTURE(_CameraDepthTexture, sampler_PointClamp, input.uv);
            if(depth ==0)
                return float4(TransformTAASpaceBack(InputColor), 1);

            //SV_POSITION作为pixel shader输入时有特殊意义 描述该片元位置
            //SV_POSITION的xy表示像素坐标 如0-1920/0-1080 只有DX9上没有0.5像素偏移 左下角为[0.5, 0.5] 
            //SV_POSITION的z表示深度值？ 可能是rawDepth并应用了Z-Reverse
            //SV_POSITION的w表示观察空间z值 可能有基于平台的差异？
            float2 Motion = GetMotionVector(input.positionCS.xy, depth); //计算Motion时不会添加抖动
            #if _USE_MOTION_VECTOR_BUFFER //仅用于骨骼动画
                //inside：采样速度buffer时寻找周围离相机最近的点 使运动的边缘有更好的效果
                float2 closest = GetClosestFragment(input.uv, depth);
                float2 SampleVelocity = SAMPLE_TEXTURE2D(_CameraMotionVectorsTexture, sampler_PointClamp, closest).xy;
                if(SampleVelocity.x > 0)
                    Motion = DecodeVelocityFromTexture(SampleVelocity);
            #endif

            //历史颜色 用无抖动的Motion尽量提高精度
            //可选：对历史结果进行锐化处理 Catmull-Rom方式的采样
            float2 HistoryUV = input.uv - Motion;
            float3 HistoryColor = TransformColorToTAASpace(_InputHistoryTexture.Sample(sampler_LinearClamp, HistoryUV).rgb);

            //获取输入uv周围9个像素的亮度范围
            //Variance clip
            float3 M1 = 0;
            float3 M2 = 0;
            UNITY_UNROLL
            for(int k = 0; k < 9; k++)
            {
                float3 C = TransformColorToTAASpace(_InputTexture.Sample(sampler_PointClamp, uv, kOffsets3x3[k]).rgb);
                M1 += C;
                M2 += C * C;
            }
            M1 *= (1 / 9.0f);
            M2 *= (1 / 9.0f);
            float3 StdDev = sqrt(abs(M2 - M1 * M1));
            float3 AABBMin = M1 - 1.25 * StdDev; //输入uv周围9个像素的RGB最小值
            float3 AABBMax = M1 + 1.25 * StdDev; //输入uv周围9个像素的RGB最大值
            
            //如果不加判断混合当前帧和历史帧就会出现Ghosting现象
            //没有深度的地方Ghosting不会消除？
            //HistoryColor与InputColor过大时Clamp HistoryColor至InputColor亮度范围边缘
            HistoryColor = ClipHistory(HistoryColor, AABBMin, AABBMax);
            float BlendFactor = saturate(0.05 + (abs(Motion.x) + abs(Motion.y)) * 10);
            float3 result = lerp(HistoryColor, InputColor, BlendFactor);
            result = TransformTAASpaceBack(result);
            return float4(result, 1);
        }
    ENDHLSL

    SubShader
    {
        Tags { "RenderPipeline" = "UniversalPipeline"}
        ZTest Always ZWrite Off Cull Off
        
        Pass
        {
            Name "TAA"
            HLSLPROGRAM
                #pragma multi_compile _ _USE_MOTION_VECTOR_BUFFER
                #pragma vertex ProceduralVert
                #pragma fragment TAAFrag
            ENDHLSL
        }
    }
}
