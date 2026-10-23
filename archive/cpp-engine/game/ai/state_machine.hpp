// SPDX-License-Identifier: Apache-2.0
// A tiny finite-state machine for enemy brains (BUILD_PLAN step 23, PLAN §7).
// Holds the current state, how long it has been held (advanced by tick(dt) on the fixed
// 60 Hz step), the previous state and a change counter. The rules that pick the next
// state live with each brain (game/ai/gnawer.*) as pure functions so they can be unit
// tested without physics; this class only does the bookkeeping. Header-only.
#pragma once
#include <cstdint>

namespace coe::game {

template <class State>
class StateMachine {
public:
    explicit StateMachine(State initial = State{}) : state_(initial), previous_(initial) {}

    State state() const { return state_; }
    State previous() const { return previous_; }
    float timeInState() const { return time_; }        // seconds since the last change
    std::uint32_t changes() const { return changes_; }

    // Switches to `next`; false (and nothing changes, the timer keeps running) when already there.
    bool set(State next) {
        if (next == state_) return false;
        previous_ = state_;
        state_ = next;
        time_ = 0.0f;
        ++changes_;
        return true;
    }
    void tick(float dt) { time_ += dt; }

private:
    State state_;
    State previous_;
    float time_ = 0.0f;
    std::uint32_t changes_ = 0;
};

}  // namespace coe::game
