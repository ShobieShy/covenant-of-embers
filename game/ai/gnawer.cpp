// SPDX-License-Identifier: Apache-2.0
#include "game/ai/gnawer.hpp"

#include <algorithm>
#include <cmath>

namespace coe::game {

namespace {

constexpr std::uint32_t kStaticMask = physics::Layers::bit(physics::Layers::Static);
constexpr float kSkin = 0.02f;          // stays this far off walls
constexpr float kGroundProbe = 0.05f;   // radius of the feet sweep
constexpr float kBiteHeight = 1.2f;     // |player feet - its feet| it can still bite across

glm::vec3 flat(const glm::vec3& v) { return {v.x, 0.0f, v.z}; }

// Yaw (degrees, 0 = facing -Z) that faces horizontal direction d.
float yawFacing(const glm::vec3& d) { return glm::degrees(std::atan2(-d.x, -d.z)); }

float turnToward(float from, float to, float maxStep) {
    float diff = std::fmod(to - from + 540.0f, 360.0f) - 180.0f;
    diff = std::clamp(diff, -maxStep, maxStep);
    float r = from + diff;
    if (r > 180.0f) r -= 360.0f;
    if (r < -180.0f) r += 360.0f;
    return r;
}

}  // namespace

const char* gnawerStateName(GnawerState s) {
    switch (s) {
        case GnawerState::Idle: return "idle";
        case GnawerState::Detect: return "detect";
        case GnawerState::Chase: return "chase";
        case GnawerState::Attack: return "attack";
        case GnawerState::Knockback: return "knockback";
        case GnawerState::Dead: return "dead";
    }
    return "?";
}

GnawerState nextGnawerState(GnawerState s, const RusherDef& d, const GnawerSenses& in) {
    if (s == GnawerState::Dead || in.dead) return GnawerState::Dead;
    if (in.knockbackLeft > 0.0f) return GnawerState::Knockback;
    if (!in.targetValid) return GnawerState::Idle;
    const float dist = in.distance;
    switch (s) {
        case GnawerState::Knockback:   // a hit always leaves it aggressive
            return dist <= d.attackRange ? GnawerState::Attack : GnawerState::Chase;
        case GnawerState::Idle:
            if (in.provoked) return GnawerState::Chase;
            return dist <= d.detectRange && in.lineOfSight ? GnawerState::Detect : GnawerState::Idle;
        case GnawerState::Detect:
            if (in.provoked) return GnawerState::Chase;
            if (dist > d.detectRange || !in.lineOfSight) return GnawerState::Idle;
            return dist <= d.aggroRange ? GnawerState::Chase : GnawerState::Detect;
        case GnawerState::Chase:   // a rusher keeps coming without sight; it gives up out of detect range
            if (dist > d.detectRange && !in.hunting) return GnawerState::Idle;
            return dist <= d.attackRange ? GnawerState::Attack : GnawerState::Chase;
        case GnawerState::Attack:
            return dist > d.attackRange + kGnawerAttackSlack ? GnawerState::Chase : GnawerState::Attack;
        case GnawerState::Dead: break;
    }
    return GnawerState::Dead;
}

GnawerAI::GnawerAI(physics::PhysicsWorld& world, EnemySystem& enemies) : world_(world), enemies_(enemies) {}

std::size_t GnawerAI::adoptAll() {
    std::size_t added = 0;
    for (const Enemy& e : enemies_.enemies()) {
        if (e.dead || !e.def->ai || agent(e.id)) continue;
        GnawerAgent a;
        a.enemy = e.id;
        agents_.push_back(a);
        ++added;
    }
    return added;
}

const GnawerAgent* GnawerAI::agent(std::uint32_t enemy) const {
    for (const GnawerAgent& a : agents_)
        if (a.enemy == enemy) return &a;
    return nullptr;
}

void GnawerAI::onHit(const EnemyHit& hit) {
    for (GnawerAgent& a : agents_) {
        if (a.enemy != hit.enemy || a.fsm.state() == GnawerState::Dead) continue;
        const Enemy* e = enemies_.find(a.enemy);
        if (!e || e->dead || !e->def->ai) return;
        a.provoked = true;
        a.huntLeft = kGnawerHuntTime;
        const RusherDef& d = *e->def->ai;
        if (hit.result.amount > d.knockbackThreshold && d.knockbackTime > 0.0f && d.knockbackStrength > 0.0f) {
            glm::vec3 dir = flat(hit.direction);
            if (glm::length(dir) < 1e-4f) dir = flat(e->feet - hit.point);
            if (glm::length(dir) < 1e-4f) dir = {0.0f, 0.0f, 1.0f};
            a.knockbackDir = glm::normalize(dir);
            a.knockbackLeft = d.knockbackTime;   // a new hit restarts it
            ++a.knockbacks;
        }
        return;
    }
}

bool GnawerAI::sees(const glm::vec3& eye, const glm::vec3& targetEye) const {
    const glm::vec3 delta = targetEye - eye;
    if (glm::length(delta) < 1e-4f) return true;
    return !world_.castSphere(eye, delta, kGroundProbe, {}, kStaticMask).has_value();
}

// Horizontal move swept against Static geometry (a sphere riding kStepUp above the feet,
// so low steps and ramps pass under it); the leftover slides along what it hit.
glm::vec3 GnawerAI::slide(const glm::vec3& feet, glm::vec3 delta, float radius, glm::vec3* blockNormal) const {
    glm::vec3 pos = feet;
    const glm::vec3 lift(0.0f, kStepUp + radius, 0.0f);
    for (int i = 0; i < 3; ++i) {
        const float len = glm::length(delta);
        if (len < 1e-5f) break;
        const auto h = world_.castSphere(pos + lift, delta, radius, {}, kStaticMask);
        if (!h) {
            pos += delta;
            break;
        }
        glm::vec3 n = flat(h->normal);
        if (glm::length(n) < 1e-4f) break;   // a floor/ceiling contact: stop rather than guess
        n = glm::normalize(n);
        if (blockNormal && i == 0) *blockNormal = n;
        if (h->fraction <= 0.0f && glm::dot(delta, n) >= 0.0f) {   // touching, moving away
            pos += delta;
            break;
        }
        const float f = std::max(0.0f, h->fraction - kSkin / len);
        pos += delta * f;
        const glm::vec3 rest = delta * (1.0f - f);
        delta = rest - n * glm::dot(rest, n);
    }
    return pos;
}

// Straight at the player; when that is mostly blocked (< half the step made), skirt the
// blocking wall along its tangent (the side nearer the player, else the last side) and
// keep doing so until kGnawerDetourTime after the last block.
glm::vec3 GnawerAI::steer(const glm::vec3& feet, const glm::vec3& dir, float len, float radius, GnawerAgent& a,
                          float dt) const {
    a.detourLeft = std::max(0.0f, a.detourLeft - dt);
    glm::vec3 want = dir;
    if (a.detourLeft > 0.0f) want = glm::normalize(dir + a.detourDir * 2.0f);
    glm::vec3 n(0.0f);
    glm::vec3 pos = slide(feet, want * len, radius, &n);
    if (glm::length(flat(pos - feet)) < 0.5f * len && glm::length(n) > 0.5f) {
        glm::vec3 t(n.z, 0.0f, -n.x);
        const float side = glm::dot(t, dir);
        if (std::abs(side) > 0.05f) {
            if (side < 0.0f) t = -t;
        } else if (a.detourLeft > 0.0f && glm::dot(t, a.detourDir) < 0.0f) {
            t = -t;   // head-on: keep the side it already chose
        }
        a.detourDir = t;
        a.detourLeft = kGnawerDetourTime;
        pos = slide(feet, glm::normalize(dir * 0.25f + t) * len, radius);
    }
    return pos;
}

// Feet follow the ground: snapped onto anything walkable from kStepUp above to kStepDown
// (or this tick's fall) below, else falling with gravity.
glm::vec3 GnawerAI::settle(const glm::vec3& feet, GnawerAgent& a, float dt) const {
    glm::vec3 pos = feet;
    const float fall = std::max(kStepDown, a.verticalSpeed < 0.0f ? -a.verticalSpeed * dt + kStepDown : 0.0f);
    const glm::vec3 from = pos + glm::vec3(0.0f, kStepUp + kGroundProbe, 0.0f);
    const auto g = world_.castSphere(from, {0.0f, -(kStepUp + fall), 0.0f}, kGroundProbe, {}, kStaticMask);
    if (g && g->normal.y > 0.5f && g->fraction > 0.0f) {
        pos.y = g->point.y;
        a.verticalSpeed = 0.0f;
        a.grounded = true;
    } else {
        a.verticalSpeed -= kGravity * dt;
        pos.y += a.verticalSpeed * dt;
        a.grounded = false;
    }
    return pos;
}

void GnawerAI::tick(float dt, const AITarget& target) {
    ++ticks_;
    for (GnawerAgent& a : agents_) {
        const Enemy* e = enemies_.find(a.enemy);
        const GnawerState before = a.fsm.state();
        if (before == GnawerState::Dead) continue;   // dead enemies stop thinking
        a.fsm.tick(dt);
        if (!e || e->dead || !e->def->ai) {
            a.fsm.set(GnawerState::Dead);
            transitions_.push_back({a.enemy, before, GnawerState::Dead, a.distance, ticks_});
            continue;
        }
        const RusherDef& d = *e->def->ai;
        a.attackTimer = std::max(0.0f, a.attackTimer - dt);
        a.huntLeft = std::max(0.0f, a.huntLeft - dt);

        // Sense.
        GnawerSenses in;
        in.targetValid = target.valid;
        const glm::vec3 toTarget = flat(target.feet - e->feet);
        in.distance = glm::length(toTarget);
        a.distance = in.distance;
        if (target.valid && in.distance <= d.detectRange) {
            const glm::vec3 eye = e->feet + glm::vec3(0.0f, e->def->size.y * 0.8f, 0.0f);
            in.lineOfSight = sees(eye, target.feet + glm::vec3(0.0f, target.eyeHeight, 0.0f));
        } else {
            in.lineOfSight = false;
        }
        in.provoked = a.provoked;
        in.hunting = a.huntLeft > 0.0f;
        in.knockbackLeft = a.knockbackLeft;
        a.provoked = false;

        // Decide.
        const GnawerState next = nextGnawerState(before, d, in);
        if (a.fsm.set(next)) transitions_.push_back({a.enemy, before, next, in.distance, ticks_});

        // Act.
        const float halfBody = 0.5f * std::max(e->def->size.x, e->def->size.z);
        const float radius = std::max(0.05f, 0.5f * std::min(e->def->size.x, e->def->size.z) - kSkin);
        // Closes to 90 % of the bite range, never into the player's capsule.
        const float stopAt = std::max(d.attackRange * 0.9f, halfBody + target.radius + 0.05f);
        const glm::vec3 dir = in.distance > 1e-4f ? toTarget / in.distance : glm::vec3(0.0f);
        float yaw = e->yawDeg;
        glm::vec3 move(0.0f);
        float walk = 0.0f;   // metres toward the player this tick (steered)
        switch (next) {
            case GnawerState::Idle:
            case GnawerState::Dead: break;
            case GnawerState::Detect:
            case GnawerState::Chase:
            case GnawerState::Attack: {
                if (in.distance > 1e-4f) yaw = turnToward(yaw, yawFacing(dir), d.turnRateDeg * dt);
                const float speed = next == GnawerState::Detect ? d.walkSpeed : d.sprintSpeed;
                walk = std::min(speed * dt, std::max(0.0f, in.distance - stopAt));
                break;
            }
            case GnawerState::Knockback: {
                // Linear decay from knockback_strength to 0 over knockback_time (sampled
                // mid-tick, so the push totals exactly strength x time / 2).
                const float mid = std::max(0.0f, a.knockbackLeft - 0.5f * dt);
                const float k = d.knockbackTime > 0.0f ? mid / d.knockbackTime : 0.0f;
                move = a.knockbackDir * (d.knockbackStrength * k * dt);
                a.knockbackLeft = std::max(0.0f, a.knockbackLeft - dt);
                break;
            }
        }

        // (1e-4 s slack: 0.8 - 48 x 1/60 is not exactly 0 in floats.)
        if (next == GnawerState::Attack && a.attackTimer <= 1e-4f && in.distance <= d.attackRange + kGnawerAttackSlack &&
            std::abs(target.feet.y - e->feet.y) <= kBiteHeight) {
            EnemyAttack at;
            at.enemy = a.enemy;
            at.def = e->def;
            at.damage = d.attackDamage;
            at.element = e->def->affinity;
            at.from = e->feet;
            at.dodged = target.invulnerable;
            if (at.dodged)
                ++a.dodged;
            else
                ++a.bites;
            a.attackTimer = d.attackCooldown;
            attacks_.push_back(at);
        }

        glm::vec3 feet = e->feet;
        if (walk > 1e-6f && in.distance > 1e-4f) feet = steer(feet, dir, walk, radius, a, dt);
        if (glm::length(move) > 1e-6f) feet = slide(feet, move, radius);
        feet = settle(feet, a, dt);
        a.travelled += glm::length(flat(feet - e->feet));
        // Every tick, even standing still: moveKinematic sets the velocity that reaches the pose
        // in one step, and a kinematic body keeps the last one (it would drift on).
        enemies_.place(a.enemy, feet, yaw, dt);
    }
}

std::vector<EnemyAttack> GnawerAI::takeAttacks() {
    std::vector<EnemyAttack> out;
    out.swap(attacks_);
    return out;
}

std::vector<GnawerTransition> GnawerAI::takeTransitions() {
    std::vector<GnawerTransition> out;
    out.swap(transitions_);
    return out;
}

}  // namespace coe::game
