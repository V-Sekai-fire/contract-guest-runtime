# contract-guest-runtime

The godot-sandbox guest runtime the stage guests share: sandbox API, rd_compute, fiber and pump, godot_lite, slang-rt.

Split out of `interactor-dress-on` at `310b52e` with its history (`git subtree`). It sits at `2-contract/guest-runtime` in the goal manifest (`contract-manifest-taskweft`), and finds the repositories it builds against as sibling checkouts at their manifest paths. `transport-meshing-pen` builds the guest ELFs (`build.sh`, `tools/build.exs`).
