// Covenant of Embers - game entry point: window + Vulkan triangle on a fixed-timestep loop.
// SPDX-License-Identifier: Apache-2.0
//   covenant                 run until the window is closed
//   covenant --seconds N     auto-quit after N seconds (smoke test; checks the tick count)
//   covenant --headless      render offscreen once, verify pixels, exit
//   covenant --no-validation skip the Khronos validation layer
//
// Loop (PLAN §23): simulation advances in fixed 60 Hz ticks (engine/core/fixed_timestep),
// rendering runs once per displayed frame with state interpolated by alpha.
#include "engine/core/clock.hpp"
#include "engine/core/fixed_timestep.hpp"
#include "engine/render/vk_renderer.hpp"
#include "game/core/spin_demo.hpp"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <cstring>

namespace {
constexpr uint32_t kTickHz = 60;
}

int main(int argc, char** argv) {
    bool headless = false, validation = true;
    double seconds = 0.0;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--headless")) headless = true;
        else if (!std::strcmp(argv[i], "--no-validation")) validation = false;
        else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = std::atof(argv[++i]);
    }
    std::puts("Covenant of Embers v0.0.2");

    coe::RendererConfig cfg;
    cfg.wantValidation = validation;
    SDL_Window* window = nullptr;
    if (!headless) {
        if (!SDL_Init(SDL_INIT_VIDEO)) { std::fprintf(stderr, "[sdl] %s\n", SDL_GetError()); return 1; }
        window = SDL_CreateWindow("Covenant of Embers", 1280, 720, SDL_WINDOW_VULKAN | SDL_WINDOW_RESIZABLE);
        if (!window) { std::fprintf(stderr, "[sdl] %s\n", SDL_GetError()); SDL_Quit(); return 1; }
        cfg.window = window;
    }

    coe::VkRenderer renderer;
    bool ok = renderer.init(cfg);
    if (ok) std::printf("GPU: %s | validation: %s\n", renderer.deviceName().c_str(),
                        renderer.validationEnabled() ? "on" : "off (layer not installed or disabled)");

    bool ticksOk = true;
    if (ok && headless) {
        ok = renderer.renderHeadlessAndVerify();
    } else if (ok) {
        coe::FixedTimestep step(kTickHz);
        coe::game::SpinDemo sim;
        uint64_t frames = 0;
        const uint64_t start = coe::monotonicNs();
        const uint64_t limitNs = seconds > 0 ? uint64_t(seconds * 1e9) : 0;
        uint64_t last = start;
        bool running = true;
        while (running && ok) {
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) running = false;
                if (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE) running = false;
                if (e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) renderer.onResize();
            }
            const uint64_t now = coe::monotonicNs();
            for (uint32_t n = step.advance(now - last); n > 0; --n) sim.tick(step.dtSeconds());
            last = now;
            if (limitNs && now - start >= limitNs) running = false;
            if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) { SDL_Delay(16); continue; }
            ok = renderer.drawFrame({sim.renderAngle(step.alpha())});
            ++frames;
        }
        const double elapsed = double(last - start) / 1e9;
        // Every ns of frame time was fed to the accumulator, so the tick count is exact.
        const uint64_t expected = (last - start - step.droppedNs()) * kTickHz / coe::FixedTimestep::kNsPerSecond;
        ticksOk = step.totalTicks() == expected;
        std::printf("frames: %llu in %.2fs (%.0f fps)\n", (unsigned long long)frames, elapsed,
                    elapsed > 0 ? double(frames) / elapsed : 0.0);
        std::printf("fixed ticks: %llu @ %u Hz (expected %llu, %.3fs dropped by hitch clamp)%s\n",
                    (unsigned long long)step.totalTicks(), kTickHz, (unsigned long long)expected,
                    double(step.droppedNs()) / 1e9, ticksOk ? "" : " MISMATCH");
    }
    renderer.shutdown();
    auto s = renderer.stats();
    std::printf("validation messages: %u errors, %u warnings\n", s.errors, s.warnings);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    bool pass = ok && ticksOk && s.errors == 0;
    std::puts(pass ? "RESULT: PASS" : "RESULT: FAIL");
    return pass ? 0 : 1;
}
