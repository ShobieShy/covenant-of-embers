// SPDX-License-Identifier: Apache-2.0
#pragma once
#include <vulkan/vulkan.h>
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

class VkRenderer {
public:
    bool init(const RendererConfig& cfg);
    void shutdown();
    bool drawFrame();                         // window mode
    bool renderHeadlessAndVerify();           // headless: render once, read back, check pixels
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
    void recordTriangle(VkCommandBuffer cmd, VkImage image, VkImageView view, VkExtent2D extent,
                        VkImageLayout finalLayout);
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

    static constexpr uint32_t kFramesInFlight = 2;
    VkCommandPool pool_ = VK_NULL_HANDLE;
    VkCommandBuffer cmds_[kFramesInFlight]{};
    VkSemaphore imageReady_[kFramesInFlight]{};
    VkFence inFlight_[kFramesInFlight]{};
    uint32_t frame_ = 0;
};

} // namespace coe
