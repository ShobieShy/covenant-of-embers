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
    glm::mat4 model{1.0f};          // world transform (fixed-tick state lerped by alpha)
};

// Per-frame inputs from the game (already interpolated by the caller). The renderer
// turns the camera into a view-projection for the target's aspect ratio and pushes
// {viewProj, model} per draw as 128 bytes of push constants (the guaranteed minimum);
// descriptor-backed per-frame data arrives with textures/lights (steps 12+, 21).
struct FrameParams {
    Camera camera{};                // view (look is applied per render frame)
    std::vector<DrawItem> draws;    // drawn in order; one draw call per submesh
};

class VkRenderer {
public:
    bool init(const RendererConfig& cfg);
    void shutdown();
    bool drawFrame(const FrameParams& p);           // window mode
    // Headless: render once, read back colour + depth and check them (corner clear,
    // centre covered by geometry nearer than draws[0]'s origin, shading varies).
    bool renderHeadlessAndVerify(const FrameParams& p);
    // Copies a mesh into device-local vertex/index buffers (staging + one-shot submit,
    // waits for completion). Call after init(); returns kInvalidMesh on failure.
    MeshId uploadMesh(const assets::MeshData& mesh);
    void onResize() { resized_ = true; }
    bool validationEnabled() const { return validation_; }
    const ValidationStats& stats() const { return stats_; }
    std::string deviceName() const { return deviceName_; }

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
    bool createImage(VkExtent2D extent, VkFormat format, VkImageUsageFlags usage, VkImageAspectFlags aspect, GpuImage& out);
    void destroyImage(GpuImage& img);
    // hostAccess: 0 = device-local, else VMA_ALLOCATION_CREATE_HOST_ACCESS_* (mapped).
    bool createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, uint32_t hostAccess, GpuBuffer& out);
    void destroyBuffer(GpuBuffer& b);
    bool uploadMeshImpl(const assets::MeshData& mesh, GpuMesh& out);
    // Clears colour + depth, draws FrameParams::draws, and leaves colour in finalLayout. With
    // readbackDepth the depth image ends in TRANSFER_SRC_OPTIMAL (headless check).
    void recordScene(VkCommandBuffer cmd, VkImage image, VkImageView view, const GpuImage& depth, VkExtent2D extent,
                     VkImageLayout finalLayout, bool readbackDepth, const FrameParams& p);

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

    static constexpr uint32_t kFramesInFlight = 2;
    VkCommandPool pool_ = VK_NULL_HANDLE;
    VkCommandBuffer cmds_[kFramesInFlight]{};
    VkSemaphore imageReady_[kFramesInFlight]{};
    VkFence inFlight_[kFramesInFlight]{};
    uint32_t frame_ = 0;
};

} // namespace coe
