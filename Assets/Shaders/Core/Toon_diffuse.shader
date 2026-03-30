Shader "Custom/ToonDiffuse_Beginner"//Shader名字
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (0.7,0.7,0.7,1)
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05
        // _BaseColor：亮面颜色
        // _ShadowColor：暗面颜色
        // _ShadowThreshold：亮暗分界线位置
        // _ShadowSoftness：分界线软硬程度
        //range滑动条
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
            // Opaque：这个材质是不透明物体
            // UniversalPipeline：告诉 Unity，这个 shader 是给 URP 用的

            // 如果不写 RenderPipeline="UniversalPipeline"，在 URP 项目里经常会出兼容问题。Unity 官方的 URP 自定义 shader 示例也都使用这个标签。
        }

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // 顶点着色器函数叫 vert
            // 片元着色器函数叫 frag

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                //这是从模型顶点数据里读进来的东西。

                // positionOS
                // 顶点位置
                // OS = Object Space，物体空间
                // normalOS
                // 顶点法线
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                //positionHCS
                // HCS = Homogeneous Clip Space
                // 裁剪空间坐标
                // 它决定顶点最后画在屏幕哪里
                // normalWS
                // WS = World Space
                // 世界空间法线
                // 我们后面要拿它算光照
            };

            CBUFFER_START(UnityPerMaterial)//这部分就是把 Properties 里的材质参数真正带进 HLSL 代码里使用
                float4 _BaseColor;
                float4 _ShadowColor;
                float _ShadowThreshold;
                float _ShadowSoftness;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;//创建一个输出变量，准备把结果传给片元着色器
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);//把模型顶点从“物体空间”转换到“裁剪空间”。
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);//这里把法线从物体空间转成世界空间。
                return OUT;//把处理好的数据交给片元着色器。
            }

            half4 frag(Varyings IN) : SV_Target //SV_Target 表示输出到当前渲染目标，也就是屏幕或缓冲区。
            {
                float3 N = normalize(IN.normalWS);//法线归一化

                Light mainLight = GetMainLight();//取主光

                //URP 中主方向光方向通常表示“光线传播方向”
                //漫反射计算时通常取反，得到“从表面指向光源”的方向
                float3 L = normalize(-mainLight.direction);

                float ndl = saturate(dot(N, L)); //计算 NdotL

                float lightBand = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );
                // 先按功能理解：

                // _ShadowThreshold
                // 决定亮暗边界在哪
                // _ShadowSoftness
                // 决定边界是硬还是软

                // 如果你把 _ShadowSoftness 调得很小，它会更像硬切。
                // 调大一点，边界会柔和一些。

                // 本质上这句就是把原本平滑的 ndl，压成更风格化的分层结果。

                float3 diffuse = lerp(_ShadowColor.rgb, _BaseColor.rgb, lightBand);//亮面和暗面插值

                return half4(diffuse, 1.0);//输出最终颜色
            }
            ENDHLSL
        }
    }
}