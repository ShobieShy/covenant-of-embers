#version 450
// Mesh vertex shader (BUILD_PLAN step 11): interleaved engine/assets Vertex from a
// vertex buffer (layout in engine/render/mesh.cpp), node transforms already baked in.
layout(push_constant) uniform Push {
    mat4 viewProj;   // per frame: Camera::viewProjection(aspect) (reverse-Z, Vulkan clip)
    mat4 model;      // per draw: interpolated object transform (rotation, uniform scale, translation)
} pc;
layout(location = 0) in vec3 inPosition;
layout(location = 1) in vec3 inNormal;
layout(location = 2) in vec4 inColor;   // material baseColorFactor (textures: step 21)
layout(location = 0) out vec3 vNormal;
layout(location = 1) out vec4 vColor;

void main() {
    gl_Position = pc.viewProj * pc.model * vec4(inPosition, 1.0);
    // Uniform scale only (DrawItem contract), so mat3(model) keeps normals' directions;
    // the fragment shader renormalises.
    vNormal = mat3(pc.model) * inNormal;
    vColor = inColor;
}
