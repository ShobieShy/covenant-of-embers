#version 450
// Unit cube (half-extent 0.5) generated from gl_VertexIndex: 6 faces x 2 triangles,
// counter-clockwise seen from outside. No vertex buffer until step 11's meshes.
layout(push_constant) uniform Push {
    mat4 viewProj;   // per frame: Camera::viewProjection(aspect) (reverse-Z, Vulkan clip)
    mat4 model;      // per draw: interpolated object transform (rotation + translation)
} pc;
layout(location = 0) out vec3 vNormal;

const vec3 N[6] = vec3[](vec3(1, 0, 0), vec3(-1, 0, 0), vec3(0, 1, 0), vec3(0, -1, 0), vec3(0, 0, 1), vec3(0, 0, -1));
// cross(U, V) == N, so (U, V) walk counter-clockwise when viewed from outside.
const vec3 U[6] = vec3[](vec3(0, 1, 0), vec3(0, 0, 1), vec3(0, 0, 1), vec3(1, 0, 0), vec3(1, 0, 0), vec3(0, 1, 0));
const vec3 V[6] = vec3[](vec3(0, 0, 1), vec3(0, 1, 0), vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 1, 0), vec3(1, 0, 0));
const vec2 Q[6] = vec2[](vec2(-1, -1), vec2(1, -1), vec2(1, 1), vec2(-1, -1), vec2(1, 1), vec2(-1, 1));

void main() {
    int f = gl_VertexIndex / 6;
    vec2 q = Q[gl_VertexIndex % 6];
    vec3 p = 0.5 * (N[f] + q.x * U[f] + q.y * V[f]);
    gl_Position = pc.viewProj * pc.model * vec4(p, 1.0);
    vNormal = mat3(pc.model) * N[f];   // rigid transform: no inverse-transpose needed
}
