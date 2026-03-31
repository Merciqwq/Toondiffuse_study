Shader "Custom/ToonCharacterRamp"
{
    Properties
    {
        // ===== 主体固有色 =====
        _BaseColor("Base Color", Color) = (1,1,1,1)

        // ===== Ramp 贴图 =====
        // 横向采样：X 轴表示从暗到亮，Y 轴通常固定为 0.5
        _RampTex("Ramp Texture", 2D) = "white" {}
        _RampUVY("Ramp UV Y", Range(0,1)) = 0.5

        // ===== Toon 明暗分界 =====
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05

        // ===== 高光（Specular） =====
        _SpecColor("Spec Color", Color) = (1,1,1,1)
        _SpecPower("Spec Power", Range(1,128)) = 32
        _SpecThreshold("Spec Threshold", Range(0,1)) = 0.5
        _SpecSoftness("Spec Softness", Range(0.001,0.3)) = 0.05

        // ===== 边缘光（Rim Light） =====
        _RimColor("Rim Color", Color) = (0.6,0.8,1.0,1)
        _RimPower("Rim Power", Range(0.1,8)) = 2
        _RimThreshold("Rim Threshold", Range(0,1)) = 0.5
        _RimSoftness("Rim Softness", Range(0.001,0.3)) = 0.05

        // ===== 描边（Outline） =====
        _OutlineColor("Outline Color", Color) = (0,0,0,1)
        _OutlineWidth("Outline Width", Range(0.0, 0.1)) = 0.02
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
        }

        // =========================================================
        // Pass 1: 主体渲染
        // 包含：Ramp 漫反射 + 高光 + 边缘光
        // =========================================================
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            Cull Back
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // ===== URP 基础库 =====
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ===== Ramp Texture 采样器 =====
            TEXTURE2D(_RampTex);//  Ramp 纹理
            SAMPLER(sampler_RampTex);// 纹理采样器

            struct Attributes
            {
                float4 positionOS : POSITION; // 顶点位置（物体空间）
                float3 normalOS   : NORMAL;   // 顶点法线（物体空间）
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 裁剪空间坐标
                float3 normalWS   : TEXCOORD0;   // 世界空间法线
                float3 positionWS : TEXCOORD1;   // 世界空间位置
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;

                float4 _RampTex_ST;
                float _RampUVY;

                float _ShadowThreshold;
                float _ShadowSoftness;

                float4 _SpecColor;
                float _SpecPower;
                float _SpecThreshold;
                float _SpecSoftness;

                float4 _RimColor;
                float _RimPower;
                float _RimThreshold;
                float _RimSoftness;

                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // 物体空间 -> 裁剪空间，决定顶点在屏幕上的位置
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);

                // 法线转到世界空间，用于与光方向、视线方向做 dot
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                // 顶点位置转到世界空间，用于计算视线方向
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // ===== 法线归一化 =====
                // 保证法线长度为 1，否则点乘结果会被向量长度污染
                float3 N = normalize(IN.normalWS);

                // ===== 获取主方向光 =====
                Light mainLight = GetMainLight();

                // URP 中 mainLight.direction 表示光线传播方向
                // 漫反射计算通常取反，得到“从表面指向光源”的方向
                float3 L = normalize(-mainLight.direction);

                // ===== Ramp 漫反射 =====
                // N·L 表示表面有多朝向光源，范围压到 0~1
                float ndl = saturate(dot(N, L));

                // 用 threshold + softness 先把受光值压到适合卡通分层的区间
                float rampInput = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );

                // Ramp 横向采样：X 是明暗输入，Y 通常固定在 0.5
                float2 rampUV = float2(rampInput, _RampUVY);

                // 从 Ramp 纹理中取出当前明暗下应使用的颜色
                float3 rampColor = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, rampUV).rgb;

                // BaseColor 作为固有色，Ramp 作为受光调色结果
                float3 diffuse = _BaseColor.rgb * rampColor;

                // ===== 视线方向 =====
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // ===== Toon 高光（Specular） =====
                // 半角向量：光方向与视线方向的中间方向
                float3 H = normalize(L + V);

                // N·H 越大，高光越强
                float ndh = saturate(dot(N, H));
                float spec = pow(ndh, _SpecPower);

                // 用 smoothstep 做硬边化，让高光更像风格化块面
                spec = smoothstep(
                    _SpecThreshold - _SpecSoftness,
                    _SpecThreshold + _SpecSoftness,
                    spec
                );

                float3 specular = spec * _SpecColor.rgb;

                // ===== 边缘光（Rim Light） =====
                // N·V 越小，说明越接近轮廓边缘，Rim 越强
                float rim = 1.0 - saturate(dot(N, V));

                // 控制边缘光宽度
                rim = pow(rim, _RimPower);

                // 用 smoothstep 控制边缘光出现的位置和软硬
                rim = smoothstep(
                    _RimThreshold - _RimSoftness,
                    _RimThreshold + _RimSoftness,
                    rim
                );

                float3 rimColor = rim * _RimColor.rgb;

                // ===== 最终颜色 =====
                // 最终输出 = Ramp 漫反射 + 高光 + 边缘光
                float3 finalColor = diffuse + specular + rimColor;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // =========================================================
        // Pass 2: 描边
        // 使用 Inverted Hull：沿法线外扩，再只画背面
        // =========================================================
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }

            Cull Front
            ZWrite On
            ZTest LEqual

            HLSLPROGRAM
            #pragma vertex vertOutline
            #pragma fragment fragOutline

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;

                float4 _RampTex_ST;
                float _RampUVY;

                float _ShadowThreshold;
                float _ShadowSoftness;

                float4 _SpecColor;
                float _SpecPower;
                float _SpecThreshold;
                float _SpecSoftness;

                float4 _RimColor;
                float _RimPower;
                float _RimThreshold;
                float _RimSoftness;

                float4 _OutlineColor;
                float _OutlineWidth;
            CBUFFER_END

            Varyings vertOutline(Attributes IN)
            {
                Varyings OUT;

                // 沿法线方向把模型向外推一点，形成膨胀壳
                float3 positionOS = IN.positionOS.xyz + IN.normalOS * _OutlineWidth;
                OUT.positionCS = TransformObjectToHClip(positionOS);

                return OUT;
            }

            half4 fragOutline(Varyings IN) : SV_Target
            {
                return half4(_OutlineColor.rgb, 1.0);
            }
            ENDHLSL
        }
    }
}
