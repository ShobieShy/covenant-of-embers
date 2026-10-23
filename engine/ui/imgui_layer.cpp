// SPDX-License-Identifier: Apache-2.0
#include "engine/ui/imgui_layer.hpp"

#include "engine/render/vk_renderer.hpp"

#include <imgui.h>
#include <imgui_impl_vulkan.h>

#include <algorithm>
#include <cstdio>

namespace coe {
namespace {

void checkVk(VkResult r) {
    if (r != VK_SUCCESS) std::fprintf(stderr, "[imgui] Vulkan error %d\n", int(r));
}

ImU32 toU32(glm::vec3 c, float a) {
    const auto b = [](float v) { return std::clamp(v, 0.0f, 1.0f); };
    return ImGui::ColorConvertFloat4ToU32(ImVec4(b(c.r), b(c.g), b(c.b), b(a)));
}

} // namespace

bool ImGuiLayer::init(VkRenderer& renderer) {
    shutdown();
    renderer_ = &renderer;
    IMGUI_CHECKVERSION();
    ctx_ = ImGui::CreateContext();
    ImGui::SetCurrentContext(ctx_);
    ImGuiIO& io = ImGui::GetIO();
    io.IniFilename = nullptr;   // no imgui.ini next to the binary
    io.LogFilename = nullptr;
    io.DisplaySize = ImVec2(1.0f, 1.0f);

    const OverlayInfo o = renderer.overlayInfo();
    ImGui_ImplVulkan_InitInfo info{};
    info.ApiVersion = o.apiVersion;
    info.Instance = o.instance;
    info.PhysicalDevice = o.phys;
    info.Device = o.device;
    info.QueueFamily = o.queueFamily;
    info.Queue = o.queue;
    info.DescriptorPoolSize = 8;   // internal pool: the font atlas (+ a few debug textures later)
    // Vertex/index buffers rotate over ImageCount RenderDrawData calls; 3 > the renderer's
    // 2 frames in flight, so a buffer is never rewritten while a frame still reads it.
    info.MinImageCount = 2;
    info.ImageCount = 3;
    info.UseDynamicRendering = true;
    info.PipelineInfoMain.MSAASamples = VK_SAMPLE_COUNT_1_BIT;   // the overlay pass draws on the resolved target
    VkPipelineRenderingCreateInfoKHR& pr = info.PipelineInfoMain.PipelineRenderingCreateInfo;
    pr.sType = VK_STRUCTURE_TYPE_PIPELINE_RENDERING_CREATE_INFO_KHR;
    pr.colorAttachmentCount = 1;
    static VkFormat format;   // the backend keeps the pointer until its pipeline is built (in Init)
    format = o.colorFormat;
    pr.pColorAttachmentFormats = &format;
    info.CheckVkResultFn = checkVk;
    if (!o.device || o.colorFormat == VK_FORMAT_UNDEFINED || !ImGui_ImplVulkan_Init(&info)) {
        std::fprintf(stderr, "[imgui] Vulkan backend init failed\n");
        shutdown();
        return false;
    }
    backend_ = true;
    return true;
}

void ImGuiLayer::shutdown() {
    if (!ctx_) return;
    ImGui::SetCurrentContext(ctx_);
    if (inFrame_) ImGui::EndFrame();
    if (backend_) {
        if (renderer_) renderer_->waitIdle();
        ImGui_ImplVulkan_Shutdown();
    }
    ImGui::DestroyContext(ctx_);
    ctx_ = nullptr;
    backend_ = inFrame_ = ended_ = false;
}

void ImGuiLayer::beginFrame(glm::vec2 displaySize, float dt) {
    if (!ctx_) return;
    ImGui::SetCurrentContext(ctx_);
    if (inFrame_) ImGui::EndFrame();
    ImGuiIO& io = ImGui::GetIO();
    io.DisplaySize = ImVec2(std::max(displaySize.x, 1.0f), std::max(displaySize.y, 1.0f));
    io.DeltaTime = dt > 0.0f ? dt : 1.0f / 60.0f;
    ImGui_ImplVulkan_NewFrame();
    ImGui::NewFrame();
    inFrame_ = true;
    ended_ = false;
}

void ImGuiLayer::drawText(glm::vec2 pos, std::string_view text, glm::vec3 color, float alpha, float size, bool shadow) {
    if (!inFrame_ || text.empty()) return;
    ImDrawList* dl = ImGui::GetForegroundDrawList();
    ImFont* font = ImGui::GetFont();
    const char* b = text.data();
    const char* e = b + text.size();
    if (shadow) dl->AddText(font, size, ImVec2(pos.x + 1.0f, pos.y + 1.0f), toU32(glm::vec3(0.0f), alpha * 0.8f), b, e);
    dl->AddText(font, size, ImVec2(pos.x, pos.y), toU32(color, alpha), b, e);
}

glm::vec2 ImGuiLayer::textSize(std::string_view text, float size) const {
    if (!inFrame_ || text.empty()) return glm::vec2(0.0f);
    const ImVec2 s = ImGui::GetFont()->CalcTextSizeA(size, 1e9f, 0.0f, text.data(), text.data() + text.size());
    return {s.x, s.y};
}

void ImGuiLayer::endFrame() {
    if (!inFrame_) return;
    ImGui::Render();
    inFrame_ = false;
    ended_ = true;
}

std::function<void(VkCommandBuffer)> ImGuiLayer::recorder() {
    if (!ended_) return {};
    return [this](VkCommandBuffer cmd) {
        if (!ctx_ || !ended_) return;
        ImGui::SetCurrentContext(ctx_);
        ImDrawData* dd = ImGui::GetDrawData();
        if (!dd) return;
        ImGui_ImplVulkan_RenderDrawData(dd, cmd);
        ++rendered_;
    };
}

} // namespace coe
