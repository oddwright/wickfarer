#!/usr/bin/env bash
# Runs Godot for CI and fails if it exits non-zero, prints a script error, or
# hangs. Godot logs a runtime script error and carries on, so a test that
# crashes half way would otherwise still exit 0 and turn CI green; and an
# error inside a tool's _init skips its quit(), leaving Godot running forever.
# Usage: tools/ci_godot.sh <godot args...>   (output is also saved to godot.log)
# GODOT_TIMEOUT (seconds, default 600) caps how long one run may take.
set -uo pipefail
timeout "${GODOT_TIMEOUT:-600}" godot "$@" 2>&1 | tee godot.log
status=${PIPESTATUS[0]}
if [ "$status" -eq 124 ]; then
  echo "::error::Godot did not finish in ${GODOT_TIMEOUT:-600}s (a script error can skip quit())"
fi
if grep -qE "SCRIPT ERROR|Parse Error|Failed to load script" godot.log; then
  echo "::error::Godot reported a script error (see the log above)"
  exit 1
fi
exit "$status"
