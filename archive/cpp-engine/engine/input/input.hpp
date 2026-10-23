// SPDX-License-Identifier: Apache-2.0
// Input layer (BUILD_PLAN step 9): SDL3 keyboard/mouse -> game actions.
//
// Timing contract with the fixed-timestep loop (engine/core/fixed_timestep):
//   * handleEvent() is fed every SDL event, once per render frame.
//   * consumeTick() is called once per fixed tick. It returns the held state of
//     every action plus the press/release edges latched since the previous tick,
//     then clears the edges. A frame that runs 0 ticks therefore keeps its edges
//     for the next tick (a tap is never dropped) and a frame that runs 2+ ticks
//     only reports the edge to the first one (a press is never doubled). A press
//     and release that both land between two ticks still shows up as pressed
//     (and released) even though the action is no longer held.
//   * takeLook() is called once per render frame and returns the mouse motion
//     accumulated since the previous frame. Mouse look is applied per frame for
//     latency, never per tick, so it does not depend on how many ticks ran.
//
// Bindings are physical keys (SDL scancodes, layout-independent like Magewar's
// physical_keycode actions) and mouse buttons; an action can have several
// bindings and is held while any of them is down. Key auto-repeat is ignored.
// Rebinding/config files arrive in step 39 (engine/input/bindings.*).
#pragma once
#include <SDL3/SDL_events.h>
#include <SDL3/SDL_scancode.h>

#include <array>
#include <bitset>
#include <cstdint>
#include <string>
#include <vector>

namespace coe::input {

enum class Action : uint8_t {
    MoveForward, MoveBack, MoveLeft, MoveRight,
    Jump, Fire, Aim, Reload, Sprint, Dash, Crouch, Interact,
    Weapon1, Weapon2, Weapon3, Weapon4,
    Count
};
inline constexpr size_t kActionCount = static_cast<size_t>(Action::Count);

const char* actionName(Action a);

struct Binding {
    enum class Kind : uint8_t { Key, MouseButton };
    Kind kind = Kind::Key;
    uint32_t code = 0;   // SDL_Scancode for Key, SDL_BUTTON_* (1-based) for MouseButton

    static Binding key(SDL_Scancode s) { return {Kind::Key, static_cast<uint32_t>(s)}; }
    static Binding mouse(uint8_t button) { return {Kind::MouseButton, button}; }
    bool operator==(const Binding&) const = default;
};
std::string bindingName(const Binding& b);   // "W", "Mouse 1", ...

class ActionMap {
public:
    // Default keyboard/mouse layout (WASD, Space, LMB/RMB, R, LShift, Q, C/LCtrl, F, 1-4).
    static ActionMap defaults();

    void bind(Action a, Binding b);          // adds (no duplicates)
    void clear(Action a);
    const std::vector<Binding>& bindings(Action a) const { return map_[static_cast<size_t>(a)]; }

private:
    std::array<std::vector<Binding>, kActionCount> map_{};
};

// What one fixed tick sees.
struct TickInput {
    std::bitset<kActionCount> held;       // down at the time the tick runs
    std::bitset<kActionCount> pressed;    // went down since the previous tick
    std::bitset<kActionCount> released;   // went up since the previous tick
    std::array<uint8_t, kActionCount> pressCount{};   // presses since the previous tick (saturating)

    bool down(Action a) const { return held[static_cast<size_t>(a)]; }
    bool wasPressed(Action a) const { return pressed[static_cast<size_t>(a)]; }
    bool wasReleased(Action a) const { return released[static_cast<size_t>(a)]; }
    // -1..1 axes from the four Move actions (forward/right positive).
    float moveForward() const { return float(down(Action::MoveForward)) - float(down(Action::MoveBack)); }
    float moveRight() const { return float(down(Action::MoveRight)) - float(down(Action::MoveLeft)); }
};

struct LookDelta {
    float dx = 0.0f, dy = 0.0f;   // relative mouse motion in mouse counts since the last frame
};

class InputState {
public:
    explicit InputState(ActionMap map = ActionMap::defaults());

    // Per render frame: feed every SDL event (non-input events are ignored).
    void handleEvent(const SDL_Event& e);

    // Raw entry points (handleEvent forwards here; tests may call them directly).
    void onKey(SDL_Scancode sc, bool down, bool repeat = false);
    void onMouseButton(uint8_t button, bool down);
    void onMouseMotion(float dx, float dy);
    // Window lost focus: every held action is released (edges latched), so keys
    // let go while unfocused can't stay stuck down.
    void releaseAll();

    // Per fixed tick: held state + latched edges; clears the edges.
    TickInput consumeTick();
    // Per render frame: accumulated mouse look; clears it.
    LookDelta takeLook();

    bool held(Action a) const { return held_[static_cast<size_t>(a)]; }
    const ActionMap& map() const { return map_; }
    void setMap(ActionMap map);

private:
    static constexpr size_t kMaxButtons = 8;   // SDL_BUTTON_LEFT..X2 and spares
    void refresh();                            // recompute held_ from sources, latch edges

    ActionMap map_;
    std::bitset<SDL_SCANCODE_COUNT> keys_;
    std::bitset<kMaxButtons + 1> buttons_;
    std::bitset<kActionCount> held_;
    std::bitset<kActionCount> pressed_, released_;
    std::array<uint8_t, kActionCount> pressCount_{};
    LookDelta look_;
};

} // namespace coe::input
