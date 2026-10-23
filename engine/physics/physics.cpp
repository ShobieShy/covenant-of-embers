// SPDX-License-Identifier: Apache-2.0
// Jolt-backed PhysicsWorld (see physics.hpp). Jolt is only included by engine/physics
// (physics_impl.hpp, shared with character.cpp).
#include "engine/physics/physics_impl.hpp"

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <mutex>

namespace coe::physics {
namespace {

void traceImpl(const char* fmt, ...) {
    char buf[512];
    va_list args;
    va_start(args, fmt);
    std::vsnprintf(buf, sizeof buf, fmt, args);
    va_end(args);
    std::fprintf(stderr, "[physics] jolt: %s\n", buf);
}

#ifdef JPH_ENABLE_ASSERTS
bool assertFailedImpl(const char* expr, const char* msg, const char* file, JPH::uint line) {
    std::fprintf(stderr, "[physics] jolt assert %s:%u: (%s) %s\n", file, unsigned(line), expr, msg ? msg : "");
    std::fflush(stderr);
    return true;   // break (trap): a Jolt assert is a bug in our use of it
}
#endif

// Jolt's process-wide state (allocator hook, factory, registered types), shared by
// every PhysicsWorld and torn down with the last one.
std::mutex gJoltMutex;
int gJoltUsers = 0;

} // namespace

void acquireJolt() {
    std::lock_guard lock(gJoltMutex);
    if (gJoltUsers++ == 0) {
        JPH::RegisterDefaultAllocator();
        JPH::Trace = traceImpl;
        JPH_IF_ENABLE_ASSERTS(JPH::AssertFailed = assertFailedImpl;)
        JPH::Factory::sInstance = new JPH::Factory();
        JPH::RegisterTypes();
    }
}

void releaseJolt() {
    std::lock_guard lock(gJoltMutex);
    if (--gJoltUsers == 0) {
        JPH::UnregisterTypes();
        delete JPH::Factory::sInstance;
        JPH::Factory::sInstance = nullptr;
    }
}

const char* layerName(ObjectLayer layer) {
    switch (layer) {
    case Layers::Static: return "static";
    case Layers::Moving: return "moving";
    case Layers::Character: return "character";
    default: return "?";
    }
}

PhysicsWorld::PhysicsWorld(const WorldSettings& settings) : impl_(std::make_unique<Impl>(settings)) {}
PhysicsWorld::~PhysicsWorld() = default;

BodyHandle PhysicsWorld::addStaticBox(const BoxDesc& desc) {
    return impl_->addBox(desc, JPH::EMotionType::Static, desc.layer);
}

BodyHandle PhysicsWorld::addDynamicBox(const BoxDesc& desc) {
    return impl_->addBox(desc, JPH::EMotionType::Dynamic, Layers::Moving);
}

void PhysicsWorld::removeBody(BodyHandle body) {
    if (!body.valid()) return;
    JPH::BodyInterface& bi = impl_->system->GetBodyInterface();
    if (bi.IsAdded(toJ(body))) bi.RemoveBody(toJ(body));
    bi.DestroyBody(toJ(body));
}

void PhysicsWorld::optimizeBroadPhase() { impl_->system->OptimizeBroadPhase(); }

bool PhysicsWorld::step(float dt) {
    const JPH::EPhysicsUpdateError err = impl_->system->Update(dt, 1, impl_->temp.get(), impl_->jobs.get());
    ++impl_->steps;
    if (err != JPH::EPhysicsUpdateError::None) {
        std::fprintf(stderr, "[physics] step %llu: update error 0x%x\n", (unsigned long long)impl_->steps, unsigned(err));
        return false;
    }
    return true;
}

std::size_t PhysicsWorld::bodyCount() const { return impl_->system->GetNumBodies(); }
std::size_t PhysicsWorld::activeBodyCount() const {
    return impl_->system->GetNumActiveBodies(JPH::EBodyType::RigidBody);
}
std::uint64_t PhysicsWorld::steps() const { return impl_->steps; }

BodyState PhysicsWorld::state(BodyHandle body) const {
    BodyState s;
    JPH::BodyLockRead lock(impl_->system->GetBodyLockInterface(), toJ(body));
    if (!lock.Succeeded()) return s;
    const JPH::Body& b = lock.GetBody();
    const JPH::RVec3 p = b.GetPosition();
    s.position = glm::vec3(float(p.GetX()), float(p.GetY()), float(p.GetZ()));
    s.rotation = toG(b.GetRotation());
    s.linearVelocity = toG(b.GetLinearVelocity());
    s.angularVelocity = toG(b.GetAngularVelocity());
    s.active = b.IsActive();
    return s;
}

ObjectLayer PhysicsWorld::layer(BodyHandle body) const {
    return impl_->system->GetBodyInterface().GetObjectLayer(toJ(body));
}

glm::vec3 PhysicsWorld::halfExtents(BodyHandle body) const {
    JPH::BodyLockRead lock(impl_->system->GetBodyLockInterface(), toJ(body));
    if (!lock.Succeeded()) return glm::vec3(0.0f);
    const JPH::Shape* shape = lock.GetBody().GetShape();
    if (shape->GetSubType() != JPH::EShapeSubType::Box) return glm::vec3(0.0f);
    return toG(static_cast<const JPH::BoxShape*>(shape)->GetHalfExtent());
}

void PhysicsWorld::setLinearVelocity(BodyHandle body, const glm::vec3& v) {
    impl_->system->GetBodyInterface().SetLinearVelocity(toJ(body), toJ(v));
}

std::optional<RayHit> PhysicsWorld::castRay(const glm::vec3& origin, const glm::vec3& delta) const {
    const JPH::RRayCast ray(JPH::RVec3(origin.x, origin.y, origin.z), toJ(delta));
    JPH::RayCastResult hit;
    if (!impl_->system->GetNarrowPhaseQuery().CastRay(ray, hit)) return std::nullopt;
    RayHit out;
    out.body = toH(hit.mBodyID);
    out.fraction = hit.mFraction;
    const JPH::RVec3 p = ray.GetPointOnRay(hit.mFraction);
    out.point = glm::vec3(float(p.GetX()), float(p.GetY()), float(p.GetZ()));
    JPH::BodyLockRead lock(impl_->system->GetBodyLockInterface(), hit.mBodyID);
    if (lock.Succeeded()) out.normal = toG(lock.GetBody().GetWorldSpaceSurfaceNormal(hit.mSubShapeID2, p));
    return out;
}

} // namespace coe::physics
