// SPDX-License-Identifier: Apache-2.0
// M1 renderer: Vulkan 1.3 instance/device/swapchain, dynamic rendering + synchronization2,
// a reverse-Z depth buffer, 2x MSAA with resolve (when supported), VMA-backed
// images/buffers, a per-frame-in-flight uniform buffer (camera + lighting) and indexed
// meshes (uploadMesh) drawn with {model, tint} push constants per FrameParams::draws entry.
// Step 21: base-colour textures (set 1, sRGB, blit-mipmapped) and a viewmodel pass with
// its own projection after a depth clear. Validation layer is used only when installed.
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
constexpr float kClearDepth = 0.0f;              // reverse-Z: 0 is infinitely far, test GREATER

constexpr VkSampleCountFlagBits kWantSamples = VK_SAMPLE_COUNT_2_BIT;   // Magewar: msaa_3d = 1 (2x)

struct PushConstants {
    glm::mat4 model;
    glm::vec4 tint;
};
static_assert(sizeof(PushConstants) == 80, "push constants must fit the guaranteed 128 bytes");

// std140 mirror of shaders/frame.glsl (every member 16-byte aligned).
struct FrameUniforms {
    glm::mat4 viewProj;
    glm::vec4 cameraPos;
    glm::vec4 toLight;
    glm::vec4 lightColor;
    glm::vec4 ambient;
    glm::vec4 fog;          // rgb colour, a density
};
static_assert(sizeof(FrameUniforms) == 144, "FrameUniforms must match shaders/frame.glsl (std140)");

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
                  VkImageAspectFlags aspect = VK_IMAGE_ASPECT_COLOR_BIT, uint32_t baseMip = 0, uint32_t mipCount = 1) {
    VkImageMemoryBarrier2 b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER_2};
    b.srcStageMask = srcStage; b.srcAccessMask = srcAccess;
    b.dstStageMask = dstStage; b.dstAccessMask = dstAccess;
    b.oldLayout = from; b.newLayout = to;
    b.srcQueueFamilyIndex = b.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    b.image = img;
    b.subresourceRange = {aspect, baseMip, mipCount, 0, 1};
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
    } else {
        pickSampleCount(VK_FORMAT_R8G8B8A8_UNORM);
        if (!createPipeline(VK_FORMAT_R8G8B8A8_UNORM)) return false;
    }
    std::printf("[vk] MSAA: %ux\n", unsigned(samples_));
    return createFrames() && createFrameUniforms() && createDefaultTexture();
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

void VkRenderer::pickSampleCount(VkFormat colorFormat) {
    VkPhysicalDeviceProperties props; vkGetPhysicalDeviceProperties(phys_, &props);
    const VkSampleCountFlags counts = props.limits.framebufferColorSampleCounts & props.limits.framebufferDepthSampleCounts;
    auto formatOk = [&](VkFormat f, VkImageUsageFlags usage) {
        VkImageFormatProperties ifp{};
        return vkGetPhysicalDeviceImageFormatProperties(phys_, f, VK_IMAGE_TYPE_2D, VK_IMAGE_TILING_OPTIMAL, usage, 0, &ifp) ==
                   VK_SUCCESS && (ifp.sampleCounts & kWantSamples);
    };
    samples_ = VK_SAMPLE_COUNT_1_BIT;
    if ((counts & kWantSamples) &&
        formatOk(colorFormat, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT) &&
        formatOk(depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT))
        samples_ = kWantSamples;
    else
        std::fprintf(stderr, "[vk] %ux MSAA unsupported for this colour/depth format; rendering without MSAA\n",
                     unsigned(kWantSamples));
    // Standard sample 0 positions (Vulkan spec "Standard sample locations"); used by the
    // headless check to unproject resolved (sample 0) depth at the right spot.
    sample0Pos_ = glm::vec2(0.5f);
    if (props.limits.standardSampleLocations && samples_ == VK_SAMPLE_COUNT_2_BIT) sample0Pos_ = glm::vec2(0.75f);
}

bool VkRenderer::createImage(VkExtent2D extent, VkFormat format, VkImageUsageFlags usage,
                             VkImageAspectFlags aspect, VkSampleCountFlagBits samples, GpuImage& out, uint32_t mipLevels) {
    VkImageCreateInfo ic{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ic.imageType = VK_IMAGE_TYPE_2D; ic.format = format; ic.extent = {extent.width, extent.height, 1};
    ic.mipLevels = mipLevels; ic.arrayLayers = 1; ic.samples = samples; ic.tiling = VK_IMAGE_TILING_OPTIMAL;
    ic.usage = usage;
    // Render targets get their own allocation (drivers like dedicated memory for attachments).
    VmaAllocationCreateInfo ac{};
    ac.usage = VMA_MEMORY_USAGE_AUTO_PREFER_DEVICE;
    ac.flags = VMA_ALLOCATION_CREATE_DEDICATED_MEMORY_BIT;
    VK_CHECK(vmaCreateImage(allocator_, &ic, &ac, &out.image, &out.allocation, nullptr));
    VkImageViewCreateInfo vi{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};
    vi.image = out.image; vi.viewType = VK_IMAGE_VIEW_TYPE_2D; vi.format = format;
    vi.subresourceRange = {aspect, 0, mipLevels, 0, 1};
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
    const size_t firstTexture = textures_.size();
    bool ok = device_ && uploadMeshImpl(mesh, g);
    for (size_t i = 0; ok && i < mesh.images.size(); ++i) {
        GpuImage img;
        ok = uploadTexture(mesh.images[i], img);
        if (ok) textures_.push_back(img);
        else destroyImage(img);
    }
    ok = ok && createMaterialSets(mesh, uint32_t(firstTexture), g);
    if (!ok) {
        destroyMesh(g);
        while (textures_.size() > firstTexture) { destroyImage(textures_.back()); textures_.pop_back(); }
        std::fprintf(stderr, "[vk] mesh upload failed\n");
        return kInvalidMesh;
    }
    meshes_.push_back(std::move(g));
    return static_cast<MeshId>(meshes_.size() - 1);
}

void VkRenderer::destroyMesh(GpuMesh& m) {
    destroyBuffer(m.vertices);
    destroyBuffer(m.indices);
    if (m.materialPool) vkDestroyDescriptorPool(device_, m.materialPool, nullptr);   // frees submeshSets
    m.materialPool = VK_NULL_HANDLE;
    m.submeshSets.clear();
}

bool VkRenderer::submitOnce(const std::function<void(VkCommandBuffer)>& record) {
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    VkFence fence = VK_NULL_HANDLE;
    auto run = [&]() -> bool {
        VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        ai.commandPool = pool_; ai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ai.commandBufferCount = 1;
        VK_CHECK(vkAllocateCommandBuffers(device_, &ai, &cmd));
        VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
        record(cmd);
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
    if (fence) vkDestroyFence(device_, fence, nullptr);
    if (cmd) vkFreeCommandBuffers(device_, pool_, 1, &cmd);
    return ok;
}

// RGBA8 sRGB texture; the full mip chain is generated with linear blits when the format
// supports it (glTF samplers expect mipmaps for the *_MIPMAP_* min filters).
bool VkRenderer::uploadTexture(const assets::ImageData& img, GpuImage& out) {
    if (img.width == 0 || img.height == 0 || img.rgba.size() != size_t(img.width) * img.height * 4) return false;
    const VkFormat fmt = VK_FORMAT_R8G8B8A8_SRGB;
    VkFormatProperties fp; vkGetPhysicalDeviceFormatProperties(phys_, fmt, &fp);
    const VkFormatFeatureFlags blit = VK_FORMAT_FEATURE_BLIT_SRC_BIT | VK_FORMAT_FEATURE_BLIT_DST_BIT |
                                      VK_FORMAT_FEATURE_SAMPLED_IMAGE_FILTER_LINEAR_BIT;
    uint32_t mips = 1;
    if ((fp.optimalTilingFeatures & blit) == blit)
        while ((std::max(img.width, img.height) >> mips) > 0) ++mips;
    VkImageUsageFlags usage = VK_IMAGE_USAGE_SAMPLED_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT;
    if (mips > 1) usage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    if (!createImage({img.width, img.height}, fmt, usage, VK_IMAGE_ASPECT_COLOR_BIT, VK_SAMPLE_COUNT_1_BIT, out, mips))
        return false;
    GpuBuffer staging;
    if (!createBuffer(img.rgba.size(), VK_BUFFER_USAGE_TRANSFER_SRC_BIT, VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT,
                      staging))
        return false;
    std::memcpy(staging.mapped, img.rgba.data(), img.rgba.size());
    vmaFlushAllocation(allocator_, staging.allocation, 0, VK_WHOLE_SIZE);
    const bool ok = submitOnce([&](VkCommandBuffer cmd) {
        const VkPipelineStageFlags2 xfer = VK_PIPELINE_STAGE_2_ALL_TRANSFER_BIT;
        imageBarrier(cmd, out.image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                     VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE, xfer, VK_ACCESS_2_TRANSFER_WRITE_BIT,
                     VK_IMAGE_ASPECT_COLOR_BIT, 0, mips);
        VkBufferImageCopy region{};
        region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.imageExtent = {img.width, img.height, 1};
        vkCmdCopyBufferToImage(cmd, staging.buffer, out.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &region);
        int32_t w = int32_t(img.width), h = int32_t(img.height);
        for (uint32_t i = 1; i < mips; ++i) {
            imageBarrier(cmd, out.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                         xfer, VK_ACCESS_2_TRANSFER_WRITE_BIT, xfer, VK_ACCESS_2_TRANSFER_READ_BIT,
                         VK_IMAGE_ASPECT_COLOR_BIT, i - 1, 1);
            VkImageBlit b{};
            b.srcSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i - 1, 0, 1};
            b.srcOffsets[1] = {w, h, 1};
            w = std::max(w / 2, 1); h = std::max(h / 2, 1);
            b.dstSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, i, 0, 1};
            b.dstOffsets[1] = {w, h, 1};
            vkCmdBlitImage(cmd, out.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, out.image,
                           VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &b, VK_FILTER_LINEAR);
        }
        if (mips > 1)
            imageBarrier(cmd, out.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                         xfer, VK_ACCESS_2_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                         VK_ACCESS_2_SHADER_SAMPLED_READ_BIT, VK_IMAGE_ASPECT_COLOR_BIT, 0, mips - 1);
        imageBarrier(cmd, out.image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,
                     xfer, VK_ACCESS_2_TRANSFER_WRITE_BIT, VK_PIPELINE_STAGE_2_FRAGMENT_SHADER_BIT,
                     VK_ACCESS_2_SHADER_SAMPLED_READ_BIT, VK_IMAGE_ASPECT_COLOR_BIT, mips - 1, 1);
    });
    destroyBuffer(staging);
    return ok;
}

VkSampler VkRenderer::sampler(const assets::SamplerDesc& d) {
    for (const auto& [desc, s] : samplers_)
        if (desc == d) return s;
    auto filter = [](assets::Filter f) { return f == assets::Filter::Nearest ? VK_FILTER_NEAREST : VK_FILTER_LINEAR; };
    auto wrap = [](assets::Wrap w) {
        return w == assets::Wrap::ClampToEdge ? VK_SAMPLER_ADDRESS_MODE_CLAMP_TO_EDGE
             : w == assets::Wrap::MirroredRepeat ? VK_SAMPLER_ADDRESS_MODE_MIRRORED_REPEAT : VK_SAMPLER_ADDRESS_MODE_REPEAT;
    };
    VkSamplerCreateInfo ci{VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO};
    ci.magFilter = filter(d.mag);
    ci.minFilter = filter(d.min);
    ci.mipmapMode = d.mip == assets::Filter::Nearest ? VK_SAMPLER_MIPMAP_MODE_NEAREST : VK_SAMPLER_MIPMAP_MODE_LINEAR;
    ci.addressModeU = wrap(d.wrapU);
    ci.addressModeV = wrap(d.wrapV);
    ci.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
    ci.minLod = 0.0f;
    ci.maxLod = d.mipmaps ? VK_LOD_CLAMP_NONE : 0.0f;   // glTF NEAREST / LINEAR min filter: base level only
    VkSampler s = VK_NULL_HANDLE;
    if (vkCreateSampler(device_, &ci, nullptr, &s) != VK_SUCCESS) return VK_NULL_HANDLE;
    samplers_.emplace_back(d, s);
    return s;
}

bool VkRenderer::createDefaultTexture() {
    assets::ImageData white;
    white.width = white.height = 1;
    white.rgba = {255, 255, 255, 255};
    white.name = "default white";
    GpuImage img;
    if (!uploadTexture(white, img)) { destroyImage(img); return false; }
    textures_.push_back(img);   // textures_[0]
    return sampler({}) != VK_NULL_HANDLE;
}

// One set per submesh: its material's base-colour image (offset by `firstTexture`, where
// this mesh's images start in textures_) and sampler, or the white default.
bool VkRenderer::createMaterialSets(const assets::MeshData& mesh, uint32_t firstTexture, GpuMesh& out) {
    const uint32_t n = uint32_t(out.submeshes.size());
    VkDescriptorPoolSize ps{VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER, n};
    VkDescriptorPoolCreateInfo pi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pi.maxSets = n; pi.poolSizeCount = 1; pi.pPoolSizes = &ps;
    VK_CHECK(vkCreateDescriptorPool(device_, &pi, nullptr, &out.materialPool));
    std::vector<VkDescriptorSetLayout> layouts(n, materialSetLayout_);
    out.submeshSets.resize(n);
    VkDescriptorSetAllocateInfo ai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    ai.descriptorPool = out.materialPool; ai.descriptorSetCount = n; ai.pSetLayouts = layouts.data();
    VK_CHECK(vkAllocateDescriptorSets(device_, &ai, out.submeshSets.data()));
    for (uint32_t i = 0; i < n; ++i) {
        const int32_t m = out.submeshes[i].material;
        VkDescriptorImageInfo ii{sampler({}), textures_[0].view, VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL};
        if (m >= 0 && size_t(m) < mesh.materials.size()) {
            const assets::MaterialData& mat = mesh.materials[size_t(m)];
            if (mat.baseColorImage >= 0 && size_t(mat.baseColorImage) < mesh.images.size()) {
                ii.imageView = textures_[firstTexture + uint32_t(mat.baseColorImage)].view;
                ii.sampler = sampler(mat.sampler);
            }
        }
        if (!ii.sampler) return false;
        VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
        w.dstSet = out.submeshSets[i]; w.dstBinding = 0; w.descriptorCount = 1;
        w.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; w.pImageInfo = &ii;
        vkUpdateDescriptorSets(device_, 1, &w, 0, nullptr);
    }
    return true;
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
    ci.imageArrayLayers = 1; ci.imageUsage = VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT;   // also the MSAA resolve target
    // Step 21: frame capture (requestCapture) copies from the swapchain image.
    captureSupported_ = (caps.supportedUsageFlags & VK_IMAGE_USAGE_TRANSFER_SRC_BIT) != 0;
    if (captureSupported_) ci.imageUsage |= VK_IMAGE_USAGE_TRANSFER_SRC_BIT;
    ci.imageSharingMode = VK_SHARING_MODE_EXCLUSIVE;
    ci.preTransform = caps.currentTransform;
    ci.compositeAlpha = VK_COMPOSITE_ALPHA_OPAQUE_BIT_KHR;
    ci.presentMode = VK_PRESENT_MODE_FIFO_KHR;      // always available, vsync
    ci.clipped = VK_TRUE;
    VK_CHECK(vkCreateSwapchainKHR(device_, &ci, nullptr, &swapchain_));
    if (swapFormat_ == VK_FORMAT_UNDEFINED) pickSampleCount(fmt.format);   // first swapchain: fixes samples_ + pipeline format
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
    // Depth (and the MSAA colour, resolved before present) is only used within a frame,
    // so one image is shared by both frames in flight; recordScene's barriers order
    // frame N+1's clears after frame N's writes.
    if (samples_ != VK_SAMPLE_COUNT_1_BIT &&
        !createImage(swapExtent_, swapFormat_, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
                     VK_IMAGE_ASPECT_COLOR_BIT, samples_, msaaColor_))
        return false;
    return createImage(swapExtent_, depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT,
                       VK_IMAGE_ASPECT_DEPTH_BIT, samples_, depth_);
}

void VkRenderer::destroySwapchain() {
    for (auto s : renderDone_) vkDestroySemaphore(device_, s, nullptr);
    for (auto v : swapViews_) vkDestroyImageView(device_, v, nullptr);
    renderDone_.clear(); swapViews_.clear(); swapImages_.clear();
    destroyImage(depth_);
    destroyImage(msaaColor_);
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
    VkDescriptorSetLayoutBinding ub{};
    ub.binding = 0; ub.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; ub.descriptorCount = 1;
    ub.stageFlags = VK_SHADER_STAGE_VERTEX_BIT | VK_SHADER_STAGE_FRAGMENT_BIT;
    VkDescriptorSetLayoutCreateInfo dli{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_LAYOUT_CREATE_INFO};
    dli.bindingCount = 1; dli.pBindings = &ub;
    VK_CHECK(vkCreateDescriptorSetLayout(device_, &dli, nullptr, &frameSetLayout_));
    VkDescriptorSetLayoutBinding tb{};
    tb.binding = 0; tb.descriptorType = VK_DESCRIPTOR_TYPE_COMBINED_IMAGE_SAMPLER; tb.descriptorCount = 1;
    tb.stageFlags = VK_SHADER_STAGE_FRAGMENT_BIT;
    dli.pBindings = &tb;
    VK_CHECK(vkCreateDescriptorSetLayout(device_, &dli, nullptr, &materialSetLayout_));
    const VkDescriptorSetLayout setLayouts[2] = {frameSetLayout_, materialSetLayout_};
    VkPushConstantRange pcr{VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(PushConstants)};
    VkPipelineLayoutCreateInfo li{VK_STRUCTURE_TYPE_PIPELINE_LAYOUT_CREATE_INFO};
    li.setLayoutCount = 2; li.pSetLayouts = setLayouts;
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
    ms.rasterizationSamples = samples_;
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

bool VkRenderer::createFrameUniforms() {
    VkDescriptorPoolSize ps{VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER, kFrameSlots};
    VkDescriptorPoolCreateInfo pi{VK_STRUCTURE_TYPE_DESCRIPTOR_POOL_CREATE_INFO};
    pi.maxSets = kFrameSlots; pi.poolSizeCount = 1; pi.pPoolSizes = &ps;
    VK_CHECK(vkCreateDescriptorPool(device_, &pi, nullptr, &descPool_));
    VkDescriptorSetLayout layouts[kFrameSlots];
    std::fill(std::begin(layouts), std::end(layouts), frameSetLayout_);
    VkDescriptorSetAllocateInfo ai{VK_STRUCTURE_TYPE_DESCRIPTOR_SET_ALLOCATE_INFO};
    ai.descriptorPool = descPool_; ai.descriptorSetCount = kFrameSlots; ai.pSetLayouts = layouts;
    VK_CHECK(vkAllocateDescriptorSets(device_, &ai, frameSets_));
    for (uint32_t i = 0; i < kFrameSlots; ++i) {
        if (!createBuffer(sizeof(FrameUniforms), VK_BUFFER_USAGE_UNIFORM_BUFFER_BIT,
                          VMA_ALLOCATION_CREATE_HOST_ACCESS_SEQUENTIAL_WRITE_BIT, frameUbo_[i]))
            return false;
        VkDescriptorBufferInfo bi{frameUbo_[i].buffer, 0, sizeof(FrameUniforms)};
        VkWriteDescriptorSet w{VK_STRUCTURE_TYPE_WRITE_DESCRIPTOR_SET};
        w.dstSet = frameSets_[i]; w.dstBinding = 0; w.descriptorCount = 1;
        w.descriptorType = VK_DESCRIPTOR_TYPE_UNIFORM_BUFFER; w.pBufferInfo = &bi;
        vkUpdateDescriptorSets(device_, 1, &w, 0, nullptr);
    }
    return true;
}

// Call only after this frame's fence has signalled (the GPU is done reading the buffer).
void VkRenderer::writeFrameUniforms(uint32_t slot, const glm::mat4& viewProj, const glm::vec3& eye,
                                    const glm::vec3& toLight, const FrameLighting& l, bool fog) {
    const FrameUniforms u{viewProj, glm::vec4(eye, 1.0f), glm::vec4(toLight, 0.0f),
                          glm::vec4(l.lightColor, 0.0f), glm::vec4(l.ambient, 0.0f),
                          glm::vec4(l.fogColor, fog ? l.fogDensity : 0.0f)};
    std::memcpy(frameUbo_[slot].mapped, &u, sizeof u);
    vmaFlushAllocation(allocator_, frameUbo_[slot].allocation, 0, VK_WHOLE_SIZE);   // no-op on coherent memory
}

// World uniforms (slot frame*2) and viewmodel uniforms (slot frame*2+1): the viewmodel
// is already in view space, so its "eye" is the origin and the light is turned into view
// space; its projection has the fixed viewmodel FOV and a near plane close enough for a
// staff held 0.3 m from the eye. No fog on the hands.
void VkRenderer::writeFrame(uint32_t frame, const FrameParams& p, float aspect, glm::mat4& viewProj) {
    viewProj = p.camera.viewProjection(aspect);
    writeFrameUniforms(frame * 2, viewProj, p.camera.position, p.lighting.toLight, p.lighting, true);
    Camera vm;
    vm.fovYDeg = p.viewmodelFovYDeg;
    vm.nearZ = p.viewmodelNear;
    const glm::vec3 toLightView = glm::mat3(p.camera.view()) * p.lighting.toLight;
    writeFrameUniforms(frame * 2 + 1, vm.projection(aspect), glm::vec3(0.0f), toLightView, p.lighting, false);
}

void VkRenderer::drawItems(VkCommandBuffer cmd, const std::vector<DrawItem>& items) {
    int bound = -1;                                  // both pipelines share one layout + dynamic state
    VkDescriptorSet boundSet = VK_NULL_HANDLE;
    for (const DrawItem& d : items) {
        if (d.mesh >= meshes_.size()) continue;      // kInvalidMesh / stale id: nothing to draw
        const GpuMesh& m = meshes_[d.mesh];
        const VkDeviceSize zero = 0;
        vkCmdBindVertexBuffers(cmd, 0, 1, &m.vertices.buffer, &zero);
        vkCmdBindIndexBuffer(cmd, m.indices.buffer, 0, VK_INDEX_TYPE_UINT32);
        const PushConstants pc{d.model, d.tint};
        vkCmdPushConstants(cmd, pipelineLayout_, VK_SHADER_STAGE_VERTEX_BIT, 0, sizeof(pc), &pc);
        for (size_t i = 0; i < m.submeshes.size(); ++i) {
            const assets::Submesh& sm = m.submeshes[i];
            const int want = sm.doubleSided ? 1 : 0;
            if (want != bound) { vkCmdBindPipeline(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelines_[want]); bound = want; }
            if (m.submeshSets[i] != boundSet) {
                boundSet = m.submeshSets[i];
                vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout_, 1, 1, &boundSet, 0, nullptr);
            }
            vkCmdDrawIndexed(cmd, sm.indexCount, 1, sm.firstIndex, 0, 0);
        }
    }
}

void VkRenderer::recordScene(VkCommandBuffer cmd, const SceneTarget& t, uint32_t frame, const FrameParams& p) {
    const VkPipelineStageFlags2 depthStages =
        VK_PIPELINE_STAGE_2_EARLY_FRAGMENT_TESTS_BIT | VK_PIPELINE_STAGE_2_LATE_FRAGMENT_TESTS_BIT;
    // Resolves run in COLOR_ATTACHMENT_OUTPUT; a depth resolve may be counted as a
    // depth write, so its barriers cover both.
    const VkPipelineStageFlags2 resolveStages = VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT | depthStages;
    const VkAccessFlags2 resolveDepthAccess =
        VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT;
    const bool msaa = t.msaaColor != nullptr;
    // Target (swapchain image / headless colour): contents discarded; the acquire
    // semaphore waits at COLOR_ATTACHMENT_OUTPUT, where both drawing and resolving write.
    imageBarrier(cmd, t.target, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, 0,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    // Shared MSAA colour + depth: discarded too, but the previous frame's writes must finish first.
    if (msaa)
        imageBarrier(cmd, t.msaaColor->image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                     VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                     VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
    imageBarrier(cmd, t.depth->image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                 depthStages, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                 depthStages, VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_READ_BIT | VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                 VK_IMAGE_ASPECT_DEPTH_BIT);
    if (t.depthResolve)
        imageBarrier(cmd, t.depthResolve->image, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                     resolveStages, 0, resolveStages, resolveDepthAccess, VK_IMAGE_ASPECT_DEPTH_BIT);

    VkRenderingAttachmentInfo ca{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    ca.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    ca.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    ca.clearValue.color = {{p.clearColor.r, p.clearColor.g, p.clearColor.b, 1.0f}};
    if (msaa) {
        ca.imageView = t.msaaColor->view;
        ca.storeOp = VK_ATTACHMENT_STORE_OP_DONT_CARE;   // only the resolved image survives
        ca.resolveMode = VK_RESOLVE_MODE_AVERAGE_BIT;
        ca.resolveImageView = t.targetView;
        ca.resolveImageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
    } else {
        ca.imageView = t.targetView;
        ca.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
    }
    VkRenderingAttachmentInfo da{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
    da.imageView = t.depth->view; da.imageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    da.loadOp = VK_ATTACHMENT_LOAD_OP_CLEAR;
    da.storeOp = (t.readbackDepth && !t.depthResolve) ? VK_ATTACHMENT_STORE_OP_STORE : VK_ATTACHMENT_STORE_OP_DONT_CARE;
    da.clearValue.depthStencil = {kClearDepth, 0};
    if (t.depthResolve) {
        // SAMPLE_ZERO is the one depth resolve mode every implementation supports.
        da.resolveMode = VK_RESOLVE_MODE_SAMPLE_ZERO_BIT;
        da.resolveImageView = t.depthResolve->view;
        da.resolveImageLayout = VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL;
    }
    VkRenderingInfo ri{VK_STRUCTURE_TYPE_RENDERING_INFO};
    ri.renderArea = {{0, 0}, t.extent}; ri.layerCount = 1;
    ri.colorAttachmentCount = 1; ri.pColorAttachments = &ca;
    ri.pDepthAttachment = &da;
    vkCmdBeginRendering(cmd, &ri);
    VkViewport v{0, 0, float(t.extent.width), float(t.extent.height), 0, 1};
    VkRect2D s{{0, 0}, t.extent};
    vkCmdSetViewport(cmd, 0, 1, &v); vkCmdSetScissor(cmd, 0, 1, &s);
    vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout_, 0, 1, &frameSets_[frame * 2], 0, nullptr);
    drawItems(cmd, p.draws);
    if (!p.viewmodelDraws.empty()) {
        // Viewmodel pass: fresh depth so the staff never sinks into a wall in front of it.
        VkClearAttachment clear{};
        clear.aspectMask = VK_IMAGE_ASPECT_DEPTH_BIT;
        clear.clearValue.depthStencil = {kClearDepth, 0};
        const VkClearRect rect{{{0, 0}, t.extent}, 0, 1};
        vkCmdClearAttachments(cmd, 1, &clear, 1, &rect);
        vkCmdBindDescriptorSets(cmd, VK_PIPELINE_BIND_POINT_GRAPHICS, pipelineLayout_, 0, 1, &frameSets_[frame * 2 + 1],
                                0, nullptr);
        drawItems(cmd, p.viewmodelDraws);
    }
    vkCmdEndRendering(cmd);
    if (p.overlay) {
        // Step 22 overlay pass: on the resolved single-sample target, after the scene's
        // (resolve) writes; keeps its contents and draws on top, no depth.
        imageBarrier(cmd, t.target, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL,
                     VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT,
                     VK_ACCESS_2_COLOR_ATTACHMENT_READ_BIT | VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT);
        VkRenderingAttachmentInfo oa{VK_STRUCTURE_TYPE_RENDERING_ATTACHMENT_INFO};
        oa.imageView = t.targetView;
        oa.imageLayout = VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL;
        oa.loadOp = VK_ATTACHMENT_LOAD_OP_LOAD;
        oa.storeOp = VK_ATTACHMENT_STORE_OP_STORE;
        VkRenderingInfo ori{VK_STRUCTURE_TYPE_RENDERING_INFO};
        ori.renderArea = {{0, 0}, t.extent}; ori.layerCount = 1;
        ori.colorAttachmentCount = 1; ori.pColorAttachments = &oa;
        vkCmdBeginRendering(cmd, &ori);
        vkCmdSetViewport(cmd, 0, 1, &v); vkCmdSetScissor(cmd, 0, 1, &s);
        p.overlay(cmd);
        vkCmdEndRendering(cmd);
    }
    const bool present = t.finalLayout == VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    imageBarrier(cmd, t.target, VK_IMAGE_LAYOUT_COLOR_ATTACHMENT_OPTIMAL, t.finalLayout,
                 VK_PIPELINE_STAGE_2_COLOR_ATTACHMENT_OUTPUT_BIT, VK_ACCESS_2_COLOR_ATTACHMENT_WRITE_BIT,
                 present ? VK_PIPELINE_STAGE_2_NONE : VK_PIPELINE_STAGE_2_COPY_BIT,
                 present ? VK_ACCESS_2_NONE : VK_ACCESS_2_TRANSFER_READ_BIT);
    if (t.readbackDepth) {
        const bool resolved = t.depthResolve != nullptr;
        imageBarrier(cmd, resolved ? t.depthResolve->image : t.depth->image, VK_IMAGE_LAYOUT_DEPTH_ATTACHMENT_OPTIMAL,
                     VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, resolved ? resolveStages : depthStages,
                     resolved ? resolveDepthAccess : VK_ACCESS_2_DEPTH_STENCIL_ATTACHMENT_WRITE_BIT,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT, VK_IMAGE_ASPECT_DEPTH_BIT);
    }
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

    glm::mat4 viewProj;
    writeFrame(frame_, p, float(swapExtent_.width) / float(swapExtent_.height), viewProj);
    const bool capture = captureRequested_ && captureSupported_;
    GpuBuffer captureBuf;
    const VkDeviceSize captureBytes = VkDeviceSize(swapExtent_.width) * swapExtent_.height * 4;
    if (capture && !createBuffer(captureBytes, VK_BUFFER_USAGE_TRANSFER_DST_BIT,
                                 VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT, captureBuf))
        return false;
    VkCommandBuffer cmd = cmds_[frame_];
    vkResetCommandBuffer(cmd, 0);
    VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
    SceneTarget t;
    t.target = swapImages_[idx]; t.targetView = swapViews_[idx]; t.finalLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    t.msaaColor = msaaColor_.image ? &msaaColor_ : nullptr;
    t.depth = &depth_; t.extent = swapExtent_;
    if (capture) t.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    recordScene(cmd, t, frame_, p);
    if (capture) {
        VkBufferImageCopy region{};
        region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.imageExtent = {swapExtent_.width, swapExtent_.height, 1};
        vkCmdCopyImageToBuffer(cmd, t.target, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, captureBuf.buffer, 1, &region);
        imageBarrier(cmd, t.target, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,
                     VK_PIPELINE_STAGE_2_COPY_BIT, VK_ACCESS_2_TRANSFER_READ_BIT, VK_PIPELINE_STAGE_2_NONE, VK_ACCESS_2_NONE);
        VkMemoryBarrier2 mb{VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
        mb.srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT; mb.srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT;
        mb.dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT; mb.dstAccessMask = VK_ACCESS_2_HOST_READ_BIT;
        VkDependencyInfo dep{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
        dep.memoryBarrierCount = 1; dep.pMemoryBarriers = &mb;
        vkCmdPipelineBarrier2(cmd, &dep);
    }
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
    if (capture) {
        // One-time stall: wait for this frame, then convert the copy to RGBA bytes.
        const bool done = vkWaitForFences(device_, 1, &inFlight_[frame_], VK_TRUE, UINT64_MAX) == VK_SUCCESS &&
                          vmaInvalidateAllocation(allocator_, captureBuf.allocation, 0, VK_WHOLE_SIZE) == VK_SUCCESS;
        if (done) {
            const auto* bytes = static_cast<const uint8_t*>(captureBuf.mapped);
            capture_ = {};
            capture_.width = swapExtent_.width; capture_.height = swapExtent_.height;
            capture_.samples = uint32_t(samples_);
            capture_.viewProj = viewProj;
            capture_.rgba.assign(bytes, bytes + captureBytes);
            capture_.srgb = swapFormat_ == VK_FORMAT_B8G8R8A8_SRGB || swapFormat_ == VK_FORMAT_R8G8B8A8_SRGB ||
                            swapFormat_ == VK_FORMAT_A8B8G8R8_SRGB_PACK32;
            if (swapFormat_ == VK_FORMAT_B8G8R8A8_SRGB || swapFormat_ == VK_FORMAT_B8G8R8A8_UNORM)
                for (size_t i = 0; i + 3 < capture_.rgba.size(); i += 4) std::swap(capture_.rgba[i], capture_.rgba[i + 2]);
            captureReady_ = true;
            captureRequested_ = false;
        }
        destroyBuffer(captureBuf);
        if (!done) return false;
    }
    frame_ = (frame_ + 1) % kFramesInFlight;
    return true;
}

bool VkRenderer::takeCapture(HeadlessFrame& out) {
    if (!captureReady_) return false;
    out = std::move(capture_);
    capture_ = {};
    captureReady_ = false;
    return true;
}

bool VkRenderer::renderHeadless(const FrameParams& p, HeadlessFrame& out) {
    const uint32_t W = cfg_.headlessWidth, H = cfg_.headlessHeight;
    const bool msaa = samples_ != VK_SAMPLE_COUNT_1_BIT;
    GpuImage color, depth, msaaColor, depthResolve;
    GpuBuffer buf;
    auto cleanup = [&] {
        destroyBuffer(buf);
        destroyImage(depthResolve); destroyImage(msaaColor); destroyImage(depth); destroyImage(color);
    };
    auto run = [&]() -> bool {
        // Single-sample images that are read back: the resolve targets with MSAA, the
        // attachments themselves without.
        if (!createImage({W, H}, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                         VK_IMAGE_ASPECT_COLOR_BIT, VK_SAMPLE_COUNT_1_BIT, color)) return false;
        const VkImageUsageFlags depthUse = VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | (msaa ? 0 : VK_IMAGE_USAGE_TRANSFER_SRC_BIT);
        if (!createImage({W, H}, depthFormat_, depthUse, VK_IMAGE_ASPECT_DEPTH_BIT, samples_, depth)) return false;
        if (msaa &&
            (!createImage({W, H}, VK_FORMAT_R8G8B8A8_UNORM, VK_IMAGE_USAGE_COLOR_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSIENT_ATTACHMENT_BIT,
                          VK_IMAGE_ASPECT_COLOR_BIT, samples_, msaaColor) ||
             !createImage({W, H}, depthFormat_, VK_IMAGE_USAGE_DEPTH_STENCIL_ATTACHMENT_BIT | VK_IMAGE_USAGE_TRANSFER_SRC_BIT,
                          VK_IMAGE_ASPECT_DEPTH_BIT, VK_SAMPLE_COUNT_1_BIT, depthResolve)))
            return false;

        // One readback buffer: RGBA8 colour, then 32-bit float depth (both 4 bytes per pixel).
        const VkDeviceSize planeBytes = VkDeviceSize(W) * H * 4;
        if (!createBuffer(planeBytes * 2, VK_BUFFER_USAGE_TRANSFER_DST_BIT, VMA_ALLOCATION_CREATE_HOST_ACCESS_RANDOM_BIT, buf))
            return false;

        VK_CHECK(vkWaitForFences(device_, 1, &inFlight_[0], VK_TRUE, UINT64_MAX));
        glm::mat4 viewProj;
        writeFrame(0, p, float(W) / float(H), viewProj);
        VkCommandBuffer cmd = cmds_[0];
        VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        bi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        VK_CHECK(vkResetFences(device_, 1, &inFlight_[0]));
        VK_CHECK(vkResetCommandBuffer(cmd, 0));
        VK_CHECK(vkBeginCommandBuffer(cmd, &bi));
        SceneTarget t;
        t.target = color.image; t.targetView = color.view; t.finalLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
        t.msaaColor = msaa ? &msaaColor : nullptr;
        t.depth = &depth; t.depthResolve = msaa ? &depthResolve : nullptr;
        t.readbackDepth = true; t.extent = {W, H};
        recordScene(cmd, t, 0, p);
        VkBufferImageCopy region{};
        region.imageSubresource = {VK_IMAGE_ASPECT_COLOR_BIT, 0, 0, 1};
        region.imageExtent = {W, H, 1};
        vkCmdCopyImageToBuffer(cmd, color.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, buf.buffer, 1, &region);
        region.bufferOffset = planeBytes;
        region.imageSubresource = {VK_IMAGE_ASPECT_DEPTH_BIT, 0, 0, 1};
        vkCmdCopyImageToBuffer(cmd, msaa ? depthResolve.image : depth.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                               buf.buffer, 1, &region);
        // Make the copies visible to the host reads below.
        VkMemoryBarrier2 mb{VK_STRUCTURE_TYPE_MEMORY_BARRIER_2};
        mb.srcStageMask = VK_PIPELINE_STAGE_2_COPY_BIT; mb.srcAccessMask = VK_ACCESS_2_TRANSFER_WRITE_BIT;
        mb.dstStageMask = VK_PIPELINE_STAGE_2_HOST_BIT; mb.dstAccessMask = VK_ACCESS_2_HOST_READ_BIT;
        VkDependencyInfo dep{VK_STRUCTURE_TYPE_DEPENDENCY_INFO};
        dep.memoryBarrierCount = 1; dep.pMemoryBarriers = &mb;
        vkCmdPipelineBarrier2(cmd, &dep);
        VK_CHECK(vkEndCommandBuffer(cmd));
        VkCommandBufferSubmitInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO}; cbi.commandBuffer = cmd;
        VkSubmitInfo2 si{VK_STRUCTURE_TYPE_SUBMIT_INFO_2};
        si.commandBufferInfoCount = 1; si.pCommandBufferInfos = &cbi;
        VK_CHECK(vkQueueSubmit2(queue_, 1, &si, inFlight_[0]));
        VK_CHECK(vkWaitForFences(device_, 1, &inFlight_[0], VK_TRUE, UINT64_MAX));

        VK_CHECK(vmaInvalidateAllocation(allocator_, buf.allocation, 0, VK_WHOLE_SIZE));
        const auto* bytes = static_cast<const uint8_t*>(buf.mapped);
        out.width = W; out.height = H;
        out.samples = uint32_t(samples_);
        out.depthSamplePos = sample0Pos_;
        out.viewProj = viewProj;
        out.rgba.assign(bytes, bytes + planeBytes);
        out.depth.resize(size_t(W) * H);
        std::memcpy(out.depth.data(), bytes + planeBytes, planeBytes);
        std::printf("[headless] %ux%u, %ux MSAA (resolved), depth format %d\n", W, H, unsigned(samples_), int(depthFormat_));
        return true;
    };
    const bool ok = run();
    cleanup();
    return ok;
}

OverlayInfo VkRenderer::overlayInfo() const {
    OverlayInfo o;
    o.instance = instance_; o.phys = phys_; o.device = device_;
    o.queueFamily = queueFamily_; o.queue = queue_;
    o.colorFormat = pipelineFormat_;   // the swapchain format in window mode, R8G8B8A8_UNORM headless
    o.apiVersion = VK_API_VERSION_1_3;
    return o;
}

VkExtent2D VkRenderer::targetExtent() const {
    return cfg_.window ? swapExtent_ : VkExtent2D{cfg_.headlessWidth, cfg_.headlessHeight};
}

void VkRenderer::waitIdle() {
    if (device_) vkDeviceWaitIdle(device_);
}

void VkRenderer::shutdown() {
    if (device_) {
        vkDeviceWaitIdle(device_);
        for (uint32_t i = 0; i < kFramesInFlight; ++i) {
            if (imageReady_[i]) vkDestroySemaphore(device_, imageReady_[i], nullptr);
            if (inFlight_[i]) vkDestroyFence(device_, inFlight_[i], nullptr);
        }
        if (pool_) vkDestroyCommandPool(device_, pool_, nullptr);
        if (descPool_) vkDestroyDescriptorPool(device_, descPool_, nullptr);   // frees frameSets_
        if (frameSetLayout_) vkDestroyDescriptorSetLayout(device_, frameSetLayout_, nullptr);
        if (materialSetLayout_) vkDestroyDescriptorSetLayout(device_, materialSetLayout_, nullptr);
        for (auto& [desc, smp] : samplers_) vkDestroySampler(device_, smp, nullptr);
        samplers_.clear();
        for (auto& pl : pipelines_) if (pl) vkDestroyPipeline(device_, pl, nullptr);
        if (pipelineLayout_) vkDestroyPipelineLayout(device_, pipelineLayout_, nullptr);
        destroySwapchain();
        if (allocator_) {
            for (auto& m : meshes_) destroyMesh(m);
            for (auto& tex : textures_) destroyImage(tex);
            textures_.clear();
            for (auto& u : frameUbo_) destroyBuffer(u);
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
    descPool_ = VK_NULL_HANDLE; frameSetLayout_ = VK_NULL_HANDLE; materialSetLayout_ = VK_NULL_HANDLE;
    for (auto& set : frameSets_) set = VK_NULL_HANDLE;
    allocator_ = nullptr; pool_ = VK_NULL_HANDLE; pipelineLayout_ = VK_NULL_HANDLE; pipelines_[0] = pipelines_[1] = VK_NULL_HANDLE;
    device_ = VK_NULL_HANDLE; instance_ = VK_NULL_HANDLE; surface_ = VK_NULL_HANDLE; messenger_ = VK_NULL_HANDLE;
}

} // namespace coe
