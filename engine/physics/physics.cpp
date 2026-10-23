// SPDX-License-Identifier: Apache-2.0
// Jolt-backed PhysicsWorld (see physics.hpp). The only translation unit that includes Jolt.
#include "engine/physics/physics.hpp"

// Jolt.h must come first (it sets up the JPH configuration macros).
#include <Jolt/Jolt.h>
#include <Jolt/Core/Factory.h>
#include <Jolt/Core/IssueReporting.h>
#include <Jolt/Core/JobSystemSingleThreaded.h>
#include <Jolt/Core/JobSystemThreadPool.h>
#include <Jolt/Core/TempAllocator.h>
#include <Jolt/Physics/Body/BodyCreationSettings.h>
#include <Jolt/Physics/Body/BodyLock.h>
#include <Jolt/Physics/Collision/CastResult.h>
#include <Jolt/Physics/Collision/RayCast.h>
#include <Jolt/Physics/Collision/Shape/BoxShape.h>
#include <Jolt/Physics/PhysicsSettings.h>
#include <Jolt/Physics/PhysicsSystem.h>
#include <Jolt/RegisterTypes.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <mutex>

namespace coe::physics {
namespace {

JPH::Vec3 toJ(const glm::vec3& v) { return JPH::Vec3(v.x, v.y, v.z); }
JPH::Quat toJ(const glm::quat& q) { return JPH::Quat(q.x, q.y, q.z, q.w).Normalized(); }
glm::vec3 toG(JPH::Vec3Arg v) { return {v.GetX(), v.GetY(), v.GetZ()}; }
glm::quat toG(JPH::QuatArg q) { return glm::quat(q.GetW(), q.GetX(), q.GetY(), q.GetZ()); }
JPH::BodyID toJ(BodyHandle h) { return JPH::BodyID(h.id); }
BodyHandle toH(JPH::BodyID id) { return id.IsInvalid() ? BodyHandle{} : BodyHandle{id.GetIndexAndSequenceNumber()}; }

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

// Broad phase: one tree per object layer (static tree rebuilt rarely, moving tree updated every step).
namespace BroadLayers {
constexpr JPH::BroadPhaseLayer Static(0);
constexpr JPH::BroadPhaseLayer Moving(1);
constexpr JPH::uint Count = 2;
} // namespace BroadLayers

class BroadPhaseLayers final : public JPH::BroadPhaseLayerInterface {
public:
    JPH::uint GetNumBroadPhaseLayers() const override { return BroadLayers::Count; }
    JPH::BroadPhaseLayer GetBroadPhaseLayer(JPH::ObjectLayer layer) const override {
        return layer == Layers::Static ? BroadLayers::Static : BroadLayers::Moving;
    }
#if defined(JPH_EXTERNAL_PROFILE) || defined(JPH_PROFILE_ENABLED)
    const char* GetBroadPhaseLayerName(JPH::BroadPhaseLayer layer) const override {
        return layer == BroadLayers::Static ? "Static" : "Moving";
    }
#endif
};

class ObjectVsBroadPhase final : public JPH::ObjectVsBroadPhaseLayerFilter {
public:
    bool ShouldCollide(JPH::ObjectLayer layer, JPH::BroadPhaseLayer bp) const override {
        if (layer == Layers::Static) return bp == BroadLayers::Moving;   // the level never tests itself
        return true;
    }
};

class ObjectPairs final : public JPH::ObjectLayerPairFilter {
public:
    bool ShouldCollide(JPH::ObjectLayer a, JPH::ObjectLayer b) const override {
        return !(a == Layers::Static && b == Layers::Static);
    }
};

} // namespace

const char* layerName(ObjectLayer layer) {
    switch (layer) {
    case Layers::Static: return "static";
    case Layers::Moving: return "moving";
    default: return "?";
    }
}

struct PhysicsWorld::Impl {
    explicit Impl(const WorldSettings& s) : settings(s) {
        acquireJolt();
        temp = std::make_unique<JPH::TempAllocatorImpl>(8u * 1024u * 1024u);
        if (s.workerThreads > 0)
            jobs = std::make_unique<JPH::JobSystemThreadPool>(JPH::cMaxPhysicsJobs, JPH::cMaxPhysicsBarriers, s.workerThreads);
        else
            jobs = std::make_unique<JPH::JobSystemSingleThreaded>(JPH::cMaxPhysicsJobs);
        system = std::make_unique<JPH::PhysicsSystem>();
        system->Init(s.maxBodies, 0, s.maxBodyPairs, s.maxContactConstraints, bpLayers, objVsBp, pairs);
        system->SetGravity(toJ(s.gravity));
    }
    ~Impl() {
        JPH::BodyInterface& bi = system->GetBodyInterface();
        JPH::BodyIDVector ids;
        system->GetBodies(ids);
        for (const JPH::BodyID& id : ids) {
            if (bi.IsAdded(id)) bi.RemoveBody(id);
            bi.DestroyBody(id);
        }
        system.reset();
        jobs.reset();
        temp.reset();
        releaseJolt();
    }

    BodyHandle addBox(const BoxDesc& d, JPH::EMotionType motion, ObjectLayer layer) {
        const glm::vec3 he = glm::max(d.halfExtents, glm::vec3(1e-3f));
        const float radius = std::min(JPH::cDefaultConvexRadius, std::min({he.x, he.y, he.z}));
        // Ref-counted: BodyCreationSettings takes a reference, so it must live on the heap.
        const JPH::Ref<JPH::BoxShapeSettings> shape = new JPH::BoxShapeSettings(toJ(he), radius);
        shape->SetDensity(d.density);
        JPH::BodyCreationSettings bcs(shape, JPH::RVec3(d.center.x, d.center.y, d.center.z), toJ(d.rotation), motion, layer);
        bcs.mFriction = d.friction;
        bcs.mRestitution = d.restitution;
        const JPH::EActivation act = motion == JPH::EMotionType::Static ? JPH::EActivation::DontActivate : JPH::EActivation::Activate;
        return toH(system->GetBodyInterface().CreateAndAddBody(bcs, act));
    }

    WorldSettings settings;
    BroadPhaseLayers bpLayers;
    ObjectVsBroadPhase objVsBp;
    ObjectPairs pairs;
    std::unique_ptr<JPH::TempAllocator> temp;
    std::unique_ptr<JPH::JobSystem> jobs;
    std::unique_ptr<JPH::PhysicsSystem> system;
    std::uint64_t steps = 0;
};

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
