# Covenant of Embers

An original, open-source co-op (1–4 players) Borderlands-style loot FPS built on a small custom C++20 / Vulkan engine. Inspired by the spirit of Magewar and by biblical themes; not a copy of either.

Status: **M0 – foundations**. See [docs/PLAN.md](docs/PLAN.md) for the full design.

## Build (Linux)
```sh
cmake --preset debug
cmake --build --preset debug
./build/debug/covenant
```
Requires CMake ≥ 3.25, Ninja, a C++20 compiler (GCC 13+/Clang 17+), and the Vulkan SDK pieces (headers, loader, glslc; validation layers recommended).

## Licenses
- Code: Apache-2.0 (see `LICENSE`).
- Original assets: CC BY-SA 4.0 (`LICENSE-ASSETS`, to be added with the first original asset).
- Third-party assets keep their own licenses; every one is listed in `ASSETS.toml` and `CREDITS.md`.
