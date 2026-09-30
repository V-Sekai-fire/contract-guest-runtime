import Lake
open Lake DSL

package Probes where

-- Every dependency is pinned in a V-Sekai-fire repo or fork.
require LeanSlang from git
  "https://github.com/V-Sekai-fire/contract-lean-slang.git" @ "60532aef8ed70cc669ecab481182d0636c9e1ac3"

-- Gate 0F probe kernels (interactor-dress-on gates/0f-runtime).
lean_lib Probes

lean_exe emit_probes where
  root := `EmitProbes
