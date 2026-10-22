// SPDX-License-Identifier: Apache-2.0
// M1 renderer: Vulkan 1.3 instance/device/swapchain, dynamic rendering + synchronization2,
// a reverse-Z depth buffer, VMA-backed images/buffers, and indexed meshes (uploadMesh)
// drawn with {viewProj, model} push constants per FrameParams::draws entry.
// Validation layer is used only when installed.
#include "engine/render/vk_renderer.hpp"

#include <SDL3/SDL_vulkan.h>
#include <vk_mem_alloc.h>
#include <algorithm>
#include <cmath>
#include <cstdio>
#include <cstring>
#include <fstream>

#ifndef COE_SHADER_DIR
#define COE_SHADER_DIR "shaders"
#endif

namespace coe {
namespace {
constexpr const char* kValidationLayer = "VK_LAYER_KHRONOS_validation";
constexpr VkClearColorValue kClear{{0.02f, 0.02f, 0.05f, 1.0f}};
constexpr float kClearDepth = 0.0f;              // reverse-Z: 0 is infinitely far, test GREATER

struct PushConstants {
    glm::mat4 viewProj;
    glm::mat4 model;
};
static_assert(sizeof(PushConstants) == 128, "push constants must fit the guaranteed 128 bytes");

#define VK_CHECK(x) do { VkResult r_ = (x); if (r_ != VK_SUCCESS) { \
    std::fprintf(stderr, "[vk] %s failed: %d (%s:%d)\n", #x, r_, __FILE__, __LINE__); return false; } } while (0)

std::vector<uint32_t> readSpirv(const std::string& path) {
    std::ifstream f(path, std::ios::binary | std::ios::ate);
    if (!f) return {};
    auto size = static_cast<size_t>(f.tellg());
    std::vector<uint32_t> words(size / 4);
    f.seekg(0);
    f.read(reinterpret_cast<char*>(words.data()), static_cast<std::streamsize>(size));
    return words;
}

void imageBarrier(VkCommandBuffer cmd, VkImage img, VkImageLayout from, VkImageLayout to,
                  VkPipelineStageFlags2 srcStage, VkAccessFlags2 srcAccess,
                  VkPipelineStageFlags2 dstStage, VkAccessFlags2 dstAccess,
                  VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT) {
    VkImageMemoryBarrier2 b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    b.srcStageMask = srcStage; b.srcAccessMask = srcAccess;
    b.dstStageMask = dstStage; b.dstAccessMask = dstAccess;
    b.oldLayout = from; b.newLayout = to;
    b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = img;
    b.subresourceRange = {aspect, 0, 1, 0, 1};
    VkDependencyInfo dep{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
    dep.imageMemoryBarrierCount = 1; dep.pImageMemoryBarriers = &b;
    vkCmdPipelineBarrier2(cmd, &dep);
}
} // namespace

VKAPI_ATTR VkBool32 VKAPI_CALL VkRenderer::debugCallback(VkDebugUtilsMessageSeverityFlagBitsEXT sev,
        VkDebugUtilsMessageTypeFlagsEXT, const VkDebugUtilsMessengerCallbackDataEXT* data, void* user) {
    auto* self = static_cast<VkRenderer*>(user);
    if (sev & VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT) self->stats_.errors++;
    else if (sev & VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT) self->stats_.warnings++;
    std::fprintf(stderr, "[vk-validation] %s\n", data->pMessage);
    return VK_FALSE;
}

bool VkRenderer::init(const RendererConfig& cfg) {
    cfg_ = cfg;
    if (!createInstance() || !pickDevice() || !pickDepthFormat() || !createDevice() || !createAllocator()) return false;
    if (cfg_.window) {
        if (!createSwapchain()) return false;
        if (!createPipeline(swapFormat_)) return false;
    } else if (!createPipeline(VK_FORMAT_R8G8B8A8_UNORM)) return false;
    return createFrames();
}

bool VkRenderer::createInstance() {
    uint32_t loaderVersion = 0;
    vkEnumerateInstanceVersion(&loaderVersion);
    if (loaderVersion < VK_API_VERSION_1_3) {
        std::fprintf(stderr, "[vk] Vulkan 1.3 loader required\n");
        return false;
    }

    std::vector<const char*> exts;
    if (cfg_.window) {
        Uint32 n = 0;
        const char* const* sdlExts = SDL_Vulkan_GetInstanceExtensions(&n);
        if (!sdlExts) { std::fprintf(stderr, "[sdl] %s\n", SDL_GetError()); return false; }
        exts.assign(sdlExts, sdlExts + n);
    }

    uint32_t layerCount = 0;
    vkEnumerateInstanceLayerProperties(&layerCount, nullptr);
    std::vector<VkLayerProperties> layers(layerCount);
    vkEnumerateInstanceLayerProperties(&layerCount, layers.data());
    bool layerPresent = std::any_of(layers.begin(), layers.end(),
        [](const VkLayerProperties& l) { return std::strcmp(l.layerName, kValidationLayer) == 0; });
    validation_ = cfg_.wantValidation && layerPresent;
    if (cfg_.wantValidation && !layerPresent)
        std::fprintf(stderr, "[vk] %s not installed - running without validation "
                             "(install vulkan-validation-layers to enable)\n", kValidationLayer);

    uint32_t extCount = 0;
    vkEnumerateInstanceExtensionProperties(nullptr, &extCount, nullptr);
    std::vector<VkExtensionProperties> avail(extCount);
    vkEnumerateInstanceExtensionProperties(nullptr, &extCount, avail.data());
    debugUtils_ = validation_ && std::any_of(avail.begin(), avail.end(), [](const VkExtensionProperties& e) {
        return std::strcmp(e.extensionName, VK_EXT_DEBUG_UTILS_EXTENSION_NAME) == 0; });
    if (debugUtils_) exts.push_back(VK_EXT_DEBUG_UTILS_EXTENSION_NAME);

    VkApplicationInfo app{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    app.pApplicationName = "Covenant of Embers";
    app.applicationVersion = VK_MAKE_VERSION(0, 0, 2);
    app.pEngineName = "Ember";
    app.apiVersion = VK_API_VERSION_1_3;

    VkDebugUtilsMessengerCreateInfoEXT dbg{VK_STRUCTURE_TYPE_DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT};
    dbg.messageSeverity = VK_DEBUG_UTILS_MESSAGE_SEVERITY_WARNING_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_SEVERITY_ERROR_BIT_EXT;
    dbg.messageType = VK_DEBUG_UTILS_MESSAGE_TYPE_GENERAL_BIT_EXT | VK_DEBUG_UTILS_MESSAGE_TYPE_VALIDATION_BIT_EXT |
                      VK_DEBUG_UTILS_MESSAGE_TYPE_PERFORMANCE_BIT_EXT;
    dbg.pfnUserCallback = &VkRenderer::debugCallback;
    dbg.pUserData = this;

    VkInstanceCreateInfo ci{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ci.pApplicationInfo = &app;
    ci.enabledExtensionCount = static_cast<uint32_t>(exts.size());
    ci.ppEnabledExtensionNames = exts.data();
    if (validation_) { ci.enabledLayerCount = 1; ci.ppEnabledLayerNames = &kValidationLayer; }
    if (debugUtils_) ci.pNext = &dbg;
    VK_CHECK(vkCreateInstance(&ci, nullptr, &instance_));

    if (debugUtils_) {
        auto create = reinterpret_cast<PFN_vkCreateDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(instance_, "vkCreateDebugUtilsMessengerEXT"));
        if (create) create(instance_, &dbg, nullptr, &messenger_);
    }
    if (cfg_.window && !SDL_Vulkan_CreateSurface(cfg_.window, instance_, nullptr, &surface_)) {
        std::fprintf(stderr, "[sdl] surface: %s\n", SDL_GetError());
        return false;
    }
    return true;
}

bool VkRenderer::pickDevice() {
    uint32_t n = 0;
    vkEnumeratePhysicalDevices(instance_, &n, nullptr);
    std::vector<VkPhysicalDevice> devs(n);
    vkEnumeratePhysicalDevices(instance_, &n, devs.data());
    int best = -1;
    for (auto d : devs) {
        VkPhysicalDeviceProperties p; vkGetPhysicalDeviceProperties(d, &p);
        if (p.apiVersion < VK_API_VERSION_1_3) continue;
        if (surface_) {
            uint32_t ec = 0; vkEnumerateDeviceExtensionProperties(d, nullptr, &ec, nullptr);
            std::vector<VkExtensionProperties> e(ec); vkEnumerateDeviceExtensionProperties(d, nullptr, &ec, e.data());
            if (std::none_of(e.begin(), e.end(), [](auto& x) { return std::strcmp(x.extensionName, VK_KHR_SWAPCHAIN_EXTENSION_NAME) == 0; }))
                continue;
        }
        uint32_t qc = 0; vkGetPhysicalDeviceQueueFamilyProperties(d, &qc, nullptr);
        std::vector<VkQueueFamilyProperties> q(qc); vkGetPhysicalDeviceQueueFamilyProperties(d, &qc, q.data());
        for (uint32_t i = 0; i < qc; ++i) {
            if (!(q[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) continue;
            VkBool32 present = VK_TRUE;
            if (surface_) vkGetPhysicalDeviceSurfaceSupportKHR(d, i, surface_, &present);
            if (!present) continue;
            int score = p.deviceType == VK_PHYSICAL_DEVICE_TYPE_DISCRETE_GPU ? 3
                      : p.deviceType == VK_PHYSICAL_DEVICE_TYPE_INTEGRATED_GPU ? 2 : 1;
            if (score > best) { best = score; phys_ = d; queueFamily_ = i; deviceName_ = p.deviceName; }
            break;
        }
    }
    if (!phys_) { std::fprintf(stderr, "[vk] no Vulkan 1.3 GPU with graphics%s\n", surface_ ? "+present" : ""); return false; }
    return true;
}

bool VkRenderer::pickDepthFormat() {
    // D32_SFLOAT is what reverse-Z wants; the stencil variant is the portable fallback.
    // Headless additionally reads depth back, so it needs TRANSFER_SRC on the format.
    VkFormatFeatureFlags need = VK_FORMAT_FEATURE_DEPTH_STENCIL_ATTACHMENT_BIT;
    if (!cfg_.window) need |= VK_FORMAT_FEATURE_TRANSFER_SRC_BIT;
    for (VkFormat f : {VK_FORMAT_D32_SFLOAT, VK_FORMAT_D32_SFLOAT_S8_UINT}) {
        VkFormatProperties fp; vkGetPhysicalDeviceFormatProperties(phys_, f, &fp);
        if ((fp.optimalTilingFeatures & need) == need) { depthFormat_ = f; return true; }
    }
    std::fprintf(stderr, "[vk] no 32-bit float depth format\n");
    return false;
}

bool VkRenderer::createImage(VkExtent2D extent, VkFormat format, VkImageUsageFlags usage,
                             VkImageAspectFlags aspect, GpuImage& out) {
    VkImageCreateInfo ic{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ic.imageType = VK_IMAGE_TYPE_2D; ic.format = format; ic.extent = {extent.width, extent.height, 1};
    ic.mipLevels = 1; ic.arrayLayers = 1; ic.samples = VK_SAMPLE_COUNT_1_BIT; ic.tiling = VK_IMAGE_TILING_OPTIMAL;
    ic.usage = usage;
    // Render targets get their own allocation (drivers like dedicated memory for attachments).
    VmaAllocationCreateInfo ac{};
    ac.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    ac.flags = VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
    VK_CHECK(vmaCreateImage(allocator_, &ic, &ac, &out.image, &out.allocation, nullptr));
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image = out.image; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = format;
    vi.subresourceRange = {aspect, 0, 1, 0, 1};
    VK_CHECK(vkCreateImageView(device_, &vi, nullptr, &out.view));
    return true;
}

void VkRenderer::destroyImage(GpuImage& img) {
    if (img.view) vkDestroyImageView(device_, img.view, nullptr);
    if (img.image) vmaDestroyImage(allocator_, img.image, img.allocation);
    img = {};
}

bool VkRenderer::createAllocator() {
    VmaAllocatorCreateInfo ci{};
    ci.vulkanApiVersion = VK_API_VERSION_1_3;
    ci.physicalDevice = phys_; ci.device = device_; ci.instance = instance_;
    VK_CHECK(vmaCreateAllocator(&ci, &allocator_));
    return true;
}

bool VkRenderer::createBuffer(VkDeviceSize size, VkBufferUsageFlags usage, uint32_t hostAccess, GpuBuffer& out) {
    VkBufferCreateInfo bci{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};
    bci.size = size; bci.usage = usage; bci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
    VmaAllocationCreateInfo ac{};
    ac.usage = VMA_MEMORY_USAGE_AUTO;
    if (hostAccess) ac.flags = hostAccess | VMA_ALLOCATION_CREATE_MAPPED_BIT;
    VmaAllocationInfo info{};
    VK_CHECK(vmaCreateBuffer(allocator_, &bci, &ac, &out.buffer, &out.allocation, &info));
    out.size = size;
    out.mapped = hostAccess ? info.pMappedData : nullptr;
    if (hostAccess && !out.mapped) { std::fprintf(stderr, "[vk] buffer not host-mapped\n"); return false; }
    return true;
}

void VkRenderer::destroyBuffer(GpuBuffer& b) {
    if (b.buffer) vmaDestroyBuffer(allocator_, b.buffer, b.allocation);
    b = {};
}

MeshId VkRenderer::uploadMesh(const assets::MeshData& mesh) {
    GpuMesh g;
    if (!device_ || !uploadMeshImpl(mesh, g)) {
        destroyBuffer(g.vertices); destroyBuffer(g.indices);
        std::fprintf(stderr, "[vk] mesh upload failed\n");
        return kInvalidMesh;
    }
    meshes_.push_back(std::move(g));
    return static_cast<MeshId>(meshes_.size() - 1);
}

bool VkRenderer::uploadMeshImpl(const assets::MeshData& mesh, GpuMesh& out) {
    if (mesh.vertices.empty() || mesh.indices.empty() || mesh.submeshes.empty()) return false;
    for (const auto& sm : mesh.submeshes)
        if (uint64_t(sm.firstIndex) + sm.indexCount > mesh.indices.size()) return false;
    for (uint32_t i : mesh.indices)
        if (i >= mesh.vertices.size()) return false;           // never hand the GPU an out-of-range index
    const VkDeviceSize vbytes = mesh.vertices.size() * sizeof(assets::Vertex);
    const VkDeviceSize ibytes = mesh.indices.size() * sizeof(uint32_t);
    if (!createBuffer(vbytes, VK_BUFFER_USAGE_VERTEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 0, out.vertices) ||
        !createBuffer(ibytes, VK_BUFFER_USAGE_INDEX_BUFFER_BIT | VK_BUFFER_USAGE_TRANSFER_DST_BIT, 0, out.indices))
        return false;
    out.submeshes = mesh.submeshes;
    out.vertexCount = static_cast<uint32_t>(mesh.vertices.size());
    out.indexCount = static_cast<uint32_t>(mesh.indices.size());

    GpuBuffer staging;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    auto cleanup = [&] {
        if (fence) vkDestroyFence(device_, fence, nullptr);
        if (cmd) vkFreeCommandBuffers(device_, pool_, 1, &cmd);
        destroyBuffer(staging);
    };
    auto run = [&]() -> bool {
        if (!createBuffer(vbytes + ibytes, VK_BUFFER_USAGE_TRANSFER_SRC_BIT,
                          VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT, staging)) return false;
        std::memcpy(staging.mapped, mesh.vertices.data(), vbytes);
        std::memcpy(static_cast<char*>(staging.mapped) + vbytes, mesh.indices.data(), ibytes);
        VK_CHECK(vmaFlushAllocation(allocator_, staging.allocation, 0, VK_WHOLE_SIZE));

        VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        ai.commandPool = pool_; ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount = 1;
        VK_CHECK(vkAllocateCommandBuffers(device_, &ai, &cmd));
        VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
        VkBufferCopy vc{0, 0, vbytes}, ic{vbytes, 0, ibytes};
        vkCmdCopyBuffer(cmd, staging.buffer, out.vertices.buffer, 1, &vc);
        vkCmdCopyBuffer(cmd, staging.buffer, out.indices.buffer, 1, &ic);
        // Make the copies visible to vertex/index fetch of later submissions.
        VkMemoryBarrier2 mb{VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
        mb.srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT; mb.srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT;
        mb.dstStageMask = VK_PIPELINE_STAGE_2_VERTEX_INPUT_BIT;
        mb.dstAccessMask = VK_ACCESS_2_VERTEX_ATTRIBUTE_READ_BIT | VK_ACCESS_2_INDEX_READ_BIT;
        VkDependencyInfo dep{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
        dep.memoryBarrierCount = 1; dep.pMemoryBarriers = &mb;
        vkCmdPipelineBarrier2(cmd, &dep);
        VK_CHECK(vkEndCommandBuffer(cmd));

        VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO};
        VK_CHECK(vkCreateFence(device_, &fi, nullptr, &fence));
        VkCommandBufferSubmitInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO}; cbi.commandBuffer = cmd;
        VkSubmitInfo2 si{VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
        si.commandBufferInfoCount = 1; si.pCommandBufferInfos = &cbi;
        VK_CHECK(vkQueueSubmit2(queue_, 1, &si, fence));
        VK_CHECK(vkWaitForFences(device_, 1, &fence, VK_TRUE, UINT64_MAX));
        return true;
    };
    const bool ok = run();
    cleanup();
    return ok;
}

bool VkRenderer::createDevice() {
    float prio = 1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = queueFamily_; qci.queueCount = 1; qci.pQueuePriorities = &prio;

    VkPhysicalDeviceVulkan13Features f13{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_VULKAN_1_3_FEATURES};
    f13.dynamicRendering = VK_TRUE; f13.synchronization2 = VK_TRUE;

    const char* swapExt = VK_KHR_SWAPCHAIN_EXTENSION_NAME;
    VkDeviceCreateInfo ci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    ci.pNext = &f13;
    ci.queueCreateInfoCount = 1; ci.pQueueCreateInfos = &qci;
    if (surface_) { ci.enabledExtensionCount = 1; ci.ppEnabledExtensionNames = &swapExt; }
    VK_CHECK(vkCreateDevice(phys_, &ci, nullptr, &device_));
    vkGetDeviceQueue(device_, queueFamily_, 0, &queue_);
    return true;
}

bool VkRenderer::createSwapchain() {
    VkSurfaceCapabilitiesKHR caps;
    VK_CHECK(vkGetPhysicalDeviceSurfaceCapabilitiesKHR(phys_, surface_, &caps));
    uint32_t fc = 0; vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fc, nullptr);
    std::vector<VkSurfaceFormatKHR> formats(fc); vkGetPhysicalDeviceSurfaceFormatsKHR(phys_, surface_, &fc, formats.data());
    VkSurfaceFormatKHR fmt = formats[0];
    for (auto& f : formats)
        if ((f.format == VK_FORMAT_B8G8R8A8_SRGB || f.format == VK_FORMAT_R8G8B8A8_SRGB) &&
            f.colorSpace == VK_COLOR_SPACE_SRGB_NONLINEAR_KHR) { fmt = f; break; }

    VkExtent2D ext = caps.currentExtent;
    if (ext.width == UINT32_MAX) {
        int w = 0, h = 0; SDL_GetWindowSizeInPixels(cfg_.window, &w, &h);
        ext.width = std::clamp<uint32_t>(static_cast<uint32_t>(w), caps.minImageExtent.width, caps.maxImageExtent.width);
        ext.height = std::clamp<uint32_t>(static_cast<uint32_t>(h), caps.minImageExtent.height, caps.maxImageExtent.height);
    }
    if (ext.width == 0 || ext.height == 0) return true;   // minimised; retry later

    uint32_t count = caps.minImageCount + 1;
    if (caps.maxImageCount && count > caps.maxImageCount) count = caps.maxImageCount;

    VkSwapchainCreateInfoKHR ci{VK_STRUCTURE_TYPE_SWAPCHAIN_CREATE_INFO_KHR};
    ci.surface = surface_; ci.minImageCount = count;
    ci.imageFormat = fmt.format; ci.imageColorSpace = fmt.colorSpace; ci.imageExtent = ext;
    ci.imageArrayLayers = 1; ci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;
    ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ci.preTransform = caps.currentTransform;
    ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    ci.presentMode = VK_PRESENT_MODE_FIFO_KHR;      // always available, vsync
    ci.clipped = VK_TRUE;
    VK_CHECK(vkCreateSwapchainKHR(device_, &ci, nullptr, &swapchain_));
    swapFormat_ = fmt.format; swapExtent_ = ext;

    uint32_t ic = 0; vkGetSwapchainImagesKHR(device_, swapchain_, &ic, nullptr);
    swapImages_.resize(ic); vkGetSwapchainImagesKHR(device_, swapchain_, &ic, swapImages_.data());
    swapViews_.resize(ic); renderDone_.resize(ic);
    for (uint32_t i = 0; i < ic; ++i) {
        VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
        vi.image = swapImages_[i]; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = swapFormat_;
        vi.subresourceRange = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
        VK_CHECK(vkCreateImageView(device_, &vi, nullptr, &swapViews_[i]));
        VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VK_CHECK(vkCreateSemaphore(device_, &si, nullptr, &renderDone_[i]));
    }
    // Depth is only written and tested within a frame, so one image is shared by
    // both frames in flight; recordScene's barrier orders frame N+1's clear after
    // frame N's depth writes.
    return createImage(swapExtent_, depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                       VK_IMAGE_ASPECT_DEPTH_BIT, depth_);
}

void VkRenderer::destroySwapchain() {
    for (auto s : renderDone_) vkDestroySemaphore(device_, s, nullptr);
    for (auto v : swapViews_) vkDestroyImageView(device_, v, nullptr);
    renderDone_.clear(); swapViews_.clear(); swapImages_.clear();
    destroyImage(depth_);
    if (swapchain_) vkDestroySwapchainKHR(device_, swapchain_, nullptr);
    swapchain_ = VK_NULL_HANDLE;
}

bool VkRenderer::createPipeline(VkFormat colorFormat) {
    auto vs = readSpirv(std::string(COE_SHADER_DIR) + "/basic.vert.spv");
    auto fs = readSpirv(std::string(COE_SHADER_DIR) + "/basic.frag.spv");
    if (vs.empty() || fs.empty()) { std::fprintf(stderr, "[vk] missing SPIR-V in %s\n", COE_SHADER_DIR); return false; }
    VkShaderModule mods[2];
    for (int i = 0; i < 2; ++i) {
        auto& code = i ? fs : vs;
        VkShaderModuleCreateInfo mi{VK_STRUCTURE_TYPE_SHADER_MODULE_CREATE_INFO};
        mi.codeSize = code.size() * 4; mi.pCode = code.data();
        VK_CHECK(vkCreateShaderModule(device_, &mi, nullptr, &mods[i]));
    }
    VkPipelineShaderStageCreateInfo stages[2]{};
    for (int i = 0; i < 2; ++i) {
        stages[i].sType = VK_STRUCTURE_TYPE_PIPELINE_SHADER_STAGE_CREATE_INFO;
        stages[i].stage = i ? VK_SHADER_STAGE_FRAGMENT_BIT : VK_SHADER_STAGE_VERTEX_BIT;
        stages[i].module = mods[i]; stages[i].pName = "main";
    }
    VkPushConstantRange pcr{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(PushConstants)};
    VkPipelineLayoutCreateInfo li{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    li.pushConstantRangeCount = 1; li.pPushConstantRanges = &pcr;
    VK_CHECK(vkCreatePipelineLayout(device_, &li, nullptr, &pipelineLayout_));

    const VertexLayout layout = vertexLayout();
    VkPipelineVertexInputStateCreateInfo vin{VK_STRUCTURE_TYPE_PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO};
    vin.vertexBindingDescriptionCount = 1; vin.pVertexBindingDescriptions = &layout.binding;
    vin.vertexAttributeDescriptionCount = static_cast<uint32_t>(layout.attributes.size());
    vin.pVertexAttributeDescriptions = layout.attributes.data();
    VkPipelineInputAssemblyStateCreateInfo ia{VK_STRUCTURE_TYPE_PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO};
    ia.topology = VK_PRIMITIVE_TOPOLOGY_TRIANGLE_LIST;
    VkPipelineViewportStateCreateInfo vp{VK_STRUCTURE_TYPE_PIPELINE_VIEWPORT_STATE_CREATE_INFO};
    vp.viewportCount = 1; vp.scissorCount = 1;
    VkPipelineRasterizationStateCreateInfo rs{VK_STRUCTURE_TYPE_PIPELINE_RASTERIZATION_STATE_CREATE_INFO};
    rs.polygonMode = VK_POLYGON_MODE_FILL; rs.lineWidth = 1.0f;
    // Geometry is counter-clockwise seen from outside (glTF convention; the loader fixes
    // mirrored nodes); the projection's Y flip keeps that counter-clockwise on screen, so
    // Vulkan's default convention applies. pipelines_[1] (doubleSided) disables culling.
    rs.cullMode = VK_CULL_MODE_BACK_BIT; rs.frontFace = VK_FRONT_FACE_COUNTER_CLOCKWISE;
    VkPipelineMultisampleStateCreateInfo ms{VK_STRUCTURE_TYPE_PIPELINE_MULTISAMPLE_STATE_CREATE_INFO};
    ms.rasterizationSamples = VK_SAMPLE_COUNT_1_BIT;
    VkPipelineDepthStencilStateCreateInfo dss{VK_STRUCTURE_TYPE_PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO};
    dss.depthTestEnable = VK_TRUE; dss.depthWriteEnable = VK_TRUE;
    dss.depthCompareOp = VK_COMPARE_OP_GREATER;     // reverse-Z
    VkPipelineColorBlendAttachmentState att{};
    att.colorWriteMask = 0xF;
    VkPipelineColorBlendStateCreateInfo cb{VK_STRUCTURE_TYPE_PIPELINE_COLOR_BLEND_STATE_CREATE_INFO};
    cb.attachmentCount = 1; cb.pAttachments = &att;
    VkDynamicState dyn[] = {VK_DYNAMIC_STATE_VIEWPORT, VK_DYNAMIC_STATE_SCISSOR};
    VkPipelineDynamicStateCreateInfo ds{VK_STRUCTURE_TYPE_PIPELINE_DYNAMIC_STATE_CREATE_INFO};
    ds.dynamicStateCount = 2; ds.pDynamicStates = dyn;
    VkPipelineRenderingCreateInfo ri{VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO};
    ri.colorAttachmentCount = 1; ri.pColorAttachmentFormats = &colorFormat;
    ri.depthAttachmentFormat = depthFormat_;

    VkGraphicsPipelineCreateInfo pi{VK_STRUCTURE_TYPE_GRAPHICS_PIPELINE_CREATE_INFO};
    pi.pNext = &ri; pi.stageCount = 2; pi.pStages = stages;
    pi.pVertexInputState = &vin; pi.pInputAssemblyState = &ia; pi.pViewportState = &vp;
    pi.pRasterizationState = &rs; pi.pMultisampleState = &ms; pi.pDepthStencilState = &dss; pi.pColorBlendState = &cb;
    pi.pDynamicState = &ds; pi.layout = pipelineLayout_;
    VkResult r = vkCreateGraphicsPipelines(device_, VK_NULL_HANDLE, 1, &pi, nullptr, &pipelines_[0]);
    if (r == VK_SUCCESS) {
        rs.cullMode = VK_CULL_MODE_NONE;
        r = vkCreateGraphicsPipelines(device_, VK_NULL_HANDLE, 1, &pi, nullptr, &pipelines_[1]);
    }
    for (auto m : mods) vkDestroyShaderModule(device_, m, nullptr);
    VK_CHECK(r);
    pipelineFormat_ = colorFormat;
    return true;
}

bool VkRenderer::createFrames() {
    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT; pci.queueFamilyIndex = queueFamily_;
    VK_CHECK(vkCreateCommandPool(device_, &pci, nullptr, &pool_));
    VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    ai.commandPool = pool_; ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount = kFramesInFlight;
    VK_CHECK(vkAllocateCommandBuffers(device_, &ai, cmds_));
    for (uint32_t i = 0; i < kFramesInFlight; ++i) {
        VkSemaphoreCreateInfo si{VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO};
        VK_CHECK(vkCreateSemaphore(device_, &si, nullptr, &imageReady_[i]));
        VkFenceCreateInfo fi{VK_STRUCTURE_TYPE_FENCE_CREATE_INFO}; fi.flags = VK_FENCE_CREATE_SIGNALED_BIT;
        VK_CHECK(vkCreateFence(device_, &fi, nullptr, &inFlight_[i]));
    }
    return true;
}

void VkRenderer::recordScene(VkCommandBuffer cmd, VkImage image, VkImageView view, const GpuImage& depth,
                             VkExtent2D extent, VkImageLayout finalLayout, bool readbackDepth, const FrameParams& p) {
    const VkPipelineStageFlags2 depthStages =
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;
    imageBarrier(cmd, image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    // Contents are discarded (UNDEFINED) but the previous frame's depth writes must finish first.
    imageBarrier(cmd, depth.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                 depthStages, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                 depthStages, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                 VK_IMAGE_ASPECT_DEPTH_BIT);
    VkRenderingAttachmentInfo ca{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    ca.imageView = view; ca.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    ca.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR; ca.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    ca.clearValue.color = kClear;
    VkRenderingAttachmentInfo da{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    da.imageView = depth.view; da.imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    da.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    da.storeOp = readbackDepth ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE;
    da.clearValue.depthStencil = {kClearDepth, 0};
    VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
    ri.renderArea = {{0, 0}, extent}; ri.layerCount = 1;
    ri.colorAttachmentCount = 1; ri.pColorAttachments = &ca;
    ri.pDepthAttachment = &da;
    vkCmdBeginRendering(cmd, &ri);
    VkViewport v{0, 0, float(extent.width), float(extent.height), 0, 1};
    VkRect2D s{{0, 0}, extent};
    const glm::mat4 viewProj = p.camera.viewProjection(float(extent.width) / float(extent.height));
    vkCmdSetViewport(cmd, 0, 1, &v); vkCmdSetScissor(cmd, 0, 1, &s);
    int bound = -1;                                  // both pipelines share one layout + dynamic state
    for (const DrawItem& d : p.draws) {
        if (d.mesh >= meshes_.size()) continue;      // kInvalidMesh / stale id: nothing to draw
        const GpuMesh& m = meshes_[d.mesh];
        const VkDeviceSize zero = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &m.vertices.buffer, &zero);
        vkCmdBindIndexBuffer(cmd, m.indices.buffer, 0, VK_INDEX_TYPE_UINT32);
        const PushConstants pc{viewProj, d.model};
        vkCmdPushConstants(cmd, pipelineLayout_, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(pc), &pc);
        for (const assets::Submesh& sm : m.submeshes) {
            const int want = sm.doubleSided ? 1 : 0;
            if (want != bound) { vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelines_[want]); bound = want; }
            vkCmdDrawIndexed(cmd, sm.indexCount, 1, sm.firstIndex, 0, 0);
        }
    }
    vkCmdEndRendering(cmd);
    bool present = finalLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    imageBarrier(cmd, image, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, finalLayout,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                 present ? VK_PIPELINE_STAGE_2_NONE : VK_PIPELINE_STAGE_2_COPY_BIT,
                 present ? VK_ACCESS_2_NONE : VK_ACCESS_2_TRANSFER_READ_BIT);
    if (readbackDepth)
        imageBarrier(cmd, depth.image, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                     depthStages, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT, VK_IMAGE_ASPECT_DEPTH_BIT);
}

bool VkRenderer::drawFrame(const FrameParams& p) {
    if (resized_ || !swapchain_) {
        vkDeviceWaitIdle(device_);
        destroySwapchain();
        if (!createSwapchain()) return false;
        resized_ = false;
        if (!swapchain_) return true;                 // minimised
        if (swapFormat_ != pipelineFormat_) return false;
    }
    VK_CHECK(vkWaitForFences(device_, 1, &inFlight_[frame_], VK_TRUE, UINT64_MAX));
    uint32_t idx = 0;
    VkResult r = vkAcquireNextImageKHR(device_, swapchain_, UINT64_MAX, imageReady_[frame_], VK_NULL_HANDLE, &idx);
    if (r == VK_ERROR_OUT_OF_DATE_KHR) { resized_ = true; return true; }
    if (r != VK_SUCCESS && r != VK_SUBOPTIMAL_KHR) VK_CHECK(r);
    VK_CHECK(vkResetFences(device_, 1, &inFlight_[frame_]));

    VkCommandBuffer cmd = cmds_[frame_];
    vkResetCommandBuffer(cmd, 0);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
    recordScene(cmd, swapImages_[idx], swapViews_[idx], depth_, swapExtent_, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR, false, p);
    VK_CHECK(vkEndCommandBuffer(cmd));

    VkSemaphoreSubmitInfo wait{VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO};
    wait.semaphore = imageReady_[frame_]; wait.stageMask = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT;
    VkSemaphoreSubmitInfo signal{VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO};
    signal.semaphore = renderDone_[idx]; signal.stageMask = VK_PIPELINE_STAGE_2_ALL_GRAPHICS_BIT;
    VkCommandBufferSubmitInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO}; cbi.commandBuffer = cmd;
    VkSubmitInfo2 si{VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
    si.waitSemaphoreInfoCount = 1; si.pWaitSemaphoreInfos = &wait;
    si.commandBufferInfoCount = 1; si.pCommandBufferInfos = &cbi;
    si.signalSemaphoreInfoCount = 1; si.pSignalSemaphoreInfos = &signal;
    VK_CHECK(vkQueueSubmit2(queue_, 1, &si, inFlight_[frame_]));

    VkPresentInfoKHR pi{VK_STRUCTURE_TYPE_PRESENT_INFO_KHR};
    pi.waitSemaphoreCount = 1; pi.pWaitSemaphores = &renderDone_[idx];
    pi.swapchainCount = 1; pi.pSwapchains = &swapchain_; pi.pImageIndices = &idx;
    r = vkQueuePresentKHR(queue_, &pi);
    if (r == VK_ERROR_OUT_OF_DATE_KHR || r == VK_SUBOPTIMAL_KHR) resized_ = true;
    else if (r != VK_SUCCESS) VK_CHECK(r);
    frame_ = (frame_ + 1) % kFramesInFlight;
    return true;
}

bool VkRenderer::renderHeadlessAndVerify(const FrameParams& p) {
    const uint32_t W = cfg_.headlessWidth, H = cfg_.headlessHeight;
    GpuImage color, depth;
    GpuBuffer buf;
    if (!createImage({W, H}, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                     VK_IMAGE_ASPECT_COLOR_BIT, color)) return false;
    if (!createImage({W, H}, depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                     VK_IMAGE_ASPECT_DEPTH_BIT, depth)) return false;

    // One readback buffer: RGBA8 colour, then 32-bit float depth (both 4 bytes per pixel).
    const VkDeviceSize planeBytes = VkDeviceSize(W) * H * 4;
    if (!createBuffer(planeBytes * 2, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT, buf))
        return false;

    VkCommandBuffer cmd = cmds_[0];
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkResetFences(device_, 1, &inFlight_[0]));
    VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
    recordScene(cmd, color.image, color.view, depth, {W, H}, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, true, p);
    VkBufferImageCopy region{};
    region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
    region.imageExtent = {W, H, 1};
    vkCmdCopyImageToBuffer(cmd, color.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf.buffer, 1, &region);
    region.bufferOffset = planeBytes;
    region.imageSubresource = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 0, 1};
    vkCmdCopyImageToBuffer(cmd, depth.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf.buffer, 1, &region);
    VK_CHECK(vkEndCommandBuffer(cmd));
    VkCommandBufferSubmitInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO}; cbi.commandBuffer = cmd;
    VkSubmitInfo2 si{VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
    si.commandBufferInfoCount = 1; si.pCommandBufferInfos = &cbi;
    VK_CHECK(vkQueueSubmit2(queue_, 1, &si, inFlight_[0]));
    VK_CHECK(vkWaitForFences(device_, 1, &inFlight_[0], VK_TRUE, UINT64_MAX));

    VK_CHECK(vmaInvalidateAllocation(allocator_, buf.allocation, 0, VK_WHOLE_SIZE));
    const auto* rgba = static_cast<const uint8_t*>(buf.mapped);
    auto px = [&](uint32_t x, uint32_t y) { return rgba + (size_t(y) * W + x) * 4; };
    auto depthAt = [&](uint32_t x, uint32_t y) {
        float d; std::memcpy(&d, rgba + planeBytes + (size_t(y) * W + x) * 4, sizeof d); return d; };

    const uint8_t* corner = px(2, 2);
    const uint8_t* centre = px(W / 2, H / 2);
    const float cornerDepth = depthAt(2, 2), centreDepth = depthAt(W / 2, H / 2);
    // Depth of draws[0]'s origin (the game centres the model on it): the surface seen
    // at the centre pixel must be nearer, i.e. larger in reverse-Z. A back face winning
    // (wrong culling/winding/compare) would land behind it.
    const glm::mat4 model0 = p.draws.empty() ? glm::mat4(1.0f) : p.draws.front().model;
    const glm::vec4 originClip = p.camera.viewProjection(float(W) / float(H)) * model0[3];
    const float originDepth = originClip.z / originClip.w;

    // Shading must vary across the model (surfaces lit at different angles).
    int minL = 255, maxL = 0, samples = 0;
    for (uint32_t y = H / 16; y < H; y += H / 32)
        for (uint32_t x = W / 16; x < W; x += W / 32)
            if (depthAt(x, y) > 0.0f) {
                const uint8_t* c = px(x, y);
                const int l = (c[0] * 2 + c[1] * 5 + c[2]) / 8;   // rough luma
                ++samples; minL = std::min(minL, l); maxL = std::max(maxL, l);
            }

    const auto closeTo = [](uint8_t v, float ref) { return std::abs(int(v) - int(ref * 255.0f + 0.5f)) <= 3; };
    const bool cornerIsClear = closeTo(corner[0], kClear.float32[0]) && closeTo(corner[1], kClear.float32[1]) &&
                               closeTo(corner[2], kClear.float32[2]) && cornerDepth == kClearDepth;
    const int centreDiff = std::abs(int(centre[0]) - int(corner[0])) + std::abs(int(centre[1]) - int(corner[1])) +
                           std::abs(int(centre[2]) - int(corner[2]));
    // Non-clear and lit: clearly above the ambient-only level of a white surface (0.2 * 255).
    const bool centreIsLit = centreDiff > 60 && centreDepth > originDepth && centreDepth <= 1.0f;
    const bool shaded = samples >= 8 && maxL - minL > 20;
    std::printf("[headless] corner rgb(%u,%u,%u) depth %.5f | centre rgb(%u,%u,%u) depth %.5f (model origin %.5f) | "
                "%d model samples, luma %d..%d | depth format %d\n",
                corner[0], corner[1], corner[2], double(cornerDepth), centre[0], centre[1], centre[2],
                double(centreDepth), double(originDepth), samples, minL, maxL, int(depthFormat_));
    // Optional artefact for humans: build/<preset>/mesh.ppm
    if (FILE* f = std::fopen("mesh.ppm", "wb")) {
        std::fprintf(f, "P6\n%u %u\n255\n", W, H);
        for (uint32_t i = 0; i < W * H; ++i) std::fwrite(rgba + size_t(i) * 4, 1, 3, f);
        std::fclose(f);
    }
    destroyBuffer(buf);
    destroyImage(depth); destroyImage(color);
    return cornerIsClear && centreIsLit && shaded;
}

void VkRenderer::shutdown() {
    if (device_) {
        vkDeviceWaitIdle(device_);
        for (uint32_t i = 0; i < kFramesInFlight; ++i) {
            if (imageReady_[i]) vkDestroySemaphore(device_, imageReady_[i], nullptr);
            if (inFlight_[i]) vkDestroyFence(device_, inFlight_[i], nullptr);
        }
        if (pool_) vkDestroyCommandPool(device_, pool_, nullptr);
        for (auto& pl : pipelines_) if (pl) vkDestroyPipeline(device_, pl, nullptr);
        if (pipelineLayout_) vkDestroyPipelineLayout(device_, pipelineLayout_, nullptr);
        destroySwapchain();
        if (allocator_) {
            for (auto& m : meshes_) { destroyBuffer(m.vertices); destroyBuffer(m.indices); }
            meshes_.clear();
            vmaDestroyAllocator(allocator_);
        }
        vkDestroyDevice(device_, nullptr);
    }
    if (surface_) SDL_Vulkan_DestroySurface(instance_, surface_, nullptr);
    if (messenger_) {
        auto destroy = reinterpret_cast<PFN_vkDestroyDebugUtilsMessengerEXT>(
            vkGetInstanceProcAddr(instance_, "vkDestroyDebugUtilsMessengerEXT"));
        if (destroy) destroy(instance_, messenger_, nullptr);
    }
    if (instance_) vkDestroyInstance(instance_, nullptr);
    allocator_ = nullptr; pool_ = VK_NULL_HANDLE; pipelineLayout_ = VK_NULL_HANDLE; pipelines_[0] = pipelines_[1] = VK_NULL_HANDLE;
    device_ = VK_NULL_HANDLE; instance_ = VK_NULL_HANDLE; surface_ = VK_NULL_HANDLE; messenger_ = VK_NULL_HANDLE;
}

} // namespace coe
