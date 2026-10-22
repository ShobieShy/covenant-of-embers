// SPDX-License-Identifier: Apache-2.0
#include "engine/input/input.hpp"

#include <SDL3/SDL_keyboard.h>
#include <SDL3/SDL_mouse.h>

#include <algorithm>
#include <utility>

namespace coe::input {

const char* actionName(Action a) {
    switch (a) {
    case Action::MoveForward: return "MoveForward";
    case Action::MoveBack: return "MoveBack";
    case Action::MoveLeft: return "MoveLeft";
    case Action::MoveRight: return "MoveRight";
    case Action::Jump: return "Jump";
    case Action::Fire: return "Fire";
    case Action::Aim: return "Aim";
    case Action::Reload: return "Reload";
    case Action::Sprint: return "Sprint";
    case Action::Dash: return "Dash";
    case Action::Crouch: return "Crouch";
    case Action::Interact: return "Interact";
    case Action::Weapon1: return "Weapon1";
    case Action::Weapon2: return "Weapon2";
    case Action::Weapon3: return "Weapon3";
    case Action::Weapon4: return "Weapon4";
    case Action::Count: break;
    }
    return "?";
}

std::string bindingName(const Binding& b) {
    if (b.kind == Binding::Kind::MouseButton) return "Mouse " + std::to_string(b.code);
    const char* n = SDL_GetScancodeName(static_cast<SDL_Scancode>(b.code));
    return (n && *n) ? std::string(n) : "Scancode " + std::to_string(b.code);
}

ActionMap ActionMap::defaults() {
    // Mirrors the usual PC FPS layout (and Magewar's physical-key input map:
    // WASD, Space jump, C crouch, Shift sprint, R reload, 1-4 slots), with F as
    // Interact and Q as Dash (Magewar has no dash). LCtrl is a second Crouch key.
    ActionMap m;
    m.bind(Action::MoveForward, Binding::key(SDL_SCANCODE_W));
    m.bind(Action::MoveBack, Binding::key(SDL_SCANCODE_S));
    m.bind(Action::MoveLeft, Binding::key(SDL_SCANCODE_A));
    m.bind(Action::MoveRight, Binding::key(SDL_SCANCODE_D));
    m.bind(Action::Jump, Binding::key(SDL_SCANCODE_SPACE));
    m.bind(Action::Fire, Binding::mouse(SDL_BUTTON_LEFT));
    m.bind(Action::Aim, Binding::mouse(SDL_BUTTON_RIGHT));
    m.bind(Action::Reload, Binding::key(SDL_SCANCODE_R));
    m.bind(Action::Sprint, Binding::key(SDL_SCANCODE_LSHIFT));
    m.bind(Action::Dash, Binding::key(SDL_SCANCODE_Q));
    m.bind(Action::Crouch, Binding::key(SDL_SCANCODE_C));
    m.bind(Action::Crouch, Binding::key(SDL_SCANCODE_LCTRL));
    m.bind(Action::Interact, Binding::key(SDL_SCANCODE_F));
    m.bind(Action::Weapon1, Binding::key(SDL_SCANCODE_1));
    m.bind(Action::Weapon2, Binding::key(SDL_SCANCODE_2));
    m.bind(Action::Weapon3, Binding::key(SDL_SCANCODE_3));
    m.bind(Action::Weapon4, Binding::key(SDL_SCANCODE_4));
    return m;
}

void ActionMap::bind(Action a, Binding b) {
    auto& v = map_[static_cast<size_t>(a)];
    if (std::find(v.begin(), v.end(), b) == v.end()) v.push_back(b);
}

void ActionMap::clear(Action a) { map_[static_cast<size_t>(a)].clear(); }

InputState::InputState(ActionMap map) : map_(std::move(map)) {}

void InputState::setMap(ActionMap map) {
    map_ = std::move(map);
    refresh();
}

void InputState::handleEvent(const SDL_Event& e) {
    switch (e.type) {
    case SDL_EVENT_KEY_DOWN:
    case SDL_EVENT_KEY_UP:
        onKey(e.key.scancode, e.key.down, e.key.repeat);
        break;
    case SDL_EVENT_MOUSE_BUTTON_DOWN:
    case SDL_EVENT_MOUSE_BUTTON_UP:
        onMouseButton(e.button.button, e.button.down);
        break;
    case SDL_EVENT_MOUSE_MOTION:
        onMouseMotion(e.motion.xrel, e.motion.yrel);
        break;
    case SDL_EVENT_WINDOW_FOCUS_LOST:
        releaseAll();
        break;
    default:
        break;
    }
}

void InputState::onKey(SDL_Scancode sc, bool down, bool repeat) {
    if (repeat) return;
    const auto i = static_cast<size_t>(sc);
    if (i == 0 || i >= keys_.size() || keys_[i] == down) return;
    keys_[i] = down;
    refresh();
}

void InputState::onMouseButton(uint8_t button, bool down) {
    if (button == 0 || button > kMaxButtons || buttons_[button] == down) return;
    buttons_[button] = down;
    refresh();
}

void InputState::onMouseMotion(float dx, float dy) {
    look_.dx += dx;
    look_.dy += dy;
}

void InputState::releaseAll() {
    keys_.reset();
    buttons_.reset();
    refresh();
}

void InputState::refresh() {
    for (size_t a = 0; a < kActionCount; ++a) {
        bool now = false;
        for (const Binding& b : map_.bindings(static_cast<Action>(a))) {
            if (b.kind == Binding::Kind::Key) now = now || (b.code < keys_.size() && keys_[b.code]);
            else now = now || (b.code <= kMaxButtons && buttons_[b.code]);
        }
        if (now && !held_[a]) {
            pressed_[a] = true;
            if (pressCount_[a] < 255) ++pressCount_[a];
        } else if (!now && held_[a]) {
            released_[a] = true;
        }
        held_[a] = now;
    }
}

TickInput InputState::consumeTick() {
    TickInput t;
    t.held = held_;
    t.pressed = pressed_;
    t.released = released_;
    t.pressCount = pressCount_;
    pressed_.reset();
    released_.reset();
    pressCount_.fill(0);
    return t;
}

LookDelta InputState::takeLook() {
    return std::exchange(look_, LookDelta{});
}

} // namespace coe::input
