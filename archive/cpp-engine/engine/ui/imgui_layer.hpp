// SPDX-License-Identifier: Apache-2.0
#pragma once
// Dear ImGui debug overlay (BUILD_PLAN step 22, ADR-0001): owns one ImGui context and
// the ImGui Vulkan backend, and draws into VkRenderer's overlay pass
// (FrameParams::overlay). No platform backend yet: the caller feeds the display size
// and frame time, and nothing reads input (debug *text* only for now; panels that need
// the mouse wire SDL in later). No imgui.ini is written; the built-in ProggyClean font
// is used (no asset).
//
// Colours are linear RGB like every other engine colour: ImGui's shader writes them
// unchanged, so on the sRGB swapchain the hardware encodes them exactly like the scene's
// tints (a Fire number reads in the same orange as the Fire staff head).
//
// Per frame: beginFrame(); drawText()...; endFrame(); then set
// FrameParams::overlay = layer.recorder() before VkRenderer::drawFrame/renderHeadless.
#include <vulkan/vulkan.h>
#include <glm/glm.hpp>

#include <functional>
#include <string_view>

struct ImGuiContext;

namespace coe {

class VkRenderer;

class ImGuiLayer {
public:
    ImGuiLayer() = default;
    ImGuiLayer(const ImGuiLayer&) = delete;
    ImGuiLayer& operator=(const ImGuiLayer&) = delete;
    ~ImGuiLayer() { shutdown(); }

    // After renderer.init(). False (with the reason on stderr) if the backend can't start.
    bool init(VkRenderer& renderer);
    // Waits for the GPU (the backend frees buffers a frame may still read), then tears
    // ImGui down. Call before renderer.shutdown(); safe to call twice.
    void shutdown();
    bool ready() const { return ctx_ != nullptr; }

    void beginFrame(glm::vec2 displaySize, float dt);
    // Screen-space text, top-left at `pos` (pixels from the top-left of the target),
    // `size` in pixels, linear colour; `shadow` adds a 1 px dark drop shadow so it reads on
    // any background. Only between beginFrame and endFrame.
    void drawText(glm::vec2 pos, std::string_view text, glm::vec3 color, float alpha = 1.0f, float size = 20.0f,
                  bool shadow = true);
    // Width/height in pixels `text` takes at `size` (for centring).
    glm::vec2 textSize(std::string_view text, float size = 20.0f) const;
    void endFrame();
    // Records the last endFrame()'s draw data; for FrameParams::overlay. Records nothing
    // if no frame was ended (or it drew nothing).
    std::function<void(VkCommandBuffer)> recorder();
    unsigned framesRendered() const { return rendered_; }

private:
    VkRenderer* renderer_ = nullptr;
    ImGuiContext* ctx_ = nullptr;
    bool backend_ = false, inFrame_ = false, ended_ = false;
    unsigned rendered_ = 0;
};

} // namespace coe
