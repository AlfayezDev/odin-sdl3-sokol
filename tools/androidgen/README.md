# androidgen (vendored)

Copied from https://github.com/AlfayezDev/androidgen at the commit recorded in
`VERSION`. Update by replacing `src/` and `wrapper/` from that repository and
bumping the commit.

Build: `odin build tools/androidgen/src -o:speed -out:build/tools/androidgen`

Used by `odin run . -- android` for Gradle project generation. The upstream
bindings command is intentionally not vendored; `tools/odinbinder` owns bindings.
