// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "engine/render/camera.hpp"
#include "engine/render/mesh.hpp"

#include <vulkan/vulkan.h>
#include <glm/glm.hpp>
#include <cstdint>
#include <string>
#include <vector>

struct SDL_Window;
typedef struct VmaAllocator_T* VmaAllocator;   // VMA's VK_DEFINE_HANDLE; header stays private

namespace coe {

struct RendererConfig {
    SDL_Window* window = nullptr;   // nullptr = headless (offscreen target)
    bool wantValidation = true;     // enabled only if the layer is installed
    uint32_t headlessWidth = 256, headlessHeight = 256;
};

struct ValidationStats { uint32_t warnings = 0, errors = 0; };

// One mesh instance to draw this frame.
struct DrawItem {
    MeshId mesh = kInvalidMesh;     // from VkRenderer::uploadMesh
    glm::mat4 model{1.0f};          // world transform: translate * rotate * scale (non-uniform allowed)
    glm::vec4 tint{1.0f};           // multiplies the vertex colour (one shared cube, many boxes)
};

// Per-frame lighting (step 12). Defaults reproduce the step-11 look: ambient 0.2,
// white light 0.8 from normalize(0.6, 0.6, 0.55), no fog.
struct FrameLighting {
    glm::vec3 toLight{0.5934f, 0.5934f, 0.5439f};   // unit vector toward the directional light
    glm::vec3 lightColor{0.8f};
    glm::vec3 ambient{0.2f};
    glm::vec3 fogColor{0.0f};
    float fogDensity = 0.0f;                         // exp(-density * distance); 0 = off
};

// Per-frame inputs from the game (already interpolated by the caller). The renderer
// turns the camera into a view-projection for the target's aspect ratio and writes it
// with the lighting into this frame-in-flight's uniform buffer (set 0, binding 0);
// push constants carry only {model, tint} per draw (80 bytes).
struct FrameParams {
    Camera camera{};                // view (look is applied per render frame)
    FrameLighting lighting{};
    glm::vec3 clearColor{0.02f, 0.02f, 0.05f};
    std::vector<DrawItem> draws;    // drawn in order; one draw call per submesh
};

// Headless readback of one resolved frame (game-side checks, e.g. game/world/level_view).
struct HeadlessFrame {
    uint32_t width = 0, height = 0;
    uint32_t samples = 1;             // MSAA sample count rendered with (resolved to 1)
    glm::vec2 depthSamplePos{0.5f};   // where in a pixel the read depth was taken (MSAA: sample 0)
    std::vector<uint8_t> rgba;        // width*height*4, row-major from the top, UNORM (no sRGB)
    std::vector<float> depth;         // width*height, reverse-Z (0 = nothing drawn)
    glm::mat4 viewProj{1.0f};         // the matrix used, to unproject depth to world space
};

class VkRenderer {
public:
    bool init(const RendererConfig& cfg);
    void shutdown();
    bool drawFrame(const FrameParams& p);           // window mode
    // Headless: render once (MSAA when supported), resolve, and read back colour + depth
    // (depth resolve: sample 0). Checking the image is the caller's job.
    bool renderHeadless(const FrameParams& p, HeadlessFrame& out);
    // Copies a mesh into device-local vertex/index buffers (staging + one-shot submit,
    // waits for completion). Call after init(); returns kInvalidMesh on failure.
    MeshId uploadMesh(const assets::MeshData& mesh);
    void onResize() { resized_ = true; }
    bool validationEnabled() const { return validation_; }
    const ValidationStats& stats() const { return stats_; }
    std::string deviceName() const { return deviceName_; }
    uint32_t msaaSamples() const { return uint32_t(samples_); }

private:
    bool createInstance();
    bool pickDevice();
    bool createDevice();
    bool createSwapchain();
    void destroySwapchain();
    bool createPipeline(VkFormat colorFormat);
    bool createFrames();
    bool createAllocator();
    struct GpuImage { VkImage image = VK_NULL_HANDLE; VmaAllocation allocation = nullptr; VkImageView view = VK_NULL_HANDLE; };
    bool pickDepthFormat();
    bool createImage(VkExtent2D extent, VkFormat format, VkImageUsageFlags usage, VkImageAspectFlags aspect,
                     VkSampleCountFlagBits samples, GpuImage& out);
    // Wants 2x MSAA (Magewar's msaa_3d setting); falls back to 1 if the colour+depth
    // formats can't do it. Called once the colour format is known.
    void pickSampleCount(VkFormat colorFormat);
    bool createFrameUniforms();
    void writeFrameUniforms(uint32_t frame, const FrameParams& p, const glm::mat4& viewProj);
    void destroyImage(GpuImage& img);
    // hostAccess: 0 = device-local, else VMA_ALLOCATION_CREATE_HOST_ACCESS_* (mapped).
    bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, uint32_t hostAccess, GpuBuffer& out);
    void destroyBuffer(GpuBuffer& b);
    bool uploadMeshImpl(const assets::MeshData& mesh, GpuMesh& out);
    // Where recordScene renders. With MSAA, `msaaColor` is drawn into and resolved
    // (average) into `target`; otherwise `target` is drawn into directly. `depthResolve`
    // (headless MSAA only) receives sample 0 of depth for readback.
    struct SceneTarget {
        VkImage target = VK_NULL_HANDLE;
        VkImageView targetView = VK_NULL_HANDLE;
        VkImageLayout finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
        const GpuImage* msaaColor = nullptr;
        const GpuImage* depth = nullptr;
        const GpuImage* depthResolve = nullptr;
        bool readbackDepth = false;   // leave the readable depth image in TRANSFER_SRC_OPTIMAL
        VkExtent2D extent{};
    };
    void recordScene(VkCommandBuffer cmd, const SceneTarget& t, uint32_t frame, const FrameParams& p);

    static VKAPI_ATTR VkBool32 VKAPI_CALL debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT,
        VkDebugUtilsMessageTypeFlagsEXT, const VkDebugUtilsMessengerCallbackDataEXT*, void*);

    RendererConfig cfg_{};
    bool validation_ = false, debugUtils_ = false, resized_ = false;
    ValidationStats stats_{};
    std::string deviceName_;

    VkInstance instance_ = VK_NULL_HANDLE;
    VkDebugUtilsMessengerEXT messenger_ = VK_NULL_HANDLE;
    VkSurfaceKHR surface_ = VK_NULL_HANDLE;
    VkPhysicalDevice phys_ = VK_NULL_HANDLE;
    VkDevice device_ = VK_NULL_HANDLE;
    uint32_t queueFamily_ = 0;
    VkQueue queue_ = VK_NULL_HANDLE;
    VmaAllocator allocator_ = nullptr;
    std::vector<GpuMesh> meshes_;

    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkFormat swapFormat_ = VK_FORMAT_UNDEFINED;
    VkExtent2D swapExtent_{};
    std::vector<VkImage> swapImages_;
    std::vector<VkImageView> swapViews_;
    std::vector<VkSemaphore> renderDone_;     // one per swapchain image

    VkPipelineLayout pipelineLayout_ = VK_NULL_HANDLE;
    VkPipeline pipelines_[2]{};                // [0] cull back faces, [1] double-sided (glTF material.doubleSided)
    VkFormat pipelineFormat_ = VK_FORMAT_UNDEFINED;
    VkFormat depthFormat_ = VK_FORMAT_UNDEFINED;
    GpuImage depth_{};                         // window mode: one depth image, sized with the swapchain
    GpuImage msaaColor_{};                     // window mode with MSAA: transient colour, resolved to the swapchain
    VkSampleCountFlagBits samples_ = VK_SAMPLE_COUNT_1_BIT;
    glm::vec2 sample0Pos_{0.5f};               // standard location of sample 0 for samples_
    VkDescriptorSetLayout frameSetLayout_ = VK_NULL_HANDLE;
    VkDescriptorPool descPool_ = VK_NULL_HANDLE;

    static constexpr uint32_t kFramesInFlight = 2;
    VkCommandPool pool_ = VK_NULL_HANDLE;
    VkCommandBuffer cmds_[kFramesInFlight]{};
    VkSemaphore imageReady_[kFramesInFlight]{};
    VkFence inFlight_[kFramesInFlight]{};
    GpuBuffer frameUbo_[kFramesInFlight]{};    // host-mapped FrameUniforms, written after the frame's fence
    VkDescriptorSet frameSets_[kFramesInFlight]{};
    uint32_t frame_ = 0;
};

} // namespace coe
