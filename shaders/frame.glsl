// Per-frame uniforms (BUILD_PLAN step 12), set 0 binding 0, one buffer per frame in
// flight. std140; mirrored by FrameUniforms in engine/render/vk_renderer.cpp.
layout(set = 0, binding = 0, std140) uniform Frame {
    mat4 viewProj;      // Camera::viewProjection(aspect): reverse-Z, Vulkan clip
    vec4 cameraPos;     // xyz world eye position
    vec4 toLight;       // xyz unit vector toward the directional light
    vec4 lightColor;    // rgb directional light colour
    vec4 ambient;       // rgb ambient colour
    vec4 fog;           // rgb fog colour, a = exponential density per metre (0 = off)
} frame;
