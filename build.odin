package build

import "core:fmt"
import "core:os"

main :: proc() {
    target := "desktop"
    build_only := false
    target_set := false
    for arg in os.args[1:] {
        switch arg {
        case "--help", "-h":
            fmt.println("Usage: odin run . -- [desktop|android|ios] [--build-only]")
            return
        case "--build-only":
            build_only = true
        case "desktop", "android", "ios":
            if target_set { fmt.eprintln("Choose exactly one target."); os.exit(2) }
            target, target_set = arg, true
        case:
            fmt.eprintln("Unknown argument:", arg, "\nUsage: odin run . -- [desktop|android|ios] [--build-only]")
            os.exit(2)
        }
    }
    mode := "run"
    if build_only { mode = "build" }
    child, err := os.process_start({
        command = []string{"bash", "scripts/run.sh", target, mode},
        working_dir = #directory,
        stdin = os.stdin, stdout = os.stdout, stderr = os.stderr,
    })
    if err != nil { fmt.eprintln("Cannot start build workflow (Bash required):", err); os.exit(1) }
    state, wait_err := os.process_wait(child)
    if wait_err != nil { fmt.eprintln("Cannot wait for build workflow:", wait_err); os.exit(1) }
    os.exit(state.exit_code)
}
