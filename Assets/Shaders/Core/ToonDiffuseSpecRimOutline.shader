Shader "Custom/ToonDiffuseSpecRimOutline"
{
    Properties
    {
        // ===== Toon Diffuse =====
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (0.35,0.35,0.4,1)
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05

        // ===== Specular =====
        _SpecColor("Spec Color", Color) = (1,1,1,1)
        _SpecPower("Spec Power", Range(1,128)) = 32
        _SpecThreshold("Spec Threshold", Range(0,1)) = 0.5
        _SpecSoftness("Spec Softness", Range(0.001,0.3)) = 0.05

        // ===== Rim Light =====
        _RimColor("Rim Color", Color) = (0.6,0.8,1.0,1)
        _RimPower("Rim Power", Range(0.1,8)) = 2
        _RimThreshold("Rim Threshold", Range(0,1)) = 0.5
        _RimSoftness("Rim Softness", Range(0.001,0.3)) = 0.05

        // ===== Outline =====
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

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;
                float4 _ShadowColor;
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

                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);

                Light mainLight = GetMainLight();
                float3 L = normalize(-mainLight.direction);

                // ===== Toon Diffuse =====
                float ndl = saturate(dot(N, L));
                float lightBand = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );

                float3 diffuse = lerp(_ShadowColor.rgb, _BaseColor.rgb, lightBand);

                // ===== View Dir =====
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // ===== Specular =====
                float3 H = normalize(L + V);
                float ndh = saturate(dot(N, H));
                float spec = pow(ndh, _SpecPower);
                spec = smoothstep(
                    _SpecThreshold - _SpecSoftness,
                    _SpecThreshold + _SpecSoftness,
                    spec
                );
                float3 specular = spec * _SpecColor.rgb;

                // ===== Rim =====
                float rim = 1.0 - saturate(dot(N, V));
                rim = pow(rim, _RimPower);
                rim = smoothstep(
                    _RimThreshold - _RimSoftness,
                    _RimThreshold + _RimSoftness,
                    rim
                );
                float3 rimColor = rim * _RimColor.rgb;

                float3 finalColor = diffuse + specular + rimColor;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }

        // =========================================================
        // Pass 2: Outline
        // =========================================================
        Pass
        {
            Name "Outline"
            Tags { "LightMode"="SRPDefaultUnlit" }

            // 只画正面剔除后的背面
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
                float4 _ShadowColor;
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

                // 沿法线方向把模型向外推一点
                float3 positionOS = IN.positionOS.xyz + IN.normalOS * _OutlineWidth;

                OUT.positionCS = TransformObjectToHClip(positionOS);

                return OUT;
            }

            half4 fragOutline(Varyings IN) : SV_Target
            {
                return half4(_OutlineColor.rgb, 1.0);// 轮廓颜色
            }
            ENDHLSL
        }
    }
}