# Contributing to RetroFM

RetroFM is a source-first FPGA, firmware, and verification project. Changes
should be reviewable from source and reproducible from the pinned dependency
metadata. Generated products, private inputs, and machine-local workspaces are
not contribution artifacts.

## What belongs in a change

- RTL, firmware, host tests, build scripts, documentation, and reproducible
  verification metadata.
- Small deterministic fixtures under `testdata/generated/` only when their
  redistribution rights are recorded in the local manifest.
- Evidence that names the exact command, tool version, result, and artifact
  hash when a build or simulation is part of the claim.

Do not commit fetched `third_party/` trees, Vivado/Vitis products, bitstreams,
ELFs, BOOT.BIN files, SD-card images, audio captures, or personal/copyrighted
music and import archives. The root `.gitignore` intentionally excludes these
paths and extensions. Do not work around it with force-adds.

## Evidence states

Keep these states separate in status reports and pull requests:

1. Portable host tests pass.
2. RTL simulation passes.
3. Vivado synthesis/implementation and firmware packaging pass.
4. A physical board boots, plays, and is measured or heard as accepted.

An earlier state never proves a later state. Simulation is not board playback;
a packaged `BOOT.BIN` is not a flashed or audibly accepted image. Leave open
bench and hardware items open, and record them in the appropriate status or
bench record.

## Workflow

For non-trivial work, open or reuse an issue first. Use a branch such as
`feat/<issue>-<slug>`, `fix/<issue>-<slug>`, or `chore/<issue>-<slug>`, and keep
the commit subject short and imperative. Pull requests should include the
linked issue, test commands and results, impact/risk notes, and explicit
limitations. Use `Refs #N` while work remains incomplete; use `Fixes #N` only
when the issue's acceptance criteria are actually satisfied.

Before requesting review, run `git diff --check`, inspect `git status`, confirm
that no ignored/generated/private files were force-added, and state which of
the four evidence states was reached. Hardware safety and licensing concerns
should be called out even when the code change itself is small.
