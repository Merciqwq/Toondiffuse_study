Shader "Custom/ToonHair"
{
    Properties
    {
        // ===== 固有色与 Ramp =====
        _BaseColor("Base Color", Color) = (1,1,1,1)
        _RampTex("Ramp Texture", 2D) = "white" {}
        _RampUVY("Ramp UV Y", Range(0,1)) = 0.5
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05

        // ===== 头发主高光（条带感） =====
        _HairSpecColor("Hair Spec Color", Color) = (1,1,1,1)
        _HairSpecShift("Hair Spec Shift", Range(-1,1)) = 0.0
        _HairSpecExponent("Hair Spec Exponent", Range(1,128)) = 32
        _HairSpecThreshold("Hair Spec Threshold", Range(0,1)) = 0.4
        _HairSpecSoftness("Hair Spec Softness", Range(0.001,0.3)) = 0.05

        // ===== 二级高光（可选，用来增加层次） =====
        _HairSpec2Color("Hair Spec 2 Color", Color) = (0.7,0.8,1.0,1)
        _HairSpec2Shift("Hair Spec 2 Shift", Range(-1,1)) = 0.2
        _HairSpec2Exponent("Hair Spec 2 Exponent", Range(1,128)) = 64
        _HairSpec2Threshold("Hair Spec 2 Threshold", Range(0,1)) = 0.55
        _HairSpec2Softness("Hair Spec 2 Softness", Range(0.001,0.3)) = 0.05

        // ===== Mask（可选） =====
        _SpecMaskTex("Spec Mask (R)", 2D) = "white" {}

        // ===== Rim =====
                // 边缘光：增强轮廓感
                // 通过 N·V 判断是否接近轮廓
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
        // Pass 1: 头发主体
        // Ramp + 各向异性近似高光 + Rim
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

            TEXTURE2D(_RampTex);
            SAMPLER(sampler_RampTex);

            TEXTURE2D(_SpecMaskTex);
            SAMPLER(sampler_SpecMaskTex);

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT; // 头发高光关键：切线方向
                float2 uv         : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float3 normalWS   : TEXCOORD0;
                float3 tangentWS  : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float2 uv         : TEXCOORD3;
            };

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseColor;

                float4 _RampTex_ST;
                float _RampUVY;
                float _ShadowThreshold;
                float _ShadowSoftness;

                float4 _HairSpecColor;
                float _HairSpecShift;
                float _HairSpecExponent;
                float _HairSpecThreshold;
                float _HairSpecSoftness;

                float4 _HairSpec2Color;
                float _HairSpec2Shift;
                float _HairSpec2Exponent;
                float _HairSpec2Threshold;
                float _HairSpec2Softness;

                float4 _SpecMaskTex_ST;

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
                OUT.tangentWS = TransformObjectToWorldDir(IN.tangentOS.xyz);
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.uv = TRANSFORM_TEX(IN.uv, _SpecMaskTex);
                return OUT;
            }

            // 沿切线方向做一个简化版各向异性高光
            float ComputeHairSpec(
                float3 T,
                float3 N,
                float3 H,
                float shift,
                float exponent,
                float threshold,
                float softness)
            {
                // 把切线沿法线轻微偏移，模拟高光条带移动
                float3 shiftedT = normalize(T + shift * N);

                // 条带高光的核心：H 与切线越垂直，高光越强
                float tdh = dot(shiftedT, H);
                float spec = pow(saturate(1.0 - abs(tdh)), exponent);
                spec = smoothstep(threshold - softness, threshold + softness, spec);
                return spec;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float3 N = normalize(IN.normalWS);
                float3 T = normalize(IN.tangentWS);
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                Light mainLight = GetMainLight();
                float3 L = normalize(-mainLight.direction);
                float3 H = normalize(L + V);

                // ===== Ramp Diffuse =====
                // 用 Ramp 控制明暗，而不是简单 lerp
                // ndl = N·L，表示受光程度
                // rampInput 决定采样 Ramp 的位置（横向）
                float ndl = saturate(dot(N, L));
                float rampInput = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );
                float2 rampUV = float2(rampInput, _RampUVY);
                float3 rampColor = SAMPLE_TEXTURE2D(_RampTex, sampler_RampTex, rampUV).rgb;
                float3 diffuse = _BaseColor.rgb * rampColor;

                // ===== Spec Mask =====
                // 用贴图控制哪里允许出现高光
                // 白=有高光，黑=无高光（常用于控制发缝、内侧头发）
                float specMask = SAMPLE_TEXTURE2D(_SpecMaskTex, sampler_SpecMaskTex, IN.uv).r;

                // ===== Hair Spec 1 =====
                // 第一层主高光：较宽，负责主要视觉亮带
                // shift 控制高光在发丝上的偏移位置
                float hairSpec1 = ComputeHairSpec(
                    T, N, H,
                    _HairSpecShift,
                    _HairSpecExponent,
                    _HairSpecThreshold,
                    _HairSpecSoftness
                );
                float3 specular1 = hairSpec1 * _HairSpecColor.rgb * specMask;

                // ===== Hair Spec 2 =====
                // 第二层高光：更窄、更锐，增加层次感
                // 常用于模拟二次元头发的“双高光结构”
                float hairSpec2 = ComputeHairSpec(
                    T, N, H,
                    _HairSpec2Shift,
                    _HairSpec2Exponent,
                    _HairSpec2Threshold,
                    _HairSpec2Softness
                );
                float3 specular2 = hairSpec2 * _HairSpec2Color.rgb * specMask;

                // ===== Rim =====
                float rim = 1.0 - saturate(dot(N, V));
                rim = pow(rim, _RimPower);
                rim = smoothstep(
                    _RimThreshold - _RimSoftness,
                    _RimThreshold + _RimSoftness,
                    rim
                );
                float3 rimColor = rim * _RimColor.rgb;

                float3 finalColor = diffuse + specular1 + specular2 + rimColor;
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

                float4 _HairSpecColor;
                float _HairSpecShift;
                float _HairSpecExponent;
                float _HairSpecThreshold;
                float _HairSpecSoftness;

                float4 _HairSpec2Color;
                float _HairSpec2Shift;
                float _HairSpec2Exponent;
                float _HairSpec2Threshold;
                float _HairSpec2Softness;

                float4 _SpecMaskTex_ST;

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

