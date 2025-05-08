#!/bin/bash

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as sudo!"
    exit 1
fi

set -euo pipefail

echo "Starting all profilers..."

CONFIG_FILE="config.json"
SCRIPT_DIR=$(jq -r '.script_dir' "$CONFIG_FILE")
PROFILERS=($(jq -r '.profilers[]' "$CONFIG_FILE"))

for PROFILER in "${PROFILERS[@]}"; do
    echo "${PROFILER}"
    python3 "${SCRIPT_DIR}/${PROFILER}.py" &
done

echo "All scripts launched. Press Ctrl+C or kill this script to stop them."
wait
