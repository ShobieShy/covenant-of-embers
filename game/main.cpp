// Covenant of Embers - game entry point: window + Vulkan cube (camera + depth) on a fixed-timestep loop.
// SPDX-License-Identifier: Apache-2.0
//   covenant                 run until the window is closed
//   covenant --seconds N     auto-quit after N seconds (smoke test; checks the tick count)
//   covenant --headless      render offscreen once, verify colour + depth, exit
//   covenant --no-validation skip the Khronos validation layer
//   covenant --input-debug   print action press/release edges per fixed tick + mouse look
//   covenant --input-script  push a scripted sequence of synthetic SDL input events and
//                            fail unless every scripted press reached exactly one tick
//
// Loop (PLAN §23): simulation advances in fixed 60 Hz ticks (engine/core/fixed_timestep),
// rendering runs once per displayed frame with state interpolated by alpha.
// Input (engine/input): SDL events are sampled per render frame; actions are
// consumed per fixed tick (latched edges), mouse look is applied per frame.
#include "engine/core/clock.hpp"
#include "engine/core/fixed_timestep.hpp"
#include "engine/input/input.hpp"
#include "engine/render/vk_renderer.hpp"
#include "game/core/cube_demo.hpp"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <cstring>
#include <string>

namespace {
constexpr uint32_t kTickHz = 60;
// Mouse look: 0.25 degrees per mouse count, Magewar's default MOUSE_SENS (cogito_player.gd).
// Sensitivity/invert-Y become settings in step 39.
constexpr double kLookRadPerCount = 0.25 * 3.141592653589793 / 180.0;

// --input-script: synthetic events pushed through SDL's real queue at given render
// frames. Taps land inside one frame (down+up), so whether that frame runs 0, 1 or
// 2+ ticks, each must reach exactly one tick as a press.
struct ScriptedEvent { uint64_t frame; SDL_EventType type; uint32_t code; float dx; };
constexpr ScriptedEvent kInputScript[] = {
    {5,  SDL_EVENT_KEY_DOWN, SDL_SCANCODE_SPACE, 0}, {5, SDL_EVENT_KEY_UP, SDL_SCANCODE_SPACE, 0},
    {8,  SDL_EVENT_KEY_DOWN, SDL_SCANCODE_W, 0},
    {10, SDL_EVENT_MOUSE_MOTION, 0, 40.0f},
    {12, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_LEFT, 0},
    {14, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_2, 0}, {14, SDL_EVENT_KEY_UP, SDL_SCANCODE_2, 0},
    {14, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_R, 0}, {14, SDL_EVENT_KEY_UP, SDL_SCANCODE_R, 0},
    {20, SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_LEFT, 0},
    {21, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_SPACE, 0}, {22, SDL_EVENT_KEY_UP, SDL_SCANCODE_SPACE, 0},
    {30, SDL_EVENT_KEY_UP, SDL_SCANCODE_W, 0},
};
constexpr struct { coe::input::Action action; uint64_t presses; } kScriptExpect[] = {
    {coe::input::Action::Jump, 2}, {coe::input::Action::MoveForward, 1},
    {coe::input::Action::Fire, 1}, {coe::input::Action::Weapon2, 1},
    {coe::input::Action::Reload, 1},
};

void pushScripted(uint64_t frame, SDL_Window* window) {
    for (const ScriptedEvent& s : kInputScript) {
        if (s.frame != frame) continue;
        SDL_Event e;
        SDL_zero(e);
        e.type = s.type;
        if (s.type == SDL_EVENT_KEY_DOWN || s.type == SDL_EVENT_KEY_UP) {
            e.key.windowID = SDL_GetWindowID(window);
            e.key.scancode = static_cast<SDL_Scancode>(s.code);
            e.key.down = s.type == SDL_EVENT_KEY_DOWN;
        } else if (s.type == SDL_EVENT_MOUSE_MOTION) {
            e.motion.windowID = SDL_GetWindowID(window);
            e.motion.xrel = s.dx;
        } else {
            e.button.windowID = SDL_GetWindowID(window);
            e.button.button = static_cast<uint8_t>(s.code);
            e.button.down = s.type == SDL_EVENT_MOUSE_BUTTON_DOWN;
        }
        SDL_PushEvent(&e);
    }
}

void printTick(uint64_t tick, const coe::input::TickInput& t) {
    if (t.pressed.none() && t.released.none()) return;
    std::string line;
    for (size_t a = 0; a < coe::input::kActionCount; ++a) {
        const char* n = coe::input::actionName(static_cast<coe::input::Action>(a));
        if (t.pressed[a]) line += std::string(" +") + n + (t.pressCount[a] > 1 ? "x" + std::to_string(t.pressCount[a]) : "");
        if (t.released[a]) line += std::string(" -") + n;
    }
    std::string held;
    for (size_t a = 0; a < coe::input::kActionCount; ++a)
        if (t.held[a]) held += std::string(held.empty() ? "" : ",") + coe::input::actionName(static_cast<coe::input::Action>(a));
    std::printf("[input] tick %llu:%s | held {%s}\n", (unsigned long long)tick, line.c_str(), held.c_str());
}
}

int main(int argc, char** argv) {
    bool headless = false, validation = true, inputDebug = false, inputScript = false;
    double seconds = 0.0;
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--headless")) headless = true;
        else if (!std::strcmp(argv[i], "--no-validation")) validation = false;
        else if (!std::strcmp(argv[i], "--input-debug")) inputDebug = true;
        else if (!std::strcmp(argv[i], "--input-script")) inputScript = true;
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

    bool ticksOk = true, inputOk = true;
    if (ok && headless) {
        // The tick-0 pose of the live demo, seen from the default camera.
        coe::FrameParams fp;
        fp.model = coe::game::CubeDemo{}.renderModel(0.0);
        ok = renderer.renderHeadlessAndVerify(fp);
    } else if (ok) {
        coe::FixedTimestep step(kTickHz);
        coe::game::CubeDemo sim;
        coe::input::InputState input;
        uint64_t presses[coe::input::kActionCount] = {};
        double lookYaw = 0.0, lookPitch = 0.0, lookCounts = 0.0;   // per-frame mouse look
        // Relative mode: hidden cursor, unbounded motion deltas. Not fatal if the
        // compositor refuses (e.g. window not focused yet).
        if (!SDL_SetWindowRelativeMouseMode(window, true))
            std::fprintf(stderr, "[input] relative mouse mode unavailable: %s\n", SDL_GetError());
        uint64_t frames = 0, loops = 0;   // loops also counts minimized iterations
        const uint64_t start = coe::monotonicNs();
        const uint64_t limitNs = seconds > 0 ? uint64_t(seconds * 1e9) : 0;
        uint64_t last = start;
        bool running = true;
        while (running && ok) {
            if (inputScript) pushScripted(loops, window);
            ++loops;
            SDL_Event e;
            while (SDL_PollEvent(&e)) {
                if (e.type == SDL_EVENT_QUIT || e.type == SDL_EVENT_WINDOW_CLOSE_REQUESTED) running = false;
                if (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE) running = false;
                if (e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) renderer.onResize();
                input.handleEvent(e);
            }
            const uint64_t now = coe::monotonicNs();
            for (uint32_t n = step.advance(now - last); n > 0; --n) {
                const coe::input::TickInput in = input.consumeTick();
                for (size_t a = 0; a < coe::input::kActionCount; ++a) presses[a] += in.pressCount[a];
                if (inputDebug) printTick(step.totalTicks() - n + 1, in);
                sim.tick(step.dtSeconds());
            }
            last = now;
            // Mouse look per render frame (not per tick) for minimum latency; it turns
            // the camera in place (step 14's FPS controller adds movement + eye height).
            const coe::input::LookDelta look = input.takeLook();
            lookCounts += look.dx;
            lookYaw = std::remainder(lookYaw - look.dx * kLookRadPerCount, 2.0 * 3.141592653589793);
            lookPitch = std::clamp(lookPitch - look.dy * kLookRadPerCount,
                                   -double(coe::Camera::kMaxPitch), double(coe::Camera::kMaxPitch));   // +-89 deg
            if (inputDebug && (look.dx != 0.0f || look.dy != 0.0f))
                std::printf("[input] frame %llu: look dx %.1f dy %.1f -> yaw %.3f pitch %.3f rad\n",
                            (unsigned long long)frames, double(look.dx), double(look.dy), lookYaw, lookPitch);
            if (limitNs && now - start >= limitNs) running = false;
            if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) { SDL_Delay(16); continue; }
            coe::FrameParams fp;
            fp.camera.yaw = float(lookYaw);       // mouse right -> negative yaw -> turn right
            fp.camera.pitch = float(lookPitch);
            fp.model = sim.renderModel(step.alpha());
            ok = renderer.drawFrame(fp);
            ++frames;
        }
        // Edges still latched when the loop stopped never reached a tick.
        const coe::input::TickInput tail = input.consumeTick();
        if (inputScript) {
            for (const auto& x : kScriptExpect) {
                const size_t a = static_cast<size_t>(x.action);
                const bool good = presses[a] + tail.pressCount[a] == x.presses && tail.pressCount[a] == 0;
                inputOk = inputOk && good;
                std::printf("[input] script %s: %llu press(es) seen by ticks (expected %llu)%s\n",
                            coe::input::actionName(x.action), (unsigned long long)presses[a],
                            (unsigned long long)x.presses, good ? "" : " MISMATCH");
            }
            if (loops <= kInputScript[std::size(kInputScript) - 1].frame) {
                std::printf("[input] script needs more frames (ran %llu)\n", (unsigned long long)loops);
                inputOk = false;
            }
            std::printf("[input] mouse look total dx %.1f counts (scripted 40)\n", lookCounts);
        }
        SDL_SetWindowRelativeMouseMode(window, false);
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
    bool pass = ok && ticksOk && inputOk && s.errors == 0;
    std::puts(pass ? "RESULT: PASS" : "RESULT: FAIL");
    return pass ? 0 : 1;
}
