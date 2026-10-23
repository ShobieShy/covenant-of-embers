// SPDX-License-Identifier: Apache-2.0
// Unit tests for game/magic/accuracy (BUILD_PLAN step 19): focus (ADS) FOV tween, Magewar
// accuracy, spread cone, stance multipliers and bloom. Done-check:
//  - 100 % accuracy => zero spread (any stance, any bloom; bolts fly exactly along the aim);
//  - focused spread = 0.35 x hip spread;
//  - bloom decays to the base cone within its configured time (0.5 s for a full bloom);
//  - the FOV reaches 55 deg 0.2 s after Aim is pressed (12 ticks at 60 Hz).
// Plain checks; doctest in step 20.
#include "engine/physics/physics.hpp"
#include "engine/render/camera.hpp"
#include "game/magic/accuracy.hpp"
#include "game/magic/casting.hpp"
#include "game/magic/projectile.hpp"
#include "game/magic/wieldable.hpp"
#include "game/player/player_controller.hpp"

#include <glm/glm.hpp>

#include <algorithm>
#include <cmath>
#include <cstdio>
#include <vector>

#ifndef COE_DATA_DIR
#define COE_DATA_DIR "data"
#endif

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using namespace coe::game;
namespace ph = coe::physics;
using coe::input::Action;
constexpr float kDt = 1.0f / 60.0f;

bool near(float a, float b, float eps) { return std::fabs(a - b) <= eps; }
float angleDeg(glm::vec3 a, glm::vec3 b) {
    return glm::degrees(std::acos(std::clamp(glm::dot(glm::normalize(a), glm::normalize(b)), -1.0f, 1.0f)));
}

WieldableTable loadReal() {
    WieldableTable t;
    const std::string err = loadWieldables(std::string(COE_DATA_DIR) + "/magic/wieldables.toml", t);
    if (!err.empty()) std::fprintf(stderr, "%s\n", err.c_str());
    CHECK(err.empty());
    return t;
}

coe::input::TickInput hold(std::initializer_list<Action> held, std::initializer_list<Action> pressed = {}) {
    coe::input::TickInput in;
    for (Action a : held) in.held.set(size_t(a));
    for (Action a : pressed) { in.pressed.set(size_t(a)); in.held.set(size_t(a)); in.pressCount[size_t(a)] = 1; }
    return in;
}

// --- Camera --------------------------------------------------------------------------

void cameraFov() {
    CHECK(coe::Camera::kViewmodelFovYDeg == 75.0f && coe::Camera::kDefaultFovYDeg == 75.0f);
    CHECK(coe::Camera::lookScaleForFov(75.0f) == 1.0f);
    const float s55 = coe::Camera::lookScaleForFov(55.0f);
    CHECK(near(s55, std::tan(glm::radians(27.5f)) / std::tan(glm::radians(37.5f)), 1e-6f) && near(s55, 0.6784f, 1e-4f));
    // The projection's focal length grows by exactly 1 / lookScale: a look count moves the
    // image under the crosshair by the same screen fraction at 55 and 75 deg.
    coe::Camera hip, ads;
    ads.fovYDeg = 55.0f;
    CHECK(near(hip.projection(1.0f)[1][1] / ads.projection(1.0f)[1][1], s55, 1e-6f));
    std::printf("camera: look scale at 55 deg %.4f, viewmodel fixed at %.0f deg\n", double(s55),
                double(coe::Camera::kViewmodelFovYDeg));
}

// --- Focus ---------------------------------------------------------------------------

void focusTween() {
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("apprentice_fire_staff")), wand(*t.find("swift_wind_wand"));
    CHECK(focusFovFor(WieldableType::Staff) == 55.0f && focusFovFor(WieldableType::Wand) == 55.0f);   // Magewar: same script

    Focus f;
    CHECK(f.fov() == 75.0f && !f.focused() && f.amount() == 0.0f);
    int reach = -1;
    for (int i = 1; i <= 20; ++i) {
        f.tick(true, &staff, kDt);
        if (i == 6) CHECK(near(f.fov(), 65.0f, 1e-3f) && near(f.amount(), 0.5f, 1e-4f));   // linear (Godot tween default)
        if (i == 11) CHECK(f.fov() > 55.0f);
        if (reach < 0 && f.fov() == 55.0f) reach = i;
    }
    std::printf("focus: staff 75 -> 55 deg in %d ticks (%.4f s) at 60 Hz\n", reach, double(reach) * double(kDt));
    CHECK(reach == 12);   // done-check: 0.2 s
    CHECK(f.focused() && f.amount() == 1.0f && near(f.lookScale(1.0f), 0.6784f, 1e-4f));
    // Render interpolation between the last two ticks.
    Focus g;
    g.tick(true, &staff, kDt);
    g.tick(true, &staff, kDt);
    CHECK(near(g.fov(0.0f), 75.0f - 20.0f / 12.0f, 1e-3f) && near(g.fov(1.0f), 75.0f - 40.0f / 12.0f, 1e-3f));
    CHECK(near(g.fov(0.5f), 75.0f - 30.0f / 12.0f, 1e-3f));
    // Release: back to 75 in 0.2 s.
    int back = -1;
    for (int i = 1; i <= 20; ++i) {
        f.tick(false, &staff, kDt);
        if (back < 0 && f.fov() == 75.0f) back = i;
    }
    CHECK(back == 12 && !f.focused() && f.amount() == 0.0f);
    // Release mid-tween (at 65): a new 0.2 s tween from 65, like Godot's tween_property.
    Focus h;
    for (int i = 0; i < 6; ++i) h.tick(true, &wand, kDt);
    CHECK(near(h.fov(), 65.0f, 1e-3f));
    for (int i = 0; i < 6; ++i) h.tick(false, &wand, kDt);
    CHECK(near(h.fov(), 70.0f, 1e-3f));
    for (int i = 0; i < 6; ++i) h.tick(false, &wand, kDt);
    CHECK(h.fov() == 75.0f);
    // Other tick rates: 0.2 s = 6 ticks at 30 Hz, 28.8 -> 29 ticks at 144 Hz.
    for (const auto [hz, expect] : {std::pair{30, 6}, std::pair{144, 29}}) {
        Focus r;
        int n = 0;
        while (r.fov() != 55.0f && n < 100) { r.tick(true, &wand, 1.0f / float(hz)); ++n; }
        CHECK(n == expect);
    }
    // Empty hands: Aim does nothing (Magewar's ADS lives on the wieldable).
    Focus e;
    for (int i = 0; i < 20; ++i) e.tick(true, nullptr, kDt);
    CHECK(e.fov() == 75.0f && !e.focused());
    // Unequipping while focused tweens back to the hip FOV.
    for (int i = 0; i < 12; ++i) e.tick(true, &staff, kDt);
    CHECK(e.fov() == 55.0f);
    for (int i = 0; i < 12; ++i) e.tick(true, nullptr, kDt);
    CHECK(e.fov() == 75.0f && !e.focused());
    // A custom (wider) wand FOV is honoured per type.
    FocusTuning tw;
    tw.wandFovDeg = 65.0f;
    Focus w2(tw);
    for (int i = 0; i < 12; ++i) w2.tick(true, &wand, kDt);
    CHECK(w2.fov() == 65.0f && w2.amount() == 1.0f);
    for (int i = 0; i < 12; ++i) w2.tick(true, &staff, kDt);   // swap while focused: retarget
    CHECK(w2.fov() == 55.0f);
}

// --- Accuracy + cone -----------------------------------------------------------------

void accuracyStat() {
    const WieldableTable t = loadReal();
    WieldableInstance w(*t.find("apprentice_fire_staff"));
    CHECK(w.accuracy() == 50.0f);   // Magewar base 50
    // Magewar parts: basic_fire_head 5, basic_handle 10, unique_void_charm 12; the
    // basic_fire_interior's 2 does not count (get_final_accuracy reads Head/Handle/Charm).
    w.parts = {{"basic_fire_head", PartType::Head, 5.0f}, {"basic_handle", PartType::Handle, 10.0f},
               {"unique_void_charm", PartType::Charm, 12.0f}, {"basic_fire_interior", PartType::Interior, 2.0f},
               {"uncommon_air_exterior", PartType::Exterior, 6.0f}};
    CHECK(w.accuracy() == 77.0f);
    w.parts.push_back({"rare_air_handle", PartType::Handle, 22.0f});
    w.parts.push_back({"primordial_fire_head", PartType::Head, 15.0f});
    CHECK(w.accuracy() == 100.0f);   // 114 clamped
    w.parts = {{"cursed", PartType::Charm, -80.0f}};
    CHECK(w.accuracy() == 0.0f);
}

void zeroSpreadAtFullAccuracy() {
    SpreadTuning st;
    const Stance stances[] = {{}, {0.0f, false, true, false}, {0.0f, false, false, true}, {1.0f, true, true, false}};
    for (const Stance& s : stances) {
        CHECK(spreadConeDeg(100.0f, stanceMultiplier(s), 0.0f) == 0.0f);
        CHECK(spreadConeDeg(100.0f, stanceMultiplier(s), st.bloomMaxDeg) == 0.0f);
        CHECK(spreadConeDeg(130.0f, stanceMultiplier(s), 2.0f) == 0.0f);
    }
    Spread sp;
    for (int i = 0; i < 8; ++i) sp.onCast();
    CHECK(sp.bloomDeg() == st.bloomMaxDeg);
    const glm::vec3 dirs[] = {{0, 0, -1}, glm::normalize(glm::vec3(0.3f, -0.4f, -0.8f)), {0, 1, 0}, {0, -1, 0}};
    for (int i = 0; i < 1000; ++i) {
        CastAim aim;
        aim.direction = dirs[i % 4];
        const CastAim out = sp.apply(aim, 100.0f, stances[i % 4]);
        CHECK(out.direction == aim.direction && sp.lastConeDeg() == 0.0f);   // bit-exact
    }
    // Through the real Caster: 10 Swift Wind casts at 100 % fly exactly along the aim.
    const WieldableTable t = loadReal();
    WieldableInstance wand(*t.find("swift_wind_wand"));
    wand.parts = {{"h", PartType::Head, 30.0f}, {"g", PartType::Handle, 20.0f}};
    CHECK(wand.accuracy() == 100.0f);
    Caster caster(wand);
    ProjectileSystem bolts;
    Spread s2;
    CastAim aim;
    aim.direction = glm::normalize(glm::vec3(0.2f, 0.1f, -1.0f));
    float worst = 0.0f;
    for (int tick = 0; tick < 200 && caster.casts() < 10; ++tick) {
        s2.tick(kDt);
        if (caster.tick(true, true, kDt, s2.apply(aim, wand.accuracy(), Stance{0.0f, false, false, true}), bolts)) s2.onCast();
    }
    for (const Projectile& p : bolts.live()) worst = std::max(worst, angleDeg(p.spawn.direction, aim.direction));
    CHECK(caster.casts() == 10 && bolts.live().size() == 10 && worst < 1e-3f);
    std::printf("spread: 100 %% accuracy -> cone 0, 10 bolts within %.5f deg of the aim\n", double(worst));
}

void focusedIsPoint35Hip() {
    SpreadTuning st;
    CHECK(st.focusMul == 0.35f && st.crouchMul == 0.8f && st.movingMul == 1.3f && st.airborneMul == 1.8f);
    // Magewar base accuracy 50 %: hip still = 4 x 0.5 = 2.0 deg.
    CHECK(near(spreadConeDeg(50.0f, 1.0f, 0.0f), 2.0f, 1e-6f));
    for (const float acc : {0.0f, 25.0f, 50.0f, 77.0f, 99.0f})
        for (const Stance body : {Stance{}, Stance{0, true, false, false}, Stance{0, false, true, false},
                                  Stance{0, true, true, false}, Stance{0, false, false, true}}) {
            Stance focused = body;
            focused.focus = 1.0f;
            const float hip = spreadConeDeg(acc, stanceMultiplier(body), 1.5f);
            const float ads = spreadConeDeg(acc, stanceMultiplier(focused), 1.5f);
            CHECK(near(ads, 0.35f * hip, 1e-5f));
        }
    CHECK(near(stanceMultiplier({0, true, false, false}), 0.8f, 1e-6f));
    CHECK(near(stanceMultiplier({0, false, true, false}), 1.3f, 1e-6f));
    CHECK(near(stanceMultiplier({0, true, true, false}), 1.04f, 1e-6f));
    CHECK(near(stanceMultiplier({0, true, true, true}), 1.8f, 1e-6f));   // airborne replaces the rest
    CHECK(near(stanceMultiplier({0.5f, false, false, false}), 0.675f, 1e-6f));   // half-way through the tween
    // Driven by the real Focus: 12 ticks of Aim with a staff = fully focused = 0.35x.
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("earthward_battlestaff"));
    Focus f;
    Spread sp;
    const float hip = sp.coneDeg(staff.accuracy(), Stance{f.amount(), false, false, false});
    for (int i = 0; i < 12; ++i) f.tick(true, &staff, kDt);
    const float ads = sp.coneDeg(staff.accuracy(), Stance{f.amount(), false, false, false});
    CHECK(near(ads, 0.35f * hip, 1e-6f));
    std::printf("spread: 50 %% accuracy hip %.3f deg, focused %.3f deg (x%.3f)\n", double(hip), double(ads), double(ads / hip));
}

void stanceFromPlayer() {
    ph::PhysicsWorld w;
    ph::BoxDesc floor;
    floor.center = {0, -0.5f, 0};
    floor.halfExtents = {50, 0.5f, 50};
    w.addStaticBox(floor);
    w.optimizeBroadPhase();
    PlayerController p(w, {0, 0, 0}, 0.0f);
    Focus f;
    auto run = [&](const coe::input::TickInput& in, int n) {
        for (int i = 0; i < n; ++i) { p.tick(in, kDt); CHECK(w.step(kDt)); }
    };
    run({}, 30);
    Stance s = stanceOf(p, f);
    CHECK(!s.airborne && !s.crouched && !s.moving && s.focus == 0.0f && stanceMultiplier(s) == 1.0f);
    run(hold({Action::MoveForward}), 30);
    s = stanceOf(p, f);
    CHECK(!s.airborne && s.moving && !s.crouched && near(stanceMultiplier(s), 1.3f, 1e-6f));
    run({}, 60);
    run(hold({Action::Crouch}), 30);
    s = stanceOf(p, f);
    CHECK(s.crouched && !s.moving && !s.airborne && near(stanceMultiplier(s), 0.8f, 1e-6f));
    run({}, 30);
    run(hold({}, {Action::Jump}), 1);
    run({}, 10);
    s = stanceOf(p, f);
    CHECK(s.airborne && near(stanceMultiplier(s), 1.8f, 1e-6f));
}

void bloomDecay() {
    SpreadTuning st;
    // A full bloom (cap 4 deg after 4+ casts) is gone exactly bloomRecoverySeconds (0.5 s)
    // after the last cast: 30 ticks at 60 Hz, 72 at 144 Hz, 15 at 30 Hz.
    for (const auto [hz, expect] : {std::pair{60, 30}, std::pair{144, 72}, std::pair{30, 15}}) {
        Spread sp;
        const float dt = 1.0f / float(hz);
        const float base = sp.coneDeg(50.0f, {});
        for (int i = 0; i < 6; ++i) sp.onCast();
        CHECK(sp.bloomDeg() == st.bloomMaxDeg);
        CHECK(near(sp.coneDeg(50.0f, {}), 2.0f * base, 1e-5f));   // cap doubles the cone
        int n = 0;
        while (sp.bloomDeg() > 0.0f && n < 1000) { sp.tick(dt); ++n; }
        std::printf("bloom: full %.1f deg -> 0 in %d ticks at %d Hz (%.4f s, limit %.2f s)\n", double(st.bloomMaxDeg), n,
                    hz, double(n) * double(dt), double(st.bloomRecoverySeconds));
        CHECK(n == expect);
        CHECK(double(n) * double(dt) <= double(st.bloomRecoverySeconds) + 1e-6);
        CHECK(sp.coneDeg(50.0f, {}) == base);   // back to the base cone
    }
    // One cast blooms by 1 deg (x 0.5 at 50 %) and is gone in 0.125 s (8 ticks at 60 Hz).
    Spread sp;
    const float base = sp.coneDeg(50.0f, {});
    sp.onCast();
    CHECK(near(sp.coneDeg(50.0f, {}) - base, 0.5f, 1e-6f));
    int n = 0;
    while (sp.bloomDeg() > 0.0f && n < 100) { sp.tick(kDt); ++n; }
    CHECK(n == 8 && sp.coneDeg(50.0f, {}) == base);
    // Through the Caster: Swift Wind spam at 60 Hz (a cast every 11 ticks) blooms at most
    // to 1 deg + what is left (11 ticks decay 1.47 deg > 1 deg: it never stacks), the Fire
    // staff likewise; Spread::tick before the cast, onCast after.
    const WieldableTable t = loadReal();
    const WieldableInstance wand(*t.find("swift_wind_wand"));
    Caster caster(wand);
    ProjectileSystem bolts;
    Spread s2;
    float maxBloom = 0.0f;
    std::vector<float> cones;
    for (int tick = 0; tick < 120; ++tick) {
        s2.tick(kDt);
        if (caster.tick(tick == 0, true, kDt, s2.apply(CastAim{}, wand.accuracy(), {}), bolts)) {
            cones.push_back(s2.lastConeDeg());
            s2.onCast();
        }
        maxBloom = std::max(maxBloom, s2.bloomDeg());
    }
    CHECK(caster.casts() == 1 && maxBloom == 1.0f);   // semi-auto without hold-to-repeat: one press
    CHECK(cones.size() == 1 && near(cones[0], 2.0f, 1e-6f));
    // Hold-to-repeat at the 0.1 s floor stacks: a cast every 6 ticks decays 0.8 deg < 1.
    WieldableDef fastDef = *t.find("swift_wind_wand");
    fastDef.cooldown = 0.1f;
    const WieldableInstance fast(fastDef);
    Caster rapid(fast);
    rapid.setHoldToRepeat(true);
    Spread s3;
    float rapidMax = 0.0f;
    for (int tick = 0; tick < 120; ++tick) {
        s3.tick(kDt);
        if (rapid.tick(tick == 0, true, kDt, s3.apply(CastAim{}, fast.accuracy(), {}), bolts)) s3.onCast();
        rapidMax = std::max(rapidMax, s3.bloomDeg());
    }
    CHECK(rapid.casts() >= 19 && rapidMax == st.bloomMaxDeg);
    n = 0;
    while (s3.bloomDeg() > 0.0f && n < 1000) { s3.tick(kDt); ++n; }
    CHECK(n <= 30);
    std::printf("bloom: rapid fire (%llu casts in 2 s) hit the %.1f deg cap, recovered in %d ticks\n",
                (unsigned long long)rapid.casts(), double(st.bloomMaxDeg), n);
}

void coneSampling() {
    // Directions fill the cap uniformly: all within the half-angle, the edge reached, and
    // the mean angle ~ 2/3 of the half-angle (small-angle uniform disc).
    Spread sp(SpreadTuning{}, 1234);
    const glm::vec3 dir = glm::normalize(glm::vec3(-0.5f, 0.2f, -1.0f));
    float maxA = 0.0f, sum = 0.0f;
    glm::vec3 mean(0.0f);
    const int n = 4000;
    for (int i = 0; i < n; ++i) {
        CastAim aim;
        aim.direction = dir;
        const CastAim out = sp.apply(aim, 50.0f, {});   // 2 deg
        CHECK(near(glm::length(out.direction), 1.0f, 1e-5f));
        const float a = angleDeg(out.direction, dir);
        maxA = std::max(maxA, a);
        sum += a;
        mean += out.direction;
    }
    const float meanA = sum / float(n);
    std::printf("cone: %d samples at 2.000 deg: max %.3f, mean %.3f deg (uniform ~1.333), centroid off by %.4f deg\n", n,
                double(maxA), double(meanA), double(angleDeg(mean, dir)));
    CHECK(maxA <= 2.0f + 1e-3f && maxA > 1.95f);
    CHECK(meanA > 1.25f && meanA < 1.42f);
    CHECK(angleDeg(mean, dir) < 0.1f);   // unbiased
    // Deterministic per seed.
    Spread a(SpreadTuning{}, 7), b(SpreadTuning{}, 7), c(SpreadTuning{}, 8);
    bool same = true, differs = false;
    for (int i = 0; i < 50; ++i) {
        const glm::vec3 da = a.apply(CastAim{}, 0.0f, {}).direction, db = b.apply(CastAim{}, 0.0f, {}).direction;
        const glm::vec3 dc = c.apply(CastAim{}, 0.0f, {}).direction;
        same = same && da == db;
        differs = differs || da != dc;
    }
    CHECK(same && differs);
    // Straight up/down (helper axis switch) stays inside the cone too.
    for (const glm::vec3 d : {glm::vec3(0, 1, 0), glm::vec3(0, -1, 0)})
        for (int i = 0; i < 100; ++i) CHECK(angleDeg(coneDirection(d, glm::radians(3.0f), float(i) / 100.0f, 0.37f), d) <= 3.0f + 1e-3f);
    // Spread bolts still land around the aim point: 200 Fire-staff casts at a 20 m wall.
    ph::PhysicsWorld w;
    ph::BoxDesc wall;
    wall.center = {0, 1.5f, -20.5f};
    wall.halfExtents = {10, 10, 0.5f};
    w.addStaticBox(wall);
    w.optimizeBroadPhase();
    const WieldableTable t = loadReal();
    const WieldableInstance staff(*t.find("apprentice_fire_staff"));
    ProjectileSystem bolts;
    Spread s2;
    std::vector<ProjectileHit> hits, all;
    for (int i = 0; i < 200; ++i) {
        ProjectileSpawn sp2;
        sp2.origin = {0, 1.5f, 0};
        CastAim aim;
        aim.origin = sp2.origin;
        sp2.direction = s2.apply(aim, staff.accuracy(), {}).direction;
        sp2.speed = staff.projectileSpeed();
        sp2.range = staff.range();
        bolts.spawn(sp2);
    }
    for (int i = 0; i < 120 && !bolts.live().empty(); ++i) { hits.clear(); bolts.tick(w, kDt, hits); all.insert(all.end(), hits.begin(), hits.end()); }
    float maxOff = 0.0f;
    for (const ProjectileHit& h : all) maxOff = std::max(maxOff, glm::length(glm::vec2(h.point.x, h.point.y - 1.5f)));
    const float limit = 20.0f * std::tan(glm::radians(2.0f));
    std::printf("cone: 200 fire-staff bolts at a 20 m wall, %zu hits, widest %.3f m off (cone edge %.3f m)\n", all.size(),
                double(maxOff), double(limit));
    CHECK(all.size() == 200 && maxOff <= limit + 0.01f && maxOff > 0.5f * limit);
}

} // namespace

int main() {
    cameraFov();
    focusTween();
    accuracyStat();
    zeroSpreadAtFullAccuracy();
    focusedIsPoint35Hip();
    stanceFromPlayer();
    bloomDecay();
    coneSampling();
    if (g_failures) { std::fprintf(stderr, "%d check(s) failed\n", g_failures); return 1; }
    std::puts("accuracy: all checks passed");
    return 0;
}
