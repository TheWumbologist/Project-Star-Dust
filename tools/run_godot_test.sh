#!/usr/bin/env bash
# Runs one headless Godot test script and fails if it fails OR if Godot
# printed any script or engine error along the way (a test can pass its
# checks while a node elsewhere throws every frame).
# Usage: tools/run_godot_test.sh <godot binary> <res://tests/x.gd> [timeout seconds]
set -uo pipefail
godot="$1"
script="$2"
limit="${3:-180}"
log="$(mktemp)"
timeout "$limit" "$godot" --headless --script "$script" 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
if grep -qE "^(SCRIPT ERROR|ERROR):" "$log"; then
	echo "::error::$script printed errors (see above)"
	grep -nE "^(SCRIPT ERROR|ERROR):" -A2 "$log" | head -40
	exit 1
fi
exit "$status"
