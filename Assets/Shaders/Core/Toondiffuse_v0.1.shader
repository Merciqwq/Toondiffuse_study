Shader "Custom/ToonDiffuseSpecRim_Commented"
{
    Properties
    {
        // ===== 漫反射（Toon） =====
        _BaseColor("Base Color", Color) = (1,1,1,1)        // 亮面颜色
        _ShadowColor("Shadow Color", Color) = (0.35,0.35,0.4,1) // 暗面颜色
        _ShadowThreshold("Shadow Threshold", Range(0,1)) = 0.5   // 明暗分界
        _ShadowSoftness("Shadow Softness", Range(0.001,0.3)) = 0.05 // 分界柔和度

        // ===== 高光（Specular） =====
        _SpecColor("Spec Color", Color) = (1,1,1,1)
        _SpecPower("Spec Power", Range(1,128)) = 32
        _SpecThreshold("Spec Threshold", Range(0,1)) = 0.5
        _SpecSoftness("Spec Softness", Range(0.001,0.3)) = 0.05

        // ===== 边缘光（Rim Light） =====
        _RimColor("Rim Color", Color) = (0.6,0.8,1,1)
        _RimPower("Rim Power", Range(0.1,8)) = 2
        _RimThreshold("Rim Threshold", Range(0,1)) = 0.5
        _RimSoftness("Rim Softness", Range(0.001,0.3)) = 0.05
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque"// 不透明物体
            "RenderPipeline"="UniversalPipeline"// 仅 URP 可用
        }

        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }// 仅 URP 可用

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            // ===== 引入 URP 基础功能 =====
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // ===== 顶点输入 =====
            struct Attributes
            {
                float4 positionOS : POSITION; // 顶点位置（物体空间）
                float3 normalOS   : NORMAL;   // 法线（物体空间）
            };

            // ===== 顶点输出 → 片元输入 =====
            struct Varyings
            {
                float4 positionCS : SV_POSITION; // 屏幕位置
                float3 normalWS   : TEXCOORD0;   // 世界空间法线
                float3 positionWS : TEXCOORD1;   // 世界空间位置
            };

            // ===== 材质参数 =====
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
            CBUFFER_END

            // ===== 顶点着色器 =====
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                // 模型 → 屏幕
                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);

                // 法线转世界空间
                OUT.normalWS = TransformObjectToWorldNormal(IN.normalOS);

                // 位置转世界空间（用于计算视角方向）
                OUT.positionWS = TransformObjectToWorld(IN.positionOS.xyz);

                return OUT;
            }

            // ===== 片元着色器 =====
            half4 frag(Varyings IN) : SV_Target
            {
                // ===== 法线归一化 =====
                float3 N = normalize(IN.normalWS);

                // ===== 获取主光 =====
                Light mainLight = GetMainLight();
                float3 L = normalize(-mainLight.direction); // 注意取反

                // ===== Toon Diffuse =====
                float ndl = saturate(dot(N, L)); // N·L

                float lightBand = smoothstep(
                    _ShadowThreshold - _ShadowSoftness,
                    _ShadowThreshold + _ShadowSoftness,
                    ndl
                );

                float3 diffuse = lerp(_ShadowColor.rgb, _BaseColor.rgb, lightBand);// 根据亮暗分界插值计算漫反射颜色

                // ===== 视线方向 =====
                float3 V = normalize(GetWorldSpaceViewDir(IN.positionWS));

                // ===== 半角向量（用于高光）=====
                float3 H = normalize(L + V);

                // ===== Specular =====
                float ndh = saturate(dot(N, H));
                float spec = pow(ndh, _SpecPower);

                spec = smoothstep(
                    _SpecThreshold - _SpecSoftness,
                    _SpecThreshold + _SpecSoftness,
                    spec
                );// 让高光也有一个柔和的边界

                float3 specular = spec * _SpecColor.rgb;

                // ===== Rim Light =====
                float rim = 1.0 - saturate(dot(N, V)); // 越靠边越大

                rim = pow(rim, _RimPower);// 控制边缘光的衰减速度

                rim = smoothstep(
                    _RimThreshold - _RimSoftness,
                    _RimThreshold + _RimSoftness,
                    rim
                );// 让边缘光也有一个柔和的边界

                float3 rimColor = rim * _RimColor.rgb; // 边缘光颜色

                // ===== 最终颜色 =====
                float3 finalColor = diffuse + specular + rimColor;

                return half4(finalColor, 1.0);
            }

            ENDHLSL
        }
    }
}