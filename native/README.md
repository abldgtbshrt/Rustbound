# Native horde simulation (GDExtension)

The horde's per-frame work runs in C++: `HordeSim` (`src/horde_sim.cpp`). It
holds every enemy's state in flat arrays and does the spatial grid, steering,
separation, status effects, spatial queries and the MultiMesh buffer.
`EnemyManager` (GDScript) keeps the gameplay side: wave spawning, kill
rewards, and handing robot contacts to `RobotController`.

**You don't need a C++ toolchain to work on the game.** Prebuilt libraries
are committed in `bin/` and Godot loads them through
`bin/rustbound_native.gdextension`. If a library is missing for your
platform, the game falls back to `scripts/systems/horde_sim_gd.gd`, a
GDScript twin with the same API (slower, same behavior). Godot will print
"GDExtension dynamic library not found" once at startup in that case; that's
expected.

## Rules

- **Two implementations, one behavior.** Any change to `horde_sim.cpp` must be
  mirrored in `horde_sim_gd.gd`, and vice versa. The parity tests in
  `tests/run_tests.gd` (`_test_horde_backends`) run both on the same input and
  fail if they drift.
- **No callbacks from C++.** `HordeSim` never calls GDScript. Kills from bulk
  operations are queued (`take_kills()`), robot contacts are queued
  (`get_contacts()` / `resolve_contacts()`), and `EnemyManager` handles them.
- **Gameplay code uses `EnemyManager`'s API**, never the backend directly:
  `get_pos(i)`, `set_pos(i, p)`, `get_hp(i)`, `damage(i, ...)`,
  `query_radius(...)`, `query_segment(...)`, `find_nearest(...)` and so on.
- Rebuild the binaries in the same PR as a C++ change (see below).

## Building

You need CMake 3.13+ and a C++17 compiler (Visual Studio 2022, GCC, Clang or
mingw-w64). Fetch godot-cpp first:

    git submodule update --init

Then, from the repository root:

    cmake -S native -B native/build -DCMAKE_BUILD_TYPE=Release
    cmake --build native/build --config Release --parallel

The library is written straight into `bin/<platform>/`. The first build
compiles godot-cpp and takes several minutes; later builds take seconds.

Windows DLL from Linux (mingw-w64 or llvm-mingw on PATH):

    cmake -S native -B native/build-win -DCMAKE_BUILD_TYPE=Release \
          -DCMAKE_TOOLCHAIN_FILE=native/mingw-toolchain.cmake
    cmake --build native/build-win --parallel

Or let CI do it: Actions > **native** > Run workflow builds Linux, Windows
and macOS, runs the tests on both backends, and commits the binaries to
your branch.

godot-cpp is pinned to the `godot-4.3-stable` tag to match the engine.
Bump the submodule when the project moves to a newer Godot.

## Testing and benchmarking

    godot --headless res://tests/run_tests.tscn
    RUSTBOUND_HORDE_BACKEND=gdscript godot --headless res://tests/run_tests.tscn
    godot --headless res://tests/bench_horde.tscn

`RUSTBOUND_HORDE_BACKEND` (`native` | `gdscript`) forces a backend. The
benchmark takes `BENCH_SIZES=600,1500` and `BENCH_BACKENDS=native` to narrow
a run.
