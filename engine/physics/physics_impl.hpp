// SPDX-License-Identifier: Apache-2.0
// Private to engine/physics: the Jolt side of PhysicsWorld (layer tables, Impl), shared by
// physics.cpp and character.cpp. Never include this outside engine/physics (it pulls in Jolt).
#pragma once
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

#include <memory>

namespace coe::physics {

// Jolt's process-wide state (allocator hook, factory, registered types), ref-counted
// across every PhysicsWorld (physics.cpp).
void acquireJolt();
void releaseJolt();


inline JPH::Vec3 toJ(const glm::vec3& v) { return JPH::Vec3(v.x, v.y, v.z); }
inline JPH::Quat toJ(const glm::quat& q) { return JPH::Quat(q.x, q.y, q.z, q.w).Normalized(); }
inline glm::vec3 toG(JPH::Vec3Arg v) { return {v.GetX(), v.GetY(), v.GetZ()}; }
inline glm::quat toG(JPH::QuatArg q) { return glm::quat(q.GetW(), q.GetX(), q.GetY(), q.GetZ()); }
inline JPH::BodyID toJ(BodyHandle h) { return JPH::BodyID(h.id); }
inline BodyHandle toH(JPH::BodyID id) { return id.IsInvalid() ? BodyHandle{} : BodyHandle{id.GetIndexAndSequenceNumber()}; }

// Broad phase: one tree per object layer (static tree rebuilt rarely, moving tree updated every step).
namespace BroadLayers {
inline constexpr JPH::BroadPhaseLayer Static(0);
inline constexpr JPH::BroadPhaseLayer Moving(1);
inline constexpr JPH::uint Count = 2;
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

} // namespace coe::physics
