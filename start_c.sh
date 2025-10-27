#!/bin/bash

cd ./profilers_c

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

# Wait for the pinned BPF map to appear before starting the dispatcher
echo ">>> Waiting for /sys/fs/bpf/ba_bawm to be created..."
for i in {1..20}; do
    if [ -e /sys/fs/bpf/ba_bawm ]; then
        break
    fi
    sleep 0.5
done

echo ">>> Launching dispatcher (sudo python dispatcher.py)"
(cd .. && sudo python dispatcher.py) &

wait
