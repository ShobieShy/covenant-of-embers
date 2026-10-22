#version 450
// Lambert + ambient with one fixed directional light (moves to per-frame data in step 12).
// Double-sided materials are drawn without culling; their back faces use the flipped normal.
layout(location = 0) in vec3 vNormal;
layout(location = 1) in vec4 vColor;
layout(location = 0) out vec4 oColor;
const vec3 kToLight = vec3(0.5934, 0.5934, 0.5439);   // normalize(0.6, 0.6, 0.55): upper right, behind the viewer
const float kAmbient = 0.2;
void main() {
    vec3 n = normalize(gl_FrontFacing ? vNormal : -vNormal);
    float d = max(dot(n, kToLight), 0.0);
    oColor = vec4(vColor.rgb * (kAmbient + (1.0 - kAmbient) * d), 1.0);
}
