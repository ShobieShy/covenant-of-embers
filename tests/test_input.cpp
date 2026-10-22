// SPDX-License-Identifier: Apache-2.0
// Unit tests for engine/input (BUILD_PLAN step 9): synthetic SDL events -> actions,
// edges latched per fixed tick (no dropped/doubled presses), mouse look per frame.
// Plain checks; moves to doctest in step 20. Needs no SDL_Init / window.
#include "engine/core/fixed_timestep.hpp"
#include "engine/input/input.hpp"

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <set>
#include <string>

namespace {
int g_failures = 0;
#define CHECK(cond) do { if (!(cond)) { ++g_failures; \
    std::fprintf(stderr, "FAIL %s:%d: %s\n", __FILE__, __LINE__, #cond); } } while (0)

using coe::input::Action;
using coe::input::Binding;
using coe::input::InputState;
using coe::input::TickInput;

constexpr uint64_t kTickNs = coe::FixedTimestep::kNsPerSecond / 60;   // 16.67 ms (1/3 ns short of a tick)
// Shortest frame time that completes exactly n ticks from an empty accumulator.
constexpr uint64_t ticksNs(uint64_t n) { return (n * coe::FixedTimestep::kNsPerSecond + 59) / 60; }

SDL_Event keyEvent(SDL_Scancode sc, bool down, bool repeat = false) {
    SDL_Event e;
    std::memset(&e, 0, sizeof e);
    e.type = down ? SDL_EVENT_KEY_DOWN : SDL_EVENT_KEY_UP;
    e.key.scancode = sc;
    e.key.down = down;
    e.key.repeat = repeat;
    return e;
}
SDL_Event buttonEvent(uint8_t button, bool down) {
    SDL_Event e;
    std::memset(&e, 0, sizeof e);
    e.type = down ? SDL_EVENT_MOUSE_BUTTON_DOWN : SDL_EVENT_MOUSE_BUTTON_UP;
    e.button.button = button;
    e.button.down = down;
    return e;
}
SDL_Event motionEvent(float dx, float dy) {
    SDL_Event e;
    std::memset(&e, 0, sizeof e);
    e.type = SDL_EVENT_MOUSE_MOTION;
    e.motion.xrel = dx;
    e.motion.yrel = dy;
    return e;
}
SDL_Event focusLost() {
    SDL_Event e;
    std::memset(&e, 0, sizeof e);
    e.type = SDL_EVENT_WINDOW_FOCUS_LOST;
    return e;
}

// Mirrors game/main.cpp: events -> advance -> N x consumeTick -> takeLook.
struct Loop {
    coe::FixedTimestep step{60};
    InputState in;
    uint64_t presses[coe::input::kActionCount] = {};
    uint64_t releases[coe::input::kActionCount] = {};
    uint64_t ticks = 0;
    TickInput last;

    uint32_t frame(uint64_t frameNs) {
        uint32_t n = step.advance(frameNs);
        for (uint32_t i = 0; i < n; ++i) {
            last = in.consumeTick();
            ++ticks;
            for (size_t a = 0; a < coe::input::kActionCount; ++a) {
                presses[a] += last.pressCount[a];
                releases[a] += last.released[a];
                if (last.pressed[a]) CHECK(last.pressCount[a] >= 1);
            }
        }
        return n;
    }
};

void defaultMapNamesAndBindings() {
    std::set<std::string> names;
    for (size_t a = 0; a < coe::input::kActionCount; ++a) {
        const char* n = coe::input::actionName(static_cast<Action>(a));
        CHECK(std::strcmp(n, "?") != 0);
        names.insert(n);
        CHECK(!coe::input::ActionMap::defaults().bindings(static_cast<Action>(a)).empty());
    }
    CHECK(names.size() == coe::input::kActionCount);
    CHECK(coe::input::bindingName(Binding::key(SDL_SCANCODE_W)) == "W");
    CHECK(coe::input::bindingName(Binding::mouse(SDL_BUTTON_LEFT)) == "Mouse 1");
}

void eventsMapToActions() {
    InputState in;
    in.handleEvent(keyEvent(SDL_SCANCODE_W, true));
    in.handleEvent(buttonEvent(SDL_BUTTON_LEFT, true));
    in.handleEvent(buttonEvent(SDL_BUTTON_RIGHT, true));
    in.handleEvent(keyEvent(SDL_SCANCODE_LSHIFT, true));
    in.handleEvent(keyEvent(SDL_SCANCODE_3, true));
    in.handleEvent(keyEvent(SDL_SCANCODE_Z, true));          // unbound: ignored
    TickInput t = in.consumeTick();
    CHECK(t.down(Action::MoveForward) && t.wasPressed(Action::MoveForward));
    CHECK(t.down(Action::Fire) && t.wasPressed(Action::Fire));
    CHECK(t.down(Action::Aim));
    CHECK(t.down(Action::Sprint));
    CHECK(t.down(Action::Weapon3) && !t.down(Action::Weapon1));
    CHECK(t.held.count() == 5 && t.pressed.count() == 5);
    CHECK(t.moveForward() == 1.0f && t.moveRight() == 0.0f);
    in.handleEvent(keyEvent(SDL_SCANCODE_S, true));
    in.handleEvent(keyEvent(SDL_SCANCODE_D, true));
    t = in.consumeTick();
    CHECK(t.moveForward() == 0.0f && t.moveRight() == 1.0f);
    CHECK(t.pressed.count() == 2);                            // only the new ones
    in.handleEvent(buttonEvent(SDL_BUTTON_LEFT, false));
    t = in.consumeTick();
    CHECK(!t.down(Action::Fire) && t.wasReleased(Action::Fire) && !t.wasPressed(Action::Fire));
}

void tapAcrossZeroTickFramesIsNotDropped() {
    Loop l;
    CHECK(l.frame(ticksNs(1)) == 1);                           // 1 tick, nothing pressed
    l.in.handleEvent(keyEvent(SDL_SCANCODE_SPACE, true));
    CHECK(l.frame(kTickNs / 4) == 0);                          // 0 ticks: edge must survive
    l.in.handleEvent(keyEvent(SDL_SCANCODE_SPACE, false));    // released before any tick ran
    CHECK(l.frame(kTickNs / 4) == 0);
    CHECK(l.frame(kTickNs / 2 + 10) == 1);                    // the frames add up to one tick
    CHECK(l.last.wasPressed(Action::Jump) && l.last.wasReleased(Action::Jump));
    CHECK(!l.last.down(Action::Jump));
    CHECK(l.presses[size_t(Action::Jump)] == 1);
    l.frame(ticksNs(3));
    CHECK(l.presses[size_t(Action::Jump)] == 1);               // consumed exactly once
    CHECK(l.releases[size_t(Action::Jump)] == 1);
}

void pressInMultiTickFrameIsNotDoubled() {
    Loop l;
    l.in.handleEvent(buttonEvent(SDL_BUTTON_LEFT, true));
    CHECK(l.frame(ticksNs(2)) == 2);                      // one frame, 2 ticks
    CHECK(l.presses[size_t(Action::Fire)] == 1);
    CHECK(l.last.down(Action::Fire) && !l.last.wasPressed(Action::Fire));   // 2nd tick: held only
    CHECK(l.frame(ticksNs(5)) == 5);
    CHECK(l.presses[size_t(Action::Fire)] == 1);
    l.in.handleEvent(buttonEvent(SDL_BUTTON_LEFT, false));
    CHECK(l.frame(ticksNs(3)) == 3);
    CHECK(l.releases[size_t(Action::Fire)] == 1);
}

void doubleTapBetweenTicksCountsTwice() {
    InputState in;
    for (int i = 0; i < 2; ++i) {
        in.onKey(SDL_SCANCODE_R, true);
        in.onKey(SDL_SCANCODE_R, false);
    }
    TickInput t = in.consumeTick();
    CHECK(t.wasPressed(Action::Reload) && t.pressCount[size_t(Action::Reload)] == 2);
    CHECK(in.consumeTick().pressCount[size_t(Action::Reload)] == 0);
}

void repeatsAndMultiBindings() {
    InputState in;
    in.handleEvent(keyEvent(SDL_SCANCODE_C, true));
    for (int i = 0; i < 5; ++i) in.handleEvent(keyEvent(SDL_SCANCODE_C, true, /*repeat*/ true));
    TickInput t = in.consumeTick();
    CHECK(t.pressCount[size_t(Action::Crouch)] == 1);
    in.handleEvent(keyEvent(SDL_SCANCODE_LCTRL, true));       // second Crouch key: no new edge
    in.handleEvent(keyEvent(SDL_SCANCODE_C, false));          // still held via LCtrl
    t = in.consumeTick();
    CHECK(t.down(Action::Crouch) && !t.wasPressed(Action::Crouch) && !t.wasReleased(Action::Crouch));
    in.handleEvent(keyEvent(SDL_SCANCODE_LCTRL, false));
    t = in.consumeTick();
    CHECK(!t.down(Action::Crouch) && t.wasReleased(Action::Crouch));
}

void focusLossReleasesEverything() {
    InputState in;
    in.handleEvent(keyEvent(SDL_SCANCODE_W, true));
    in.handleEvent(buttonEvent(SDL_BUTTON_RIGHT, true));
    in.consumeTick();
    in.handleEvent(focusLost());
    TickInput t = in.consumeTick();
    CHECK(t.held.none());
    CHECK(t.wasReleased(Action::MoveForward) && t.wasReleased(Action::Aim));
    in.handleEvent(keyEvent(SDL_SCANCODE_W, false));          // late key-up: no stray edge
    CHECK(in.consumeTick().released.none());
}

void rebindJump() {
    coe::input::ActionMap m = coe::input::ActionMap::defaults();
    m.clear(Action::Jump);
    m.bind(Action::Jump, Binding::mouse(SDL_BUTTON_X1));
    m.bind(Action::Jump, Binding::mouse(SDL_BUTTON_X1));      // duplicate ignored
    CHECK(m.bindings(Action::Jump).size() == 1);
    InputState in(m);
    in.handleEvent(keyEvent(SDL_SCANCODE_SPACE, true));
    CHECK(!in.consumeTick().down(Action::Jump));
    in.handleEvent(buttonEvent(SDL_BUTTON_X1, true));
    CHECK(in.consumeTick().wasPressed(Action::Jump));
    in.handleEvent(buttonEvent(200, true));                    // out-of-range button: ignored
    CHECK(in.consumeTick().pressed.none());
}

void mouseLookIsPerFrame() {
    Loop l;
    l.in.handleEvent(motionEvent(3.0f, -1.0f));
    l.in.handleEvent(motionEvent(2.5f, 4.0f));
    CHECK(l.frame(kTickNs / 4) == 0);                          // no tick ran: look still applies
    coe::input::LookDelta d = l.in.takeLook();
    CHECK(d.dx == 5.5f && d.dy == 3.0f);
    d = l.in.takeLook();
    CHECK(d.dx == 0.0f && d.dy == 0.0f);
    l.in.handleEvent(motionEvent(1.0f, 1.0f));
    CHECK(l.frame(ticksNs(3)) == 3);                          // ticks never consume look
    d = l.in.takeLook();
    CHECK(d.dx == 1.0f && d.dy == 1.0f);
}

// Every tap generated by a jittered render loop is seen by exactly one tick.
void jitteredLoopNeverDropsOrDoubles() {
    for (uint32_t seed : {1u, 42u, 9001u}) {
        Loop l;
        uint64_t taps = 0, framesWith0 = 0, framesWith2 = 0;
        for (int f = 0; f < 4000; ++f) {
            seed = seed * 1664525u + 1013904223u;
            if ((seed >> 20) % 3 == 0) {                       // tap Interact within this frame
                l.in.onKey(SDL_SCANCODE_F, true);
                l.in.onKey(SDL_SCANCODE_F, false);
                ++taps;
            }
            uint64_t ns = 1'000'000ull + (seed >> 8) % 40'000'000ull;   // 1..41 ms
            uint32_t n = l.frame(ns);
            framesWith0 += n == 0;
            framesWith2 += n >= 2;
        }
        l.frame(ticksNs(1));                                   // flush the last latched edge
        CHECK(framesWith0 > 0 && framesWith2 > 0);
        CHECK(l.presses[size_t(Action::Interact)] == taps);
        CHECK(l.releases[size_t(Action::Interact)] <= taps);
    }
}
} // namespace

int main() {
    defaultMapNamesAndBindings();
    eventsMapToActions();
    tapAcrossZeroTickFramesIsNotDropped();
    pressInMultiTickFrameIsNotDoubled();
    doubleTapBetweenTicksCountsTwice();
    repeatsAndMultiBindings();
    focusLossReleasesEverything();
    rebindJump();
    mouseLookIsPerFrame();
    jitteredLoopNeverDropsOrDoubles();
    std::printf("test_input: %s (%d failures)\n", g_failures ? "FAIL" : "PASS", g_failures);
    return g_failures ? 1 : 0;
}
