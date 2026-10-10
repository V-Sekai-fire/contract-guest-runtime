# contract-guest-runtime

The godot-sandbox runtime the stage guest ELFs share: sandbox API, compute dispatch, fibers, a reduced engine core and the shader runtime.

## What it is for

A guest repository builds its RISC-V ELF against this runtime by including `cmake/guest_runtime.cmake` after `project()`, with the toolchain from `repository-riscv64-sysroot`. The runtime finds the repositories it builds against as sibling checkouts at their goal-manifest paths.

## Build and check

    elixir tools/check_standalone.exs --sysroot=<repository-riscv64-sysroot>

It builds a standalone guest through the same module and checks the ELF, with a control for each check. `RISCV64_SYSROOT` can stand in for `--sysroot`, and `cmake`, `ninja`, `clang++` and `ld.lld` must be on `PATH`.

## Licence

MIT. See [LICENSE](LICENSE). The vendored and derived trees carry their own, recorded in each tree's `CITATION.cff`: the engine core subsets are MIT and the sandbox API is BSD-3-Clause.
