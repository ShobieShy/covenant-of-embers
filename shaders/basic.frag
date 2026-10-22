#version 450
// Lambert + ambient with one fixed directional light (moves to per-frame data in step 12).
layout(location = 0) in vec3 vNormal;
layout(location = 0) out vec4 oColor;
const vec3 kToLight = vec3(0.5934, 0.5934, 0.5439);   // normalize(0.6, 0.6, 0.55): upper right, behind the viewer
const vec3 kAlbedo = vec3(1.0, 0.5, 0.15);              // ember orange
const float kAmbient = 0.2;
void main() {
    float d = max(dot(normalize(vNormal), kToLight), 0.0);
    oColor = vec4(kAlbedo * (kAmbient + (1.0 - kAmbient) * d), 1.0);
}
