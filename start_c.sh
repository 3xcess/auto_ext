#!/bin/bash

cd ./profilers_c

if [[ "$EUID" -ne 0 ]]; then
    echo "Please run as sudo!"
    exit 1
fi

set -euo pipefail
echo "Launching ba-bawm profilers. Press Ctrl+C or kill this script to stop them."

trap 'echo ">>> Stopping all profilers..."; \
      echo ">>> Cleaning BPF filesystem..."; sudo rm -rf /sys/fs/bpf/ba_bawm; kill 0; exit 1' SIGINT


PROFILER=${1:-all}
PROFILER=$(echo "$PROFILER" | tr '[:upper:]' '[:lower:]')

run_profiler() {
    local p=$1
    echo ">>> Launching BA-BAWM $p profiler"
    sudo ./"$(echo "$p" | tr '[:lower:]' '[:upper:]')/ba_bawm_$p"
}

case "$PROFILER" in
    cpu|io|mem|net)
        run_profiler $PROFILER
        ;;
    all)
        for p in cpu io mem net; do
            run_profiler $p &
        done
        ;;
    *)
        echo "Usage: $0 [cpu|io|mem|net|all]"
        exit 1
        ;;
esac

wait