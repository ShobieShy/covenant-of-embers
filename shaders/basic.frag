#version 450
#extension GL_GOOGLE_include_directive : require
// Lambert + ambient with one directional light and optional exponential distance fog,
// all from the per-frame UBO (step 12). Double-sided materials are drawn without
// culling; their back faces use the flipped normal. Step 21: the base colour is the
// material texture (set 1, sRGB image so the sample is linear; untextured materials
// get a 1x1 white texture) times the vertex colour (baseColorFactor * tint).
#include "frame.glsl"
layout(location = 0) in vec3 vNormal;
layout(location = 1) in vec4 vColor;
layout(location = 2) in vec3 vWorldPos;
layout(location = 3) in vec2 vUv;
layout(set = 1, binding = 0) uniform sampler2D baseColorTex;
layout(location = 0) out vec4 oColor;
void main() {
    vec3 n = normalize(gl_FrontFacing ? vNormal : -vNormal);
    float d = max(dot(n, frame.toLight.xyz), 0.0);
    vec3 base = texture(baseColorTex, vUv).rgb * vColor.rgb;
    vec3 lit = base * (frame.ambient.rgb + frame.lightColor.rgb * d);
    float f = exp(-frame.fog.a * distance(vWorldPos, frame.cameraPos.xyz));
    oColor = vec4(mix(frame.fog.rgb, lit, f), 1.0);
}
