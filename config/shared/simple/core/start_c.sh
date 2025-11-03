#!/bin/bash

cd ./profilers_c

set -euo pipefail
echo "Launching ba-bawm profilers. Press Ctrl+C or kill this script to stop them."

trap 'echo ">>> Stopping all profilers..."; \
      echo ">>> Cleaning BPF filesystem..."; sudo rm -rf /sys/fs/bpf/ba_bawm; kill 0; exit 1' SIGINT

usage() {
    echo "Usage: $0 [-m profile|sched] [cpu|io|mem|net|all]" >&2
    echo "  -m profile  Run only profilers (default profiler: all)" >&2
    echo "  -m sched    Run only dispatcher" >&2
    echo "  (no -m)     Run profilers and dispatcher (default)" >&2
}

# Default mode is to run both profilers and dispatcher
MODE="both"
CONFIG=""

while getopts ":m:h" opt; do
    case "$opt" in
        m)
            MODE=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')
            ;;
        h)
            usage
            exit 0
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
    esac
done
shift $((OPTIND-1))

case "$MODE" in
    both|profile|sched)
        ;;
    *)
        echo "Invalid mode: $MODE" >&2
        usage
        exit 1
        ;;
esac

PROFILER=${1:-all}
PROFILER=$(echo "$PROFILER" | tr '[:upper:]' '[:lower:]')

run_profiler() {
    local p=$1
    echo ">>> Launching BA-BAWM $p profiler"
    sudo ./"$(echo "$p" | tr '[:lower:]' '[:upper:]')/ba_bawm_$p"
}

start_profilers() {
    case "$PROFILER" in
        cpu|io|mem|net)
            run_profiler "$PROFILER" &
            ;;
        all)
            for p in cpu io mem net; do
                run_profiler "$p" &
            done
            ;;
        *)
            echo "Usage: $0 [-m profile|sched] [cpu|io|mem|net|all]" >&2
            exit 1
            ;;
    esac
}
CONFIG=${2:-main}
run_dispatcher() {
    local cfg=${1:-main}
    echo ">>> Launching dispatcher (sudo python dispatcher.py ${cfg})"
    (cd .. && sudo python dispatcher.py ${cfg}) &
}
case "$MODE" in
    profile)
        echo "Launching BA-BAWM profilers. Press Ctrl+C or kill this script to stop them."
        start_profilers
        ;;
    sched)
        echo ">>> Running dispatcher only"
        run_dispatcher "$CONFIG"
        ;;
    both)
        echo "Launching BA-BAWM profilers and dispatcher. Press Ctrl+C or kill this script to stop them."
        start_profilers
        # Wait for the pinned BPF map to appear before starting the dispatcher
        echo ">>> Waiting for /sys/fs/bpf/ba_bawm to be created..."
        for i in {1..20}; do
            if [ -e /sys/fs/bpf/ba_bawm ]; then
                break
            fi
            sleep 0.5
        done
        run_dispatcher "$CONFIG"
        ;;
esac

wait