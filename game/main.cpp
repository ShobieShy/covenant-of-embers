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
//                            (level mode: and the player walked forward, jumped, dashed
//                            and cast exactly one bolt that did not fizzle, paying its
//                            mana cost exactly once)
//   covenant --crate         level mode: also drop step 13's tumbling demo crate (a push target)
//   covenant --reduced-motion  level mode: no head bob / landing dip (accessibility)
//   covenant --wieldables FILE  staff/wand bases (default: data/magic/wieldables.toml)
//   covenant --staff ID / --wand ID  what the Staff / Wand slot holds (default: the first
//                            staff / wand in wieldables.toml)
//   covenant --enemies FILE  enemy types for the level's [[enemy]] placements
//                            (default: data/enemies/training_dummies.toml)
//
// Loop (PLAN §23): simulation advances in fixed 60 Hz ticks (engine/core/fixed_timestep),
// rendering runs once per displayed frame with state interpolated by alpha.
// Input (engine/input): SDL events are sampled per render frame; actions are
// consumed per fixed tick (latched edges), mouse look is applied per frame.
// Assets (step 11): the model is resolved through the cooker's manifest (size + hash
// checked), loaded with fastgltf (engine/assets) and uploaded once (VMA buffers).
// Level (step 12): boxes from TOML (game/world/level), one shared unit cube, one draw each.
// Physics (step 13): every level box is a static Jolt collider (game/world/level_physics);
// the world steps once per fixed tick. With --crate a tumbling demo crate (dynamic box)
// is dropped in front of the player and drawn interpolated.
// Player (step 14): game/player/player_controller spawns a Jolt CharacterVirtual at the
// level's [player_start]; each tick it walks/jumps/crouches, and (step 15) sprints on
// Breath and slides, (step 16) dashes, from the TickInput (before the world steps), mouse
// look turns it per frame, the camera sits at its eye (+ head bob / landing dip).
// Casting (step 17): Magewar staffs/wands from data/magic/wieldables.toml (game/magic);
// Fire casts a bolt from the eye along the view (after the world steps) on the
// wieldable's cooldown; bolts are ray-swept per tick skipping the player's own capsule
// and drawn as element-coloured debug lines.
// Loadout + viewmodel (step 21, game/magic/loadout, game/render/viewmodel): a Staff slot
// (Weapon1) and a Wand slot (Weapon2); a swap takes 0.4 s and blocks Fire/Aim; each slot
// keeps its own cooldown. The held one is drawn as a greybox staff/wand in the
// renderer's viewmodel pass, its head tinted by the element colour; tracers start at its
// CastPoint. Window runs read back frame 4 and check the head is there in that colour;
// --headless checks it on a second render.
// Mana (step 18): game/player/mana on the PlayerController (Magewar ManaAttribute: 100,
// 3/s after 1.5 s); each cast spends the wieldable's mana cost through
// Caster::setManaSpender, a refused cast costs no cooldown. No ammo, no reload: the Reload
// action (R) is still mapped but drives nothing.
// Enemies + damage numbers (step 22, game/enemies/enemy, game/ui/damage_numbers): the
// level's [[enemy]] placements (training dummies) spawn as kinematic hitboxes on the
// Enemy physics layer; bolt hits on them run the step-20 damage formula, lower health,
// kill at 0 and float an element-coloured number drawn by the ImGui overlay
// (engine/ui/imgui_layer, coe_ui). --headless casts the held staff at the first dummy
// until it dies: the first hit must deal the formula value and show its number in the
// element colour (dmgframe.ppm), the dummy must die at exactly 0.
#include "engine/core/clock.hpp"
#include "engine/core/fixed_timestep.hpp"
#include "engine/input/input.hpp"
#include "engine/render/vk_renderer.hpp"
#include "engine/assets/gltf_loader.hpp"
#include "engine/assets/manifest.hpp"
#include "engine/physics/physics.hpp"
#include "engine/ui/imgui_layer.hpp"
#include "game/combat/element.hpp"
#include "game/enemies/enemy.hpp"
#include "game/core/tumble_demo.hpp"
#include "game/magic/accuracy.hpp"
#include "game/magic/casting.hpp"
#include "game/magic/loadout.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"
#include "game/player/player_controller.hpp"
#include "game/render/viewmodel.hpp"
#include "game/ui/damage_numbers.hpp"
#include "game/world/headless_checks.hpp"
#include "game/world/level.hpp"
#include "game/world/level_physics.hpp"

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
#include <memory>
#include <string>
#include <vector>

#include <glm/gtc/matrix_transform.hpp>
#include <glm/gtc/quaternion.hpp>

#ifndef COE_COOKED_DIR
#define COE_COOKED_DIR "cooked"
#endif
#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
constexpr uint32_t kTickHz = 60;
// Mouse look: 0.25 degrees per mouse count, Magewar's default MOUSE_SENS (cogito_player.gd).
// Sensitivity/invert-Y become settings in step 39. Level mode uses PlayerTuning's copy;
// this one turns the --model view.
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

// The level as the renderer sees it: the player's start view (eye above [player_start],
// level pitch), sun/ambient/fog, sky as clear colour.
coe::FrameParams levelFrame(const coe::game::Level& level, coe::MeshId cube) {
    coe::FrameParams fp;
    fp.camera.position = level.playerStart.position + glm::vec3(0.0f, coe::game::PlayerTuning{}.standingEye, 0.0f);
    fp.camera.yaw = glm::radians(level.playerStart.yawDeg);
    fp.camera.pitch = 0.0f;
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

// Demo crate (step 13, --crate): 0.6 m, dropped tilted 2.8 m up, 4.5 m in front of the player start.
constexpr float kDemoCrateEdge = 0.6f;
constexpr glm::vec4 kDemoCrateTint{0.85f, 0.35f, 0.1f, 1.0f};   // ember orange
coe::physics::BoxDesc demoCrate(const coe::game::Level& level) {
    coe::physics::BoxDesc d;
    d.center = level.playerStart.position + glm::vec3(0.8f, 2.8f, -4.5f);
    d.halfExtents = glm::vec3(kDemoCrateEdge * 0.5f);
    d.rotation = glm::angleAxis(0.6f, glm::normalize(glm::vec3(1.0f, 0.3f, 0.7f)));
    return d;
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

bool loadElementsFile(const std::string& path, coe::game::ElementTable& table) {
    const std::string err = coe::game::loadElements(path, table);
    if (!err.empty()) { std::fprintf(stderr, "[magic] %s\n", err.c_str()); return false; }
    std::string names;
    for (coe::game::Element e : coe::game::kAllElements) names += std::string(names.empty() ? "" : ", ") + table.name(e);
    std::printf("[magic] %zu elements (strong x%.2f, weak x%.2f): %s\n", coe::game::kElementCount,
                double(table.strong), double(table.weak), names.c_str());
    return true;
}

bool loadWieldablesFile(const std::string& path, coe::game::WieldableTable& table) {
    const std::string err = coe::game::loadWieldables(path, table);
    if (!err.empty()) { std::fprintf(stderr, "[magic] %s\n", err.c_str()); return false; }
    std::string names;
    for (const coe::game::WieldableDef& d : table.defs)
        names += std::string(names.empty() ? "" : ", ") + d.name + " (" + coe::game::wieldableTypeName(d.type) + ", " +
                 coe::game::elementName(d.element) + ")";
    std::printf("[magic] %zu wieldables: %s\n", table.defs.size(), names.c_str());
    return true;
}

// Step 21: one instance per base (no parts until step 28); the Staff slot gets `staffId`
// (default: the first staff), the Wand slot `wandId` (default: the first wand). `hands`
// must not grow afterwards (the loadout points into it).
bool buildLoadout(const coe::game::WieldableTable& table, const std::string& staffId, const std::string& wandId,
                  std::vector<coe::game::WieldableInstance>& hands, coe::game::Loadout& loadout) {
    hands.clear();
    for (const coe::game::WieldableDef& d : table.defs) hands.emplace_back(d);
    const auto pick = [&](coe::game::Slot slot, const std::string& id) {
        for (const coe::game::WieldableInstance& w : hands)
            if (coe::game::slotFor(w.type()) == slot && (id.empty() || w.def->id == id)) return &w;
        return static_cast<const coe::game::WieldableInstance*>(nullptr);
    };
    bool ok = true;
    for (const auto& [slot, id] : {std::pair{coe::game::Slot::Staff, staffId}, std::pair{coe::game::Slot::Wand, wandId}}) {
        const coe::game::WieldableInstance* w = pick(slot, id);
        if (!w && !id.empty()) {
            std::fprintf(stderr, "[loadout] no %s with id '%s' in the wieldables\n", coe::game::slotName(slot), id.c_str());
            ok = false;
        }
        loadout.equip(slot, w);
    }
    if (!loadout.wieldable()) loadout.select(coe::game::Slot::Wand, /*instant=*/true);   // spawn holding something
    return ok;
}

// Viewmodel draws for what the loadout shows (focus 0..1 = Focus::amount()); returns the
// head's view-space position (z = 0 if nothing is shown).
glm::vec3 addViewmodel(const coe::game::Loadout& loadout, const coe::game::ViewmodelMeshes& meshes,
                       const coe::game::ElementTable& elements, float focus, std::vector<coe::DrawItem>& out) {
    const coe::game::ViewmodelShown shown = coe::game::viewmodelShown(loadout);
    if (!shown.wieldable || meshes.shaft == coe::kInvalidMesh) return glm::vec3(0.0f);
    const glm::mat4 t = coe::game::viewmodelTransform(shown.wieldable->type(), focus, shown.lowered);
    coe::game::appendViewmodelDraws(meshes, shown.wieldable->type(), t, elements.color(shown.wieldable->element()), out);
    return coe::game::viewmodelCastPoint(shown.wieldable->type(), t);
}

bool loadEnemiesFile(const std::string& path, coe::game::EnemyTable& table) {
    const std::string err = coe::game::loadEnemies(path, table);
    if (!err.empty()) { std::fprintf(stderr, "[enemy] %s\n", err.c_str()); return false; }
    std::string names;
    for (const coe::game::EnemyDef& d : table.defs)
        names += std::string(names.empty() ? "" : ", ") + d.name + " (" + coe::game::elementName(d.affinity) + ", " +
                 std::to_string(int(d.maxHealth)) + " HP" + (d.weakPoint ? ", weak point" : "") + ")";
    std::printf("[enemy] %zu enemy types: %s\n", table.defs.size(), names.c_str());
    return true;
}

// Spawns the level's [[enemy]] placements; an id missing from the table is an error.
bool spawnLevelEnemies(const coe::game::Level& level, const coe::game::EnemyTable& table, coe::game::EnemySystem& out) {
    bool ok = true;
    for (size_t i = 0; i < level.enemies.size(); ++i) {
        const coe::game::LevelEnemy& le = level.enemies[i];
        const coe::game::EnemyDef* def = table.find(le.enemy);
        if (!def) {
            std::fprintf(stderr, "[enemy] level '%s' enemy #%zu: unknown enemy '%s'\n", level.id.c_str(), i + 1,
                         le.enemy.c_str());
            ok = false;
            continue;
        }
        out.spawn(*def, le.position, le.yawDeg);
        std::printf("[enemy] spawned %s at (%.2f, %.2f, %.2f), %.0f HP, %s\n", def->name.c_str(), double(le.position.x),
                    double(le.position.y), double(le.position.z), double(def->maxHealth), coe::game::elementName(def->affinity));
    }
    return ok;
}

void printEnemyHit(const coe::game::EnemySystem& enemies, const coe::game::EnemyHit& h, const coe::game::ProjectileHit& bolt,
                   const coe::game::ElementTable& elements) {
    const coe::game::Enemy* e = enemies.find(h.enemy);
    const coe::game::DamageResult& r = h.result;
    std::printf("[enemy] %s hit %s (%s)%s%s: %.1f %s x%.2f%s%s = %.1f dmg, health %.1f -> %.1f%s\n",
                elements.name(h.element).c_str(), e ? e->def->name.c_str() : "?",
                e ? coe::game::elementName(e->def->affinity) : "?", h.weakPoint ? " in the weak point" : "",
                bolt.grazed ? " (grazed)" : "", double(bolt.damage), coe::game::elementName(h.element), double(r.effectiveness),
                r.resist > 0.0f ? (" -" + std::to_string(int(std::lround(r.resist * 100.0f))) + "% resist").c_str() : "",
                r.crit > 1.0f ? " x2 crit" : "", double(r.amount), double(h.healthBefore), double(h.healthAfter),
                h.killed ? ", KILLED" : "");
}

// Damage numbers -> ImGui text, centred on each label's pixel. Font size 22 px x scale.
void drawDamageLabels(coe::ImGuiLayer& ui, const coe::game::DamageNumbers& numbers, const glm::mat4& viewProj,
                      glm::vec2 viewport, std::vector<coe::game::DamageLabel>& scratch) {
    scratch.clear();
    numbers.labels(viewProj, viewport, scratch);
    for (const coe::game::DamageLabel& l : scratch) {
        const float size = 22.0f * l.scale;
        const glm::vec2 ext = ui.textSize(l.text, size);
        ui.drawText(l.screen - ext * 0.5f, l.text, l.color, l.alpha, size);
    }
}

// Step 22 headless done-check (see the header comment). Turns the start view toward the
// first dummy, casts the held wieldable at its chest until it dies, renders the first
// hit's number over the dummy and compares against the same frame without the overlay.
bool headlessDummyCheck(coe::VkRenderer& renderer, coe::ImGuiLayer& ui, const coe::FrameParams& base, coe::MeshId cube,
                        coe::physics::PhysicsWorld& physics, coe::game::EnemySystem& enemies,
                        const coe::game::ElementTable& elements, coe::game::Loadout& loadout) {
    const coe::game::Enemy* target = nullptr;
    for (const coe::game::Enemy& e : enemies.enemies())
        if (!e.dead) { target = &e; break; }
    const coe::game::WieldableInstance* held = loadout.wieldable();
    if (!target || !held) { std::puts("[enemy] headless check skipped: no enemy placed or nothing held"); return true; }
    const std::uint32_t id = target->id;
    const coe::game::EnemyDef& def = *target->def;
    const glm::vec3 eye = base.camera.position;
    const glm::vec3 chest = target->feet + glm::vec3(0.0f, def.size.y * 0.5f, 0.0f);
    const glm::vec3 dir = glm::normalize(chest - eye);
    const float expected = coe::game::resolveHit(held->damage(), held->element(), {def.affinity, def.resist, false}, elements).amount;
    const int hitsToKill = int(std::ceil(def.maxHealth / expected - 1e-4f));

    coe::FrameParams fp = base;
    fp.camera.yaw = std::atan2(-dir.x, -dir.z);
    fp.camera.pitch = std::asin(std::clamp(dir.y, -1.0f, 1.0f));
    coe::game::ProjectileSystem bolts;
    bolts.setElements(&elements);
    coe::game::DamageNumbers numbers;
    std::vector<coe::game::ProjectileHit> hits;
    std::vector<coe::game::DamageLabel> scratch;
    const float dt = 1.0f / float(kTickHz);
    const coe::game::CastAim aim{eye, dir, {}, {}};
    bool firstOk = false, labelOk = false, rendered = false, strayHit = false;
    int enemyHits = 0;
    float firstDealt = -1.0f;
    for (int tick = 0; tick < 20 * int(kTickHz) && !rendered; ++tick) {
        const bool alive = !enemies.find(id)->dead;
        if (alive) loadout.tick(true, true, dt, aim, bolts);
        hits.clear();
        bolts.tick(physics, dt, hits);
        for (const coe::game::ProjectileHit& h : hits) {
            const std::optional<coe::game::EnemyHit> eh = enemies.applyHit(h);
            if (!eh) { strayHit = strayHit || alive; continue; }   // after the kill bolts fly through to the wall
            printEnemyHit(enemies, *eh, h, elements);
            ++enemyHits;
            numbers.add(h.point, eh->result, h.element, elements);
            if (enemyHits != 1) continue;
            firstDealt = eh->healthBefore - eh->healthAfter;
            firstOk = eh->result.amount == expected && firstDealt == expected && !eh->weakPoint;
            // The number over the dummy: the scene with the overlay vs. without.
            coe::FrameParams sp = fp;
            enemies.draws(cube, sp.draws);
            const VkExtent2D ext = renderer.targetExtent();
            const glm::vec2 size{float(ext.width), float(ext.height)};
            ui.beginFrame(size, dt);
            drawDamageLabels(ui, numbers, sp.camera.viewProjection(size.x / size.y), size, scratch);
            ui.endFrame();
            coe::HeadlessFrame plain, withUi;
            if (!renderer.renderHeadless(sp, plain)) return false;
            sp.overlay = ui.recorder();
            if (!renderer.renderHeadless(sp, withUi)) return false;
            std::string report;
            labelOk = !scratch.empty() &&
                      coe::game::checkLabelPixels(withUi, plain, scratch.front().screen, 28.0f,
                                                  elements.color(h.element), 12, report);
            std::printf("%s, text \"%s\"%s\n", report.empty() ? "[damage] no label on screen MISMATCH" : report.c_str(),
                        scratch.empty() ? "" : scratch.front().text.c_str(), ui.framesRendered() ? "" : " (overlay never recorded)");
            if (!coe::game::writePpm("dmgframe.ppm", withUi)) std::fprintf(stderr, "[headless] could not write dmgframe.ppm\n");
        }
        numbers.tick(dt);
        enemies.tick(dt);
        // Done once dead and every bolt in flight has landed.
        if (enemies.find(id)->dead && bolts.live().empty()) rendered = true;
    }
    const coe::game::Enemy& e = *enemies.find(id);
    const std::vector<coe::game::EnemyDeath> deaths = enemies.takeDeaths();
    const bool died = e.dead && e.health == 0.0f && enemyHits == hitsToKill && deaths.size() == 1 &&
                      deaths.front().enemy == id && !e.body.valid() && !enemies.byBody(e.body);
    std::printf("[enemy] %s: %.1f %s vs %s = %.1f per hit (expect %.1f), %d hit(s) to kill (expect %d), health %.1f, %s%s\n",
                held->def->name.c_str(), double(held->damage()), coe::game::elementName(held->element()),
                coe::game::elementName(def.affinity), double(firstDealt), double(expected), enemyHits, hitsToKill,
                double(e.health), died ? "dead" : "ALIVE", firstOk && died && labelOk && !strayHit ? "" : " MISMATCH");
    return firstOk && labelOk && died && !strayHit;
}

// A debug line as the shared unit cube stretched along a -> b (step 17 bolt tracers).
constexpr float kDebugLineWidth = 0.04f;
glm::mat4 lineModel(const glm::vec3& a, const glm::vec3& b) {
    const glm::vec3 d = b - a;
    const float len = glm::length(d);
    const glm::vec3 z = len > 1e-6f ? d / len : glm::vec3(0, 0, 1);
    const glm::vec3 up = std::abs(z.y) < 0.99f ? glm::vec3(0, 1, 0) : glm::vec3(1, 0, 0);
    const glm::vec3 x = glm::normalize(glm::cross(up, z));
    const glm::vec3 y = glm::cross(z, x);
    glm::mat4 m(glm::vec4(x, 0), glm::vec4(y, 0), glm::vec4(z, 0), glm::vec4((a + b) * 0.5f, 1));
    return glm::scale(m, glm::vec3(kDebugLineWidth, kDebugLineWidth, len));
}

// --input-script: synthetic events pushed through SDL's real queue at given render
// frames. Taps land inside one frame (down+up), so whether that frame runs 0, 1 or
// 2+ ticks, each must reach exactly one tick as a press.
// Scripted events carry kScriptDevice as their device id; in script mode real
// keyboard/mouse events are dropped so a stray key press on the desktop (the window
// takes focus) can't change the outcome (seen once: a real S press walked it back).
constexpr uint32_t kScriptDevice = 0x434F4553u;   // 'COES'
bool isRealInput(const SDL_Event& e) {
    switch (e.type) {
    case SDL_EVENT_KEY_DOWN: case SDL_EVENT_KEY_UP: return e.key.which != kScriptDevice;
    case SDL_EVENT_MOUSE_MOTION: return e.motion.which != kScriptDevice;
    case SDL_EVENT_MOUSE_BUTTON_DOWN: case SDL_EVENT_MOUSE_BUTTON_UP: return e.button.which != kScriptDevice;
    case SDL_EVENT_MOUSE_WHEEL: case SDL_EVENT_TEXT_INPUT: return true;
    default: return false;
    }
}
struct ScriptedEvent { uint64_t frame; SDL_EventType type; uint32_t code; float dx; };
constexpr ScriptedEvent kInputScript[] = {
    {5,  SDL_EVENT_KEY_DOWN, SDL_SCANCODE_SPACE, 0}, {5, SDL_EVENT_KEY_UP, SDL_SCANCODE_SPACE, 0},
    {8,  SDL_EVENT_KEY_DOWN, SDL_SCANCODE_W, 0},
    {10, SDL_EVENT_MOUSE_MOTION, 0, 40.0f},
    {12, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_LEFT, 0},
    {14, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_R, 0}, {14, SDL_EVENT_KEY_UP, SDL_SCANCODE_R, 0},
    {20, SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_LEFT, 0},
    {21, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_SPACE, 0}, {22, SDL_EVENT_KEY_UP, SDL_SCANCODE_SPACE, 0},
    {30, SDL_EVENT_KEY_UP, SDL_SCANCODE_W, 0},
    {24, SDL_EVENT_MOUSE_BUTTON_DOWN, SDL_BUTTON_RIGHT, 0},   // focus (ADS) with the staff slot
    {40, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_Q, 0}, {41, SDL_EVENT_KEY_UP, SDL_SCANCODE_Q, 0},   // dash
    {50, SDL_EVENT_MOUSE_BUTTON_UP, SDL_BUTTON_RIGHT, 0},
    // Step 21: swap to the wand slot after the focus, so the 0.4 s swap (which blocks
    // Aim) can't eat the RMB hold on a fast display; it must finish within the run.
    {52, SDL_EVENT_KEY_DOWN, SDL_SCANCODE_2, 0}, {52, SDL_EVENT_KEY_UP, SDL_SCANCODE_2, 0},
};
constexpr struct { coe::input::Action action; uint64_t presses; } kScriptExpect[] = {
    {coe::input::Action::Jump, 2}, {coe::input::Action::MoveForward, 1},
    {coe::input::Action::Fire, 1}, {coe::input::Action::Weapon2, 1},
    {coe::input::Action::Reload, 1}, {coe::input::Action::Dash, 1},   // Reload: seen, does nothing (step 18)
    {coe::input::Action::Aim, 1},
};

void pushScripted(uint64_t frame, SDL_Window* window) {
    for (const ScriptedEvent& s : kInputScript) {
        if (s.frame != frame) continue;
        SDL_Event e;
        SDL_zero(e);
        e.type = s.type;
        if (s.type == SDL_EVENT_KEY_DOWN || s.type == SDL_EVENT_KEY_UP) {
            e.key.windowID = SDL_GetWindowID(window);
            e.key.which = kScriptDevice;
            e.key.scancode = static_cast<SDL_Scancode>(s.code);
            e.key.down = s.type == SDL_EVENT_KEY_DOWN;
        } else if (s.type == SDL_EVENT_MOUSE_MOTION) {
            e.motion.windowID = SDL_GetWindowID(window);
            e.motion.which = kScriptDevice;
            e.motion.xrel = s.dx;
        } else {
            e.button.windowID = SDL_GetWindowID(window);
            e.button.which = kScriptDevice;
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
    bool headless = false, validation = true, inputDebug = false, inputScript = false, withCrate = false,
         reducedMotion = false;
    double seconds = 0.0;
    bool modelView = false;   // --model: step 11's single-model view instead of the level
    std::string model = kDefaultModel, cookedDir = COE_COOKED_DIR;
    std::string levelPath = std::string(COE_DATA_DIR) + "/levels/midden_greybox.toml";
    std::string wieldablesPath = std::string(COE_DATA_DIR) + "/magic/wieldables.toml";
    std::string elementsPath = std::string(COE_DATA_DIR) + "/magic/elements.toml";
    std::string enemiesPath = std::string(COE_DATA_DIR) + "/enemies/training_dummies.toml";
    std::string staffId, wandId;   // step 21: empty = the first staff / wand
    for (int i = 1; i < argc; ++i) {
        if (!std::strcmp(argv[i], "--headless")) headless = true;
        else if (!std::strcmp(argv[i], "--no-validation")) validation = false;
        else if (!std::strcmp(argv[i], "--input-debug")) inputDebug = true;
        else if (!std::strcmp(argv[i], "--input-script")) inputScript = true;
        else if (!std::strcmp(argv[i], "--crate")) withCrate = true;
        else if (!std::strcmp(argv[i], "--reduced-motion")) reducedMotion = true;
        else if (!std::strcmp(argv[i], "--seconds") && i + 1 < argc) seconds = std::atof(argv[++i]);
        else if (!std::strcmp(argv[i], "--model")) {
            modelView = true;
            if (i + 1 < argc && std::strncmp(argv[i + 1], "--", 2) != 0) model = argv[++i];
        }
        else if (!std::strcmp(argv[i], "--level") && i + 1 < argc) levelPath = argv[++i];
        else if (!std::strcmp(argv[i], "--wieldables") && i + 1 < argc) wieldablesPath = argv[++i];
        else if (!std::strcmp(argv[i], "--elements") && i + 1 < argc) elementsPath = argv[++i];
        else if (!std::strcmp(argv[i], "--enemies") && i + 1 < argc) enemiesPath = argv[++i];
        else if (!std::strcmp(argv[i], "--staff") && i + 1 < argc) staffId = argv[++i];
        else if (!std::strcmp(argv[i], "--wand") && i + 1 < argc) wandId = argv[++i];
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
    coe::game::WieldableTable wieldables;
    coe::game::ElementTable elements;
    coe::game::EnemyTable enemyTypes;
    bool ok = modelView ? loadModel(cookedDir, model, mesh)
                        : loadLevelFile(levelPath, level) && loadElementsFile(elementsPath, elements) &&
                              loadWieldablesFile(wieldablesPath, wieldables) && loadEnemiesFile(enemiesPath, enemyTypes);
    if (ok && !modelView) mesh = coe::game::makeUnitCube();   // uploaded once, drawn per box
    // Step 21: the Staff + Wand slots (level mode).
    std::vector<coe::game::WieldableInstance> hands;
    coe::game::Loadout loadout;
    if (ok && !modelView) ok = buildLoadout(wieldables, staffId, wandId, hands, loadout);
    coe::VkRenderer renderer;
    ok = ok && renderer.init(cfg);
    if (ok) std::printf("GPU: %s | validation: %s\n", renderer.deviceName().c_str(),
                        renderer.validationEnabled() ? "on" : "off (layer not installed or disabled)");
    coe::ImGuiLayer ui;   // step 22 overlay (damage numbers), level mode
    if (ok && !modelView) ok = ui.init(renderer);
    coe::MeshId meshId = coe::kInvalidMesh;
    if (ok) ok = (meshId = renderer.uploadMesh(mesh)) != coe::kInvalidMesh;
    coe::game::ViewmodelMeshes vmMeshes;   // step 21 greybox staff/wand (level mode)
    if (ok && !modelView) {
        vmMeshes.shaft = renderer.uploadMesh(coe::game::makeViewmodelShaft());
        vmMeshes.head = renderer.uploadMesh(coe::game::makeViewmodelHead());
        ok = vmMeshes.shaft != coe::kInvalidMesh && vmMeshes.head != coe::kInvalidMesh;
    }
    const glm::mat4 fit = ok && modelView ? fitModel(mesh) : glm::mat4(1.0f);
    // Level mode: every box is a draw of the one cube; the frame only changes by camera.
    const coe::FrameParams levelBase = ok && !modelView ? levelFrame(level, meshId) : coe::FrameParams{};
    // Physics (level mode): static colliders from the same boxes the renderer draws.
    coe::physics::PhysicsWorld physics;
    if (ok && !modelView) {
        const coe::game::LevelPhysics lp = coe::game::buildLevelPhysics(level, physics);
        std::printf("[physics] Jolt world: %zu static box colliders, gravity %.1f m/s^2, %u Hz fixed step\n",
                    lp.bodies.size(), double(-coe::physics::WorldSettings{}.gravity.y), kTickHz);
    }
    // Step 22: the level's enemies (after the level colliders; destroyed before `physics`).
    coe::game::EnemySystem enemies(physics, elements);
    if (ok && !modelView) ok = spawnLevelEnemies(level, enemyTypes, enemies);
    coe::game::DamageNumbers damageNumbers;
    std::vector<coe::game::DamageLabel> labelScratch;

    bool ticksOk = true, inputOk = true, viewmodelOk = true;
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
        if (ok && !modelView && loadout.wieldable()) {
            // Step 21: the same view with the held staff in the viewmodel pass; its head
            // must show up where projected, in the element's colour (vmframe.ppm).
            coe::FrameParams vp = fp;
            const glm::vec3 head = addViewmodel(loadout, vmMeshes, elements, 0.0f, vp.viewmodelDraws);
            coe::HeadlessFrame vmFrame;
            ok = renderer.renderHeadless(vp, vmFrame);
            glm::vec2 px{-1.0f};
            if (ok) {
                coe::game::viewmodelPixel(head, vmFrame.width, vmFrame.height, px, vp.viewmodelFovYDeg, vp.viewmodelNear);
                std::string report;
                ok = coe::game::checkViewmodelHead(vmFrame, &frame, px,
                                                   elements.color(loadout.wieldable()->element()), report);
                std::printf("%s [%s]\n", report.c_str(), loadout.wieldable()->def->name.c_str());
                if (!coe::game::writePpm("vmframe.ppm", vmFrame)) std::fprintf(stderr, "[headless] could not write vmframe.ppm\n");
            }
        }
        if (ok && !modelView) ok = headlessDummyCheck(renderer, ui, levelBase, meshId, physics, enemies, elements, loadout);
    } else if (ok) {
        coe::FixedTimestep step(kTickHz);
        coe::game::TumbleDemo sim;   // --model only
        coe::input::InputState input;
        uint64_t presses[coe::input::kActionCount] = {};
        double lookYaw = levelBase.camera.yaw, lookPitch = levelBase.camera.pitch, lookCounts = 0.0;   // per-frame mouse look
        // Relative mode: hidden cursor, unbounded motion deltas. Not fatal if the
        // compositor refuses (e.g. window not focused yet).
        if (!SDL_SetWindowRelativeMouseMode(window, true))
            std::fprintf(stderr, "[input] relative mouse mode unavailable: %s\n", SDL_GetError());
        coe::physics::BodyHandle crate;
        coe::physics::BodyState cratePrev, crateCur;   // poses at the last two ticks, for interpolation
        if (!modelView && withCrate) {
            crate = physics.addDynamicBox(demoCrate(level));
            cratePrev = crateCur = physics.state(crate);
        }
        std::unique_ptr<coe::game::PlayerController> player;
        glm::vec3 spawnFeet{0.0f}, spawnForward{0.0f};
        float apex = 0.0f;   // highest feet above the spawn
        float minMana = 0.0f, castCost = 0.0f;   // lowest mana seen after a cast; the last cast's cost
        // Casting (step 17) through the loadout's slots (step 21, built above).
        coe::game::ProjectileSystem bolts;
        bolts.setElements(&elements);   // tracer colours from elements.toml (step 20)
        // Focus (ADS) and spread (step 19): Aim tweens the FOV to the wieldable's focus FOV;
        // casts leave along a cone from its accuracy, stance and bloom.
        coe::game::Focus focus;
        coe::game::Spread spread;
        float minFov = focus.fov();   // narrowest FOV any tick reached
        // Step 21 script checks: what was held when focusing / for the first cast; the
        // first swap's start tick (the press) and the tick it ended on.
        const coe::game::WieldableInstance *focusWith = nullptr, *firstCastWith = nullptr;
        uint64_t swapStartTick = 0, swapEndTick = 0;
        // Step 21 done-check in the window: frame kCaptureFrame is read back and the
        // viewmodel head must be at its projected pixel in the element colour.
        constexpr uint64_t kCaptureFrame = 4;
        glm::vec3 captureHead{0.0f}, captureColor{0.0f};
        std::string captureName;
        bool vmChecked = false, vmOk = false;
        std::vector<coe::game::ProjectileHit> boltHits;
        std::vector<coe::game::DebugLine> debugLines;
        if (!modelView) {
            const float yaw = glm::radians(level.playerStart.yawDeg);
            player = std::make_unique<coe::game::PlayerController>(physics, level.playerStart.position, yaw);
            player->setReducedMotion(reducedMotion);
            loadout.setManaSpender([&p = *player](float cost) { return p.mana().spend(cost); });
            std::printf("[loadout] staff slot: %s | wand slot: %s | holding the %s\n",
                        loadout.inSlot(coe::game::Slot::Staff) ? loadout.inSlot(coe::game::Slot::Staff)->def->name.c_str() : "empty",
                        loadout.inSlot(coe::game::Slot::Wand) ? loadout.inSlot(coe::game::Slot::Wand)->def->name.c_str() : "empty",
                        coe::game::slotName(loadout.active()));
            spawnFeet = player->feet();
            spawnForward = coe::game::PlayerController::forwardFor(yaw);
            std::printf("[player] spawned at (%.2f, %.2f, %.2f) facing %.0f deg, %s, eye %.2f m\n", double(spawnFeet.x),
                        double(spawnFeet.y), double(spawnFeet.z), double(level.playerStart.yawDeg),
                        coe::physics::groundStateName(player->character().groundState()), double(player->eyeHeight()));
        }
        bool physicsOk = true;
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
                if (inputScript && isRealInput(e)) continue;   // only the script drives a scripted run
                if (e.type == SDL_EVENT_KEY_DOWN && e.key.key == SDLK_ESCAPE) running = false;
                if (e.type == SDL_EVENT_WINDOW_PIXEL_SIZE_CHANGED) renderer.onResize();
                input.handleEvent(e);
            }
            const uint64_t now = coe::monotonicNs();
            for (uint32_t n = step.advance(now - last); n > 0; --n) {
                const coe::input::TickInput in = input.consumeTick();
                for (size_t a = 0; a < coe::input::kActionCount; ++a) presses[a] += in.pressCount[a];
                if (inputDebug) printTick(step.totalTicks() - n + 1, in);
                if (modelView) sim.tick(step.dtSeconds());
                else {
                    player->tick(in, float(step.dtSeconds()));   // moves the character, then the world steps
                    apex = std::max(apex, player->feet().y - spawnFeet.y);
                    physicsOk = physics.step(float(step.dtSeconds())) && physicsOk;
                    // Cast from where the player is after this tick, then sweep the bolts
                    // against the world as just stepped.
                    const size_t fire = size_t(coe::input::Action::Fire);
                    // Step 21: no focus while swapping (Aim held through a swap focuses after it).
                    focus.tick(in.held[size_t(coe::input::Action::Aim)] && loadout.ready(), loadout.wieldable(),
                               float(step.dtSeconds()));
                    minFov = std::min(minFov, focus.fov());
                    if (focus.focused()) focusWith = loadout.wieldable();
                    spread.tick(float(step.dtSeconds()));
                    const coe::game::WieldableInstance* held = loadout.wieldable();
                    const float accuracy = held ? held->accuracy() : coe::game::kBaseAccuracy;
                    const coe::game::CastAim eyeAim = coe::game::playerAim(*player);
                    coe::game::CastAim aim = spread.apply(eyeAim, accuracy, coe::game::stanceOf(*player, focus));
                    if (held) {   // tracer from the viewmodel's CastPoint (the bolt still flies the eye ray)
                        coe::Camera c;
                        c.position = eyeAim.origin;
                        c.yaw = player->yaw();
                        c.pitch = player->pitch();
                        c.fovYDeg = focus.fov();
                        const glm::vec3 tip = coe::game::viewmodelCastPoint(
                            held->type(), coe::game::viewmodelTransform(held->type(), focus.amount(), 0.0f));
                        aim.visualOffset = coe::game::viewmodelToWorld(tip, c) - eyeAim.origin;
                    }
                    if (loadout.tick(in.pressed[fire], in.held[fire], float(step.dtSeconds()), aim, bolts)) {
                        const coe::game::Caster& caster = loadout.caster();
                        spread.onCast();
                        castCost = caster.wieldable()->manaCost();
                        if (firstCastWith == nullptr) firstCastWith = caster.wieldable();
                        minMana = loadout.casts() == 1 ? player->mana().value() : std::min(minMana, player->mana().value());
                        std::printf("[cast] %s (%s): bolt %.0f m/s, %.0f m range, %.1f dmg, -%.1f mana -> %.1f/%.0f, "
                                    "accuracy %.0f%%, spread %.2f deg%s\n",
                                    caster.wieldable()->def->name.c_str(), coe::game::elementName(caster.wieldable()->element()),
                                    double(caster.wieldable()->projectileSpeed()), double(caster.wieldable()->range()),
                                    double(caster.wieldable()->damage()), double(castCost),
                                    double(player->mana().value()), double(player->mana().max()), double(accuracy),
                                    double(spread.lastConeDeg()), focus.focused() ? ", focused" : "");
                    }
                    boltHits.clear();
                    bolts.tick(physics, float(step.dtSeconds()), boltHits);
                    for (const coe::game::ProjectileHit& h : boltHits) {
                        // Step 22: hits on enemies run the damage formula and float a number.
                        if (const std::optional<coe::game::EnemyHit> eh = enemies.applyHit(h)) {
                            printEnemyHit(enemies, *eh, h, elements);
                            damageNumbers.add(h.point, eh->result, h.element, elements);
                            continue;
                        }
                        std::printf("[cast] hit %s body %u at %.2f m after %.3f s (tick %d) at (%.2f, %.2f, %.2f), "
                                    "%.1f %s dmg\n",
                                    coe::physics::layerName(physics.layer(h.body)), h.body.id, double(h.distance),
                                    double(h.time), h.tick, double(h.point.x), double(h.point.y), double(h.point.z),
                                    double(h.damage), elements.name(h.element).c_str());
                    }
                    for (const coe::game::EnemyDeath& d : enemies.takeDeaths())
                        std::printf("[enemy] %s died (%s), %zu left\n", d.def->name.c_str(),
                                    coe::game::elementName(d.killingElement), enemies.alive());
                    enemies.tick(float(step.dtSeconds()));
                    damageNumbers.tick(float(step.dtSeconds()));
                    // Weapon1 = Staff slot, Weapon2 = Wand slot (Weapon3/4: unbound until step
                    // 44's options), after the cast so a same-tick Fire + switch casts the old one.
                    for (size_t k = 0; k < coe::game::kSlotCount; ++k)
                        if (in.pressed[size_t(coe::input::Action::Weapon1) + k] &&
                            loadout.select(static_cast<coe::game::Slot>(k)))
                            std::printf("[loadout] tick %llu: swapping to the %s slot (%s), %.2f s\n",
                                        (unsigned long long)(step.totalTicks() - n + 1), coe::game::slotName(loadout.active()),
                                        loadout.wieldable()->def->name.c_str(), double(loadout.tuning().equipTime));
                    if (swapStartTick == 0 && loadout.swapping()) swapStartTick = step.totalTicks() - n + 1;
                    if (swapStartTick && !swapEndTick && !loadout.swapping()) swapEndTick = step.totalTicks() - n + 1;
                    if (crate.valid()) {
                        cratePrev = crateCur;
                        crateCur = physics.state(crate);
                    }
                }
            }
            last = now;
            // Mouse look per render frame (not per tick) for minimum latency; the next
            // ticks walk along the new yaw.
            const coe::input::LookDelta look = input.takeLook();
            lookCounts += look.dx;
            if (player) {
                // Focused: scale by tan(fov/2)/tan(hip/2) so a count moves the view by the
                // same screen fraction at any FOV.
                const float s = focus.lookScale(float(step.alpha()));
                player->addLook(look.dx * s, look.dy * s);
                lookYaw = player->yaw();
                lookPitch = player->pitch();
            } else {
                lookYaw = std::remainder(lookYaw - look.dx * kLookRadPerCount, 2.0 * 3.141592653589793);
                lookPitch = std::clamp(lookPitch - look.dy * kLookRadPerCount,
                                       -double(coe::Camera::kMaxPitch), double(coe::Camera::kMaxPitch));   // +-89 deg
            }
            if (inputDebug && (look.dx != 0.0f || look.dy != 0.0f))
                std::printf("[input] frame %llu: look dx %.1f dy %.1f -> yaw %.3f pitch %.3f rad\n",
                            (unsigned long long)frames, double(look.dx), double(look.dy), lookYaw, lookPitch);
            if (limitNs && now - start >= limitNs) running = false;
            if (SDL_GetWindowFlags(window) & SDL_WINDOW_MINIMIZED) { SDL_Delay(16); continue; }
            coe::FrameParams fp = levelBase;
            if (player) {
                fp.camera = player->camera(float(step.alpha()));   // eye, interpolated between ticks
                fp.camera.fovYDeg = focus.fov(float(step.alpha()));   // focus tween (viewmodel stays 75: step 21)
            } else {
                fp.camera.yaw = float(lookYaw);       // mouse right -> negative yaw -> turn right
                fp.camera.pitch = float(lookPitch);
            }
            if (modelView) fp.draws.push_back({meshId, sim.renderModel(step.alpha()) * fit});
            else if (crate.valid()) {
                const float a = float(step.alpha());
                glm::mat4 m = glm::translate(glm::mat4(1.0f), glm::mix(cratePrev.position, crateCur.position, a));
                m = m * glm::mat4_cast(glm::slerp(cratePrev.rotation, crateCur.rotation, a));
                fp.draws.push_back({meshId, glm::scale(m, glm::vec3(kDemoCrateEdge)), kDemoCrateTint});
            }
            if (!modelView) {
                const glm::vec3 head = addViewmodel(loadout, vmMeshes, elements, focus.amount(), fp.viewmodelDraws);
                if (frames == kCaptureFrame && renderer.captureSupported() && loadout.wieldable() && head.z < 0.0f) {
                    renderer.requestCapture();
                    captureHead = head;
                    captureColor = elements.color(loadout.wieldable()->element());
                    captureName = loadout.wieldable()->def->name;
                }
                debugLines.clear();
                bolts.debugLines(float(step.alpha()), debugLines);
                for (const coe::game::DebugLine& l : debugLines)
                    fp.draws.push_back({meshId, lineModel(l.a, l.b), glm::vec4(l.color, 1.0f)});
                enemies.draws(meshId, fp.draws);
                const VkExtent2D ext = renderer.targetExtent();
                const glm::vec2 size{float(ext.width), float(ext.height)};
                ui.beginFrame(size, float(step.dtSeconds()));
                if (size.x > 0.0f && size.y > 0.0f)
                    drawDamageLabels(ui, damageNumbers, fp.camera.viewProjection(size.x / size.y), size, labelScratch);
                ui.endFrame();
                fp.overlay = ui.recorder();
            }
            ok = renderer.drawFrame(fp);
            if (coe::HeadlessFrame cap; ok && renderer.takeCapture(cap)) {
                glm::vec2 px{-1.0f};
                coe::game::viewmodelPixel(captureHead, cap.width, cap.height, px, fp.viewmodelFovYDeg, fp.viewmodelNear);
                std::string report;
                vmOk = coe::game::checkViewmodelHead(cap, nullptr, px, captureColor, report);
                vmChecked = true;
                std::printf("%s [window frame %llu, %ux%u, %s]\n", report.c_str(), (unsigned long long)frames, cap.width,
                            cap.height, captureName.c_str());
            }
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
            if (player) {
                // Scripted W + Space + Q must reach the controller: it walks forward, jumps
                // and dashes (forward, no move key held by then: + 6 m).
                const float forward = glm::dot(player->feet() - spawnFeet, spawnForward);
                const bool moved = forward > 0.2f + 5.0f && player->jumps() >= 1 && apex > 0.5f &&
                                   player->dash().dashes() == 1;
                // Fire (LMB, frame 12) casts one Apprentice Fire Staff bolt at the north
                // wall (well inside its 50 m range: it hits, or is still flying at exit).
                const bool cast = loadout.casts() == 1 && bolts.fizzled() == 0;
                // Its mana cost (5) was paid exactly once: 100 -> 95, then it regenerates
                // (3/s after 1.5 s) but never past 100.
                const coe::game::Mana& mana = player->mana();
                const bool paid = mana.spends() == 1 && mana.refusals() == 0 && castCost > 0.0f &&
                                  minMana == mana.tuning().max - castCost && mana.value() >= minMana &&
                                  mana.value() <= mana.max();
                // RMB (frames 24-50) with the default staff slot (Apprentice Fire Staff)
                // narrowed the FOV toward 55 deg, and the release tweened it back to exactly 75.
                const coe::game::WieldableInstance* staff = loadout.inSlot(coe::game::Slot::Staff);
                const bool focused = minFov < focus.tuning().hipFovDeg && focus.fov() == focus.tuning().hipFovDeg &&
                                     !focus.focused() && focusWith == staff && firstCastWith == staff;
                // Step 21: Weapon2 (frame 52) swapped to the wand slot; the swap took the
                // equip time (0.4 s = 24 ticks) and ended within the run.
                const uint64_t swapTicks = swapEndTick > swapStartTick ? swapEndTick - swapStartTick : 0;
                const uint64_t wantTicks = uint64_t(std::lround(loadout.tuning().equipTime * float(kTickHz)));
                const bool swapped = loadout.swaps() == 1 && loadout.active() == coe::game::Slot::Wand &&
                                     !loadout.swapping() && swapTicks == wantTicks;
                inputOk = inputOk && moved && cast && paid && focused && swapped;
                std::printf("[focus] script: narrowest FOV %.1f deg (target %.0f) with %s, back to %.1f%s\n", double(minFov),
                            double(staff ? coe::game::focusFovFor(staff->type(), focus.tuning()) : focus.tuning().hipFovDeg),
                            focusWith ? focusWith->def->name.c_str() : "nothing", double(focus.fov()),
                            focused ? "" : " MISMATCH (need < 75 while held with the staff slot, 75 after release)");
                std::printf("[loadout] script: %llu swap(s), now the %s slot (%s), swap took %llu ticks (expect %llu)%s\n",
                            (unsigned long long)loadout.swaps(), coe::game::slotName(loadout.active()),
                            loadout.wieldable() ? loadout.wieldable()->def->name.c_str() : "nothing",
                            (unsigned long long)swapTicks, (unsigned long long)wantTicks,
                            swapped ? "" : " MISMATCH (need 1 finished swap to the wand slot taking the equip time)");
                std::printf("[mana] script: %llu spend(s), %llu refusal(s), lowest %.2f (expect %.2f), now %.2f/%.0f%s\n",
                            (unsigned long long)mana.spends(), (unsigned long long)mana.refusals(), double(minMana),
                            double(mana.tuning().max - castCost), double(mana.value()), double(mana.max()),
                            paid ? "" : " MISMATCH (need 1 spend of the cast's cost)");
                std::printf("[cast] script: %llu cast(s), %llu hit(s), %llu fizzled%s\n",
                            (unsigned long long)loadout.casts(), (unsigned long long)bolts.hits(),
                            (unsigned long long)bolts.fizzled(), cast ? "" : " MISMATCH (need 1 cast, 0 fizzled)");
                std::printf("[player] script: moved %.2f m forward, %llu jump(s), apex %.2f m, %llu dash(es)%s\n",
                            double(forward), (unsigned long long)player->jumps(), double(apex),
                            (unsigned long long)player->dash().dashes(),
                            moved ? "" : " MISMATCH (need > 5.2 m, >= 1 jump, apex > 0.5 m, 1 dash)");
            }
        }
        SDL_SetWindowRelativeMouseMode(window, false);
        const double elapsed = double(last - start) / 1e9;
        // Every ns of frame time was fed to the accumulator, so the tick count is exact.
        const uint64_t expected = (last - start - step.droppedNs()) * kTickHz / coe::FixedTimestep::kNsPerSecond;
        ticksOk = step.totalTicks() == expected;
        if (!modelView) {
            // One physics step per fixed tick, no Jolt errors.
            const bool stepsMatch = physics.steps() == step.totalTicks();
            ticksOk = ticksOk && stepsMatch && physicsOk;
            std::printf("[physics] %llu steps (one per tick%s)%s\n", (unsigned long long)physics.steps(),
                        stepsMatch ? "" : " MISMATCH", physicsOk ? "" : ", update ERRORS");
            if (crate.valid())
                std::printf("[physics] demo crate at (%.2f, %.2f, %.2f) %s\n", double(crateCur.position.x),
                            double(crateCur.position.y), double(crateCur.position.z), crateCur.active ? "moving" : "asleep");
            const glm::vec3 f = player->feet();
            std::printf("[player] feet at (%.2f, %.2f, %.2f), %s, eye %.2f m, %llu jump(s), apex %.2f m, "
                        "Breath %.0f/%.0f, %llu slide(s), %llu dash(es), %llu landing(s)%s\n", double(f.x),
                        double(f.y), double(f.z), coe::physics::groundStateName(player->character().groundState()),
                        double(player->eyeHeight()), (unsigned long long)player->jumps(), double(apex),
                        double(player->breath().value()), double(player->breath().max()),
                        (unsigned long long)player->slides(), (unsigned long long)player->dash().dashes(),
                        (unsigned long long)player->landings(), reducedMotion ? ", reduced motion" : "");
            std::printf("[mana] %.2f/%.0f, %llu spend(s), %llu refusal(s), regen %.1f/s after %.1f s%s\n",
                        double(player->mana().value()), double(player->mana().max()),
                        (unsigned long long)player->mana().spends(), (unsigned long long)player->mana().refusals(),
                        double(player->mana().regenRate()), double(player->mana().tuning().regenDelay),
                        player->mana().regenerating() ? ", regenerating" : "");
            uint64_t blocked = 0, manaRefused = 0;
            for (size_t k = 0; k < coe::game::kSlotCount; ++k) {
                blocked += loadout.caster(static_cast<coe::game::Slot>(k)).blocked();
                manaRefused += loadout.caster(static_cast<coe::game::Slot>(k)).manaRefused();
            }
            std::printf("[cast] %llu cast(s), %llu refused (%llu cooldown, %llu mana, %llu mid-swap), %llu hit(s), "
                        "%llu fizzled, %zu in flight, holding %s\n", (unsigned long long)loadout.casts(),
                        (unsigned long long)(blocked + loadout.swapBlocked()), (unsigned long long)(blocked - manaRefused),
                        (unsigned long long)manaRefused, (unsigned long long)loadout.swapBlocked(),
                        (unsigned long long)bolts.hits(), (unsigned long long)bolts.fizzled(), bolts.live().size(),
                        loadout.wieldable() ? loadout.wieldable()->def->name.c_str() : "nothing");
            // Step 21: the window viewmodel check must have run and passed (when the
            // swapchain can be read back at all).
            if (!renderer.captureSupported()) std::puts("[viewmodel] window check skipped: swapchain has no TRANSFER_SRC");
            else if (!vmChecked) std::puts("[viewmodel] window check never ran MISMATCH (run ended before frame 4?)");
            viewmodelOk = !renderer.captureSupported() || (vmChecked && vmOk);
            std::printf("[focus] FOV %.1f deg%s, narrowest %.1f; spread bloom %.2f deg\n", double(focus.fov()),
                        focus.focused() ? " (focused)" : "", double(minFov), double(spread.bloomDeg()));
            loadout.setManaSpender(nullptr);   // it refers to the player
            player.reset();   // before the world it lives in
        }
        std::printf("frames: %llu in %.2fs (%.0f fps)\n", (unsigned long long)frames, elapsed,
                    elapsed > 0 ? double(frames) / elapsed : 0.0);
        std::printf("fixed ticks: %llu @ %u Hz (expected %llu, %.3fs dropped by hitch clamp)%s\n",
                    (unsigned long long)step.totalTicks(), kTickHz, (unsigned long long)expected,
                    double(step.droppedNs()) / 1e9, ticksOk ? "" : " MISMATCH");
    }
    ui.shutdown();   // before the device goes
    renderer.shutdown();
    auto s = renderer.stats();
    std::printf("validation messages: %u errors, %u warnings\n", s.errors, s.warnings);
    if (window) SDL_DestroyWindow(window);
    SDL_Quit();
    bool pass = ok && ticksOk && inputOk && viewmodelOk && s.errors == 0;
    std::puts(pass ? "RESULT: PASS" : "RESULT: FAIL");
    return pass ? 0 : 1;
}
