// Covenant of Embers - M0 entry point: window + Vulkan triangle.
// SPDX-License-Identifier: Apache-2.0
//   covenant                 run until the window is closed
//   covenant --seconds N     auto-quit after N seconds (smoke test)
//   covenant --headless      render offscreen once, verify pixels, exit
//   covenant --no-validation skip the Khronos validation layer
#include "render/vk_renderer.hpp"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <cstdio>
#include <cstdlib>
#include <cstring>

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

    uint64_t frames = 0;
    if (ok && headless) {
        ok = renderer.renderHeadlessAndVerify();
        frames = 1;
    } else if (ok) {
        const Uint64 start = SDL_GetTicks();
        bool running = true;
        while (running && ok) {
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) running = false;
                if (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE) running = false;
                if (e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) renderer.onResize();
            }
            if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) { SDL_Delay(16); continue; }
            ok = renderer.drawFrame();
            ++frames;
            if (seconds > 0 && (SDL_GetTicks() - start) >= Uint64(seconds * 1000.0)) running = false;
        }
        double elapsed = (SDL_GetTicks() - start) / 1000.0;
        std::printf("frames: %llu in %.2fs (%.0f fps)\n", (unsigned long long)frames, elapsed,
                    elapsed > 0 ? frames / elapsed : 0.0);
    }
    renderer.shutdown();
    auto s = renderer.stats();
    std::printf("validation messages: %u errors, %u warnings\n", s.errors, s.warnings);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    bool pass = ok && s.errors == 0;
    std::puts(pass ? "RESULT: PASS" : "RESULT: FAIL");
    return pass ? 0 : 1;
}
