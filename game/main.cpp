// Covenant of Embers - game entry point: window + Vulkan greybox level (or a glTF model) on a fixed-timestep loop.
// SPDX-License-Identifier: Apache-2.0
//   covenant                 run until the window is closed (the Midden greybox level)
//   covenant --seconds N     auto-quit after N seconds (smoke test; checks the tick count)
//   covenant --headless      render offscreen once, verify the resolved colour + depth, exit
//                            (level: floor + walls visible and on the data's boxes -> midden.ppm;
//                            --model: step 11's model check -> mesh.ppm)
//   covenant --level FILE    level TOML (default: data/levels/midden_greybox.toml)
//   covenant --model [SRC]   show one model instead of the level, by source path in the
//                            cooked manifest (default: the Kenney blaster-a GLB)
//   covenant --cooked DIR    cooked asset dir (default: build/<preset>/cooked, made by `cook`)
//   covenant --no-validation skip the Khronos validation layer
//   covenant --input-debug   print action press/release edges per fixed tick + mouse look
//   covenant --input-script  push a scripted sequence of synthetic SDL input events and
//                            fail unless every scripted press reached exactly one tick
//
// Loop (PLAN §23): simulation advances in fixed 60 Hz ticks (engine/core/fixed_timestep),
// rendering runs once per displayed frame with state interpolated by alpha.
// Input (engine/input): SDL events are sampled per render frame; actions are
// consumed per fixed tick (latched edges), mouse look is applied per frame.
// Assets (step 11): the model is resolved through the cooker's manifest (size + hash
// checked), loaded with fastgltf (engine/assets) and uploaded once (VMA buffers).
// Level (step 12): boxes from TOML (game/world/level), one shared unit cube, one draw each.
#include "engine/core/clock.hpp"
#include "engine/core/fixed_timestep.hpp"
#include "engine/input/input.hpp"
#include "engine/render/vk_renderer.hpp"
#include "engine/assets/gltf_loader.hpp"
#include "engine/assets/manifest.hpp"
#include "game/core/tumble_demo.hpp"
#include "game/world/headless_checks.hpp"
#include "game/world/level.hpp"

#include <SDL3/SDL.h>
#include <SDL3/SDL_vulkan.h>
#include <cstdint>
#include <cstdio>
#include <cstdlib>
#include <algorithm>
#include <cmath>
#include <iterator>
#include <cstring>
#include <filesystem>
#include <string>

#include <glm/gtc/matrix_transform.hpp>

#ifndef COE_COOKED_DIR
#define COE_COOKED_DIR "cooked"
#endif
#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
constexpr uint32_t kTickHz = 60;
// Mouse look: 0.25 degrees per mouse count, Magewar's default MOUSE_SENS (cogito_player.gd).
// Sensitivity/invert-Y become settings in step 39.
constexpr double kLookRadPerCount = 0.25 * 3.141592653589793 / 180.0;
constexpr const char* kDefaultModel = "assets/kenney/blaster-kit/Models/GLB format/blaster-a.glb";

// Demo framing: centre the model on its bounds, scale its longest side to 1 m (the
// step-10 cube's size) and turn it side-on (glTF +Z forward -> profile to the camera).
// The in-hand viewmodel transform is step 21's job.
glm::mat4 fitModel(const coe::assets::MeshData& m) {
    const glm::vec3 e = m.extent();
    const float longest = std::max({e.x, e.y, e.z, 1e-6f});
    glm::mat4 t = glm::rotate(glm::mat4(1.0f), glm::radians(90.0f), glm::vec3(0, 1, 0));
    t = glm::scale(t, glm::vec3(1.0f / longest));
    return glm::translate(t, -m.center());
}

// The level as the renderer sees it: start camera, sun/ambient/fog, sky as clear colour.
coe::FrameParams levelFrame(const coe::game::Level& level, coe::MeshId cube) {
    coe::FrameParams fp;
    fp.camera.position = level.camera.position;
    fp.camera.yaw = glm::radians(level.camera.yawDeg);
    fp.camera.pitch = glm::radians(level.camera.pitchDeg);
    const coe::game::LevelEnvironment& env = level.environment;
    fp.lighting.toLight = env.toLight;
    fp.lighting.lightColor = env.sunColor;
    fp.lighting.ambient = env.ambientColor;
    fp.lighting.fogColor = env.skyColor;   // fog fades into the sky
    fp.lighting.fogDensity = env.fogDensity;
    fp.clearColor = env.skyColor;
    for (const coe::game::LevelBox& b : level.boxes) fp.draws.push_back({cube, b.model(), b.color});
    return fp;
}

bool loadLevelFile(const std::string& path, coe::game::Level& level) {
    const std::string err = coe::game::loadLevel(path, level);
    if (!err.empty()) { std::fprintf(stderr, "[level] %s\n", err.c_str()); return false; }
    std::string kinds;
    for (size_t k = 0; k < coe::game::kBoxKindCount; ++k)
        if (const size_t n = level.count(coe::game::BoxKind(k)))
            kinds += std::string(kinds.empty() ? "" : ", ") + std::to_string(n) + " " + coe::game::boxKindName(coe::game::BoxKind(k));
    std::printf("[level] %s '%s': %zu boxes (%s)\n", level.id.c_str(), level.name.c_str(), level.boxes.size(), kinds.c_str());
    return true;
}

bool loadModel(const std::string& cookedDir, const std::string& source, coe::assets::MeshData& mesh) {
    coe::assets::CookedManifest manifest;
    std::string err = manifest.load(cookedDir);
    std::filesystem::path path;
    if (err.empty()) err = manifest.resolve(source, path);
    if (err.empty()) err = coe::assets::loadGltfMesh(path, mesh);
    if (!err.empty()) { std::fprintf(stderr, "[assets] %s\n", err.c_str()); return false; }
    const glm::vec3 e = mesh.extent();
    std::printf("[mesh] %s: %zu triangles, %zu vertices, %zu submesh(es), size %.3f x %.3f x %.3f m\n",
                source.c_str(), mesh.triangleCount(), mesh.vertices.size(), mesh.submeshes.size(),
                double(e.x), double(e.y), double(e.z));
    return true;
}

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
    bool modelView = false;   // --model: step 11's single-model view instead of the level
    std::string model = kDefaultModel, cookedDir = COE_COOKED_DIR;
    std::string levelPath = std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml";
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--headless")) headless = true;
        else if (!std::strcmp(argv[i], "--no-validation")) validation = false;
        else if (!std::strcmp(argv[i], "--input-debug")) inputDebug = true;
        else if (!std::strcmp(argv[i], "--input-script")) inputScript = true;
        else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = std::atof(argv[++i]);
        else if (!std::strcmp(argv[i], "--model")) {
            modelView = true;
            if (i + 1 < argc && std::strncmp(argv[i + 1], "--", 2) != 0) model = argv[++i];
        }
        else if (!std::strcmp(argv[i], "--level") && i + 1 < argc) levelPath = argv[++i];
        else if (!std::strcmp(argv[i], "--cooked") && i + 1 < argc) cookedDir = argv[++i];
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

    coe::assets::MeshData mesh;
    coe::game::Level level;
    bool ok = modelView ? loadModel(cookedDir, model, mesh) : loadLevelFile(levelPath, level);
    if (ok && !modelView) mesh = coe::game::makeUnitCube();   // uploaded once, drawn per box
    coe::VkRenderer renderer;
    ok = ok && renderer.init(cfg);
    if (ok) std::printf("GPU: %s | validation: %s\n", renderer.deviceName().c_str(),
                        renderer.validationEnabled() ? "on" : "off (layer not installed or disabled)");
    coe::MeshId meshId = coe::kInvalidMesh;
    if (ok) ok = (meshId = renderer.uploadMesh(mesh)) != coe::kInvalidMesh;
    const glm::mat4 fit = ok && modelView ? fitModel(mesh) : glm::mat4(1.0f);
    // Level mode: every box is a draw of the one cube; the frame only changes by camera.
    const coe::FrameParams levelBase = ok && !modelView ? levelFrame(level, meshId) : coe::FrameParams{};

    bool ticksOk = true, inputOk = true;
    if (ok && headless) {
        coe::FrameParams fp = levelBase;
        if (modelView)   // the tick-0 pose of the live demo, seen from the default camera
            fp.draws.push_back({meshId, coe::game::TumbleDemo{}.renderModel(0.0) * fit});
        coe::HeadlessFrame frame;
        ok = renderer.renderHeadless(fp, frame);
        if (ok) {
            std::string report;
            if (modelView) {
                ok = coe::game::checkModelView(frame, fp.draws.front().model, fp.clearColor, report);
            } else {
                coe::game::LevelViewStats stats;
                ok = coe::game::checkLevelView(level, frame, fp.camera.position, fp.clearColor, stats, report);
            }
            std::puts(report.c_str());
            // Artefact for humans: build/<preset>/midden.ppm or mesh.ppm
            const char* ppm = modelView ? "mesh.ppm" : "midden.ppm";
            if (!coe::game::writePpm(ppm, frame)) std::fprintf(stderr, "[headless] could not write %s\n", ppm);
        }
    } else if (ok) {
        coe::FixedTimestep step(kTickHz);
        coe::game::TumbleDemo sim;
        coe::input::InputState input;
        uint64_t presses[coe::input::kActionCount] = {};
        double lookYaw = levelBase.camera.yaw, lookPitch = levelBase.camera.pitch, lookCounts = 0.0;   // per-frame mouse look
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
            coe::FrameParams fp = levelBase;
            fp.camera.yaw = float(lookYaw);       // mouse right -> negative yaw -> turn right
            fp.camera.pitch = float(lookPitch);
            if (modelView) fp.draws.push_back({meshId, sim.renderModel(step.alpha()) * fit});
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
