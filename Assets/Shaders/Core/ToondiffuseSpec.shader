Shader "Custom/ToonDiffuseSpec_Beginner"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _ShadowColor("Shadow Color", Color) = (0.35,0.35,0.4,1)
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05

        _SpecColor("Spec Color", Color) = (1,1,1,1)
        _SpecPower("Spec Power", Range(1,128)) = 32
        _SpecThreshold("Spec Threshold", Range(0,1)) = 0.5
        _SpecSoftness("Spec Softness", Range(0.001,0.3)) = 0.05
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"
            "RenderPipeline"="UniversalPipeline"
            "Queue"="Geometry"
        }

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

                float ndl = saturate(dot(N, L));
                float lightBand = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );

                float3 diffuse = lerp(_ShadowColor.rgb, _BaseColor.rgb, lightBand);

                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));
                float3 H = normalize(L + V);

                float ndh = saturate(dot(N, H));
                float spec = pow(ndh, _SpecPower);
                spec = smoothstep(
                    _SpecThreshold - _SpecSoftness,
                    _SpecThreshold + _SpecSoftness,
                    spec
                );

                // N 是法线
                // L 是光方向
                // V 是视线方向
                // H 是半角向量，表示光和视线的中间方向

                // dot(N, L) 决定明暗
                // dot(N, H) 决定高光

                // 而三渲二的关键是：
                // 把这些连续值再“硬边化

                float3 specular = spec * _SpecColor.rgb;

                float3 finalColor = diffuse + specular;

                return half4(finalColor, 1.0);
            }
            ENDHLSL
        }
    }
}