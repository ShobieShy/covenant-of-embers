// SPDX-License-Identifier: Apache-2.0
#pragma once
#include "engine/render/camera.hpp"

#include <vulkan/vulkan.h>
#include <glm/glm.hpp>
#include <cstdint>
#include <string>
#include <vector>

struct SDL_Window;

namespace coe {

struct RendererConfig {
    SDL_Window* window = nullptr;   // nullptr = headless (offscreen target)
    bool wantValidation = true;     // enabled only if the layer is installed
    uint32_t headlessWidth = 256, headlessHeight = 256;
};

struct ValidationStats { uint32_t warnings = 0, errors = 0; };

// Per-frame inputs from the game (already interpolated by the caller). The renderer
// turns the camera into a view-projection for the target's aspect ratio and pushes
// {viewProj, model} as 128 bytes of push constants (the guaranteed minimum), which
// is all the per-frame data until step 11/12 adds descriptor-backed buffers.
struct FrameParams {
    Camera camera{};                // view (look is applied per render frame)
    glm::mat4 model{1.0f};          // cube transform (fixed-tick state lerped by alpha)
};

class VkRenderer {
public:
    bool init(const RendererConfig& cfg);
    void shutdown();
    bool drawFrame(const FrameParams& p);           // window mode
    bool renderHeadlessAndVerify(const FrameParams& p);  // headless: render once, read back colour + depth, check them
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
    struct GpuImage { VkImage image = VK_NULL_HANDLE; VkDeviceMemory memory = VK_NULL_HANDLE; VkImageView view = VK_NULL_HANDLE; };
    bool pickDepthFormat();
    bool createImage(VkExtent2D extent, VkFormat format, VkImageUsageFlags usage, VkImageAspectFlags aspect, GpuImage& out);
    void destroyImage(GpuImage& img);
    // Clears colour + depth, draws the cube, and leaves colour in finalLayout. With
    // readbackDepth the depth image ends in TRANSFER_SRC_OPTIMAL (headless check).
    void recordScene(VkCommandBuffer cmd, VkImage image, VkImageView view, const GpuImage& depth, VkExtent2D extent,
                     VkImageLayout finalLayout, bool readbackDepth, const FrameParams& p);
    uint32_t findMemoryType(uint32_t bits, VkMemoryPropertyFlags props) const;

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

    VkSwapchainKHR swapchain_ = VK_NULL_HANDLE;
    VkFormat swapFormat_ = VK_FORMAT_UNDEFINED;
    VkExtent2D swapExtent_{};
    std::vector<VkImage> swapImages_;
    std::vector<VkImageView> swapViews_;
    std::vector<VkSemaphore> renderDone_;     // one per swapchain image

    VkPipelineLayout pipelineLayout_ = VK_NULL_HANDLE;
    VkPipeline pipeline_ = VK_NULL_HANDLE;
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
