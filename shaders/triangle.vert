#version 450
layout(location = 0) out vec3 vColor;
// Rotation in radians from the game's interpolated state (FrameParams::spin).
layout(push_constant) uniform Push { float spin; } pc;
const vec2 P[3] = vec2[](vec2(0.0, -0.6), vec2(0.6, 0.6), vec2(-0.6, 0.6));
const vec3 C[3] = vec3[](vec3(1.0, 0.55, 0.1), vec3(0.95, 0.2, 0.05), vec3(1.0, 0.85, 0.35));
void main() {
    float c = cos(pc.spin), s = sin(pc.spin);
    vec2 p = P[gl_VertexIndex];
    gl_Position = vec4(c * p.x - s * p.y, s * p.x + c * p.y, 0.0, 1.0);
    vColor = C[gl_VertexIndex];
}
