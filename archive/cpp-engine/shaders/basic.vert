#version 450
#extension GL_GOOGLE_include_directive : require
// Mesh vertex shader: interleaved engine/assets Vertex from a vertex buffer (layout in
// engine/render/mesh.cpp). Per-frame data comes from the Frame UBO; push constants
// carry only per-draw data (step 12).
#include "frame.glsl"
layout(push_constant) uniform Push {
    mat4 model;      // per draw: translate * rotate * (possibly non-uniform) scale
    vec4 tint;       // per draw: multiplies the vertex colour (level boxes share one white cube)
} pc;
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec4 inColor;   // material baseColorFactor
layout(location = 3) in vec2 inUv;      // base-colour texture UV (KHR_texture_transform baked in)
layout(location = 0) out vec3 vNormal;
layout(location = 1) out vec4 vColor;
layout(location = 2) out vec3 vWorldPos;
layout(location = 3) out vec2 vUv;

void main() {
    vec4 world = pc.model * vec4(inPosition, 1.0);
    gl_Position = frame.viewProj * world;
    // Inverse-transpose keeps normals perpendicular under non-uniform scale (greybox
    // boxes are scaled unit cubes). Per vertex for now; move to the CPU per draw if
    // vertex cost ever matters. The fragment shader renormalises.
    vNormal = transpose(inverse(mat3(pc.model))) * inNormal;
    vColor = inColor * pc.tint;
    vWorldPos = world.xyz;
    vUv = inUv;
}
