# contract-guest-runtime

The godot-sandbox guest runtime the stage guests share: sandbox API, rd_compute, fiber and pump, godot_lite, slang-rt.

Split out of `interactor-dress-on` at `310b52e` with its history (`git subtree`). It sits at `2-contract/guest-runtime` in the goal manifest (`contract-manifest-taskweft`), and finds the repositories it builds against as sibling checkouts at their manifest paths. A guest repository builds its ELF by including `cmake/guest_runtime.cmake` after `project()`, configured with the `toolchain.cmake` of `repository-riscv64-sysroot`. `elixir tools/check_standalone.exs --sysroot=<dir>` builds `tests/standalone` that way, and `transport-meshing-pen` builds its stage ELFs through the same module.
