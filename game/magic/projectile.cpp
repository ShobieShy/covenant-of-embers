// SPDX-License-Identifier: Apache-2.0
#include "game/magic/projectile.hpp"

#include <algorithm>
#include <cmath>
#include <optional>

namespace coe::game {
// Tracer from max(kSkipNear, d - kTail) to d metres along the bolt's ray.
// With a visualOffset (step 21) it starts at the cast point and the offset fades
// linearly to 0 over kConverge m, so the line meets the eye ray where the bolt can hit.
bool ProjectileSystem::tracer(const ProjectileSpawn& s, float d, DebugLine& out) const {
    const bool offset = glm::dot(s.visualOffset, s.visualOffset) > 1e-8f;
    const float from = std::max(offset ? 0.0f : kSkipNear, d - kTail);
    if (d <= from) return false;
    const auto at = [&](float t) {
        return s.origin + s.direction * t + s.visualOffset * std::max(0.0f, 1.0f - t / kConverge);
    };
    out = {at(from), at(d), elements_ ? elements_->color(s.element) : glm::vec3(1.0f)};
    return true;
}

std::uint32_t ProjectileSystem::spawn(const ProjectileSpawn& s) {
    Projectile p;
    p.id = nextId_++;
    p.spawn = s;
    const float len = glm::length(s.direction);
    p.spawn.direction = len > 1e-6f ? s.direction / len : glm::vec3(0.0f, 0.0f, -1.0f);
    p.position = p.previous = s.origin;
    live_.push_back(p);
    ++spawned_;
    return p.id;
}

void ProjectileSystem::tick(const physics::PhysicsWorld& world, float dt, std::vector<ProjectileHit>& hits) {
    for (Impact& i : impacts_) i.ttl -= dt;
    std::erase_if(impacts_, [](const Impact& i) { return i.ttl <= 0.0f; });

    for (Projectile& p : live_) {
        const ProjectileSpawn& s = p.spawn;
        const float seg = std::min(s.speed * dt, s.range - p.travelled);
        p.previous = p.position;
        if (seg <= 0.0f) { ++fizzled_; p.ticks = -1; continue; }   // (range 0; not reached normally)
        const glm::vec3 from = s.origin + s.direction * p.travelled;
        const glm::vec3 delta = s.direction * seg;
        std::optional<physics::RayHit> h = world.castRay(from, delta, s.ignore);
        bool grazed = false;
        if (s.radius > 0.0f) {
            // Enemies only: a sphere touching one no later than the ray's own hit wins.
            // When the ray itself hits that body, its exact on-ray point is kept.
            const auto e = world.castSphere(from, delta, s.radius, s.ignore, physics::Layers::bit(physics::Layers::Enemy));
            if (e && (!h || (e->body != h->body && e->fraction <= h->fraction))) {
                grazed = true;
                h = e;
            }
        }
        if (h) {
            ProjectileHit out;
            out.grazed = grazed;
            out.projectile = p.id;
            out.body = h->body;
            out.point = h->point;
            out.normal = h->normal;
            out.distance = p.travelled + h->fraction * seg;
            out.time = float(p.ticks) * dt + h->fraction * seg / s.speed;
            out.tick = p.ticks + 1;
            out.element = s.element;
            out.damage = s.damage;
            hits.push_back(out);
            ++hits_;
            DebugLine l;
            if (tracer(s, out.distance, l)) impacts_.push_back({l, kImpactLinger});
            p.ticks = -1;   // done
            continue;
        }
        p.travelled += seg;
        p.position = from + delta;
        ++p.ticks;
        if (p.travelled >= s.range - 1e-4f) { ++fizzled_; p.ticks = -1; }
    }
    std::erase_if(live_, [](const Projectile& p) { return p.ticks < 0; });
}

void ProjectileSystem::debugLines(float alpha, std::vector<DebugLine>& out) const {
    for (const Projectile& p : live_) {
        // Interpolate the head between the last two tick positions.
        const float dPrev = glm::length(p.previous - p.spawn.origin);
        const float d = dPrev + (p.travelled - dPrev) * std::clamp(alpha, 0.0f, 1.0f);
        DebugLine l;
        if (tracer(p.spawn, d, l)) out.push_back(l);
    }
    for (const Impact& i : impacts_) out.push_back(i.line);
}

} // namespace coe::game
