#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "${SCRIPT_DIR}/profilers_c"
make

VM_ID=""

PIDS=()

cleanup() {
    echo ">>> Stopping all profilers and dispatcher..."
    for pid in "${PIDS[@]}"; do
        if kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
    done
    echo ">>> Cleaning BPF filesystem..."
    sudo rm -rf /sys/fs/bpf/ba_bawm 2>/dev/null || true
}


trap 'cleanup; exit 1' INT TERM

usage() {
    echo "Usage: $0 [-m profile|sched] [-v vm_id] [cpu|io|mem|net|all] [config]" >&2
    echo ""
    echo "  -m profile   Run only profilers"
    echo "  -m sched     Run only dispatcher"
    echo "  (no -m)      Run profilers + dispatcher (default)"
    echo ""
    echo "  -v vm_id     Optional identifier (vm1, vm2)."
    echo "               If supplied, passed to dispatcher for logging."
    echo ""
    echo "  PROFILER:    cpu | io | mem | net | all (default: all)"
    echo "  config:      main | alt (default: main)"
}

MODE="both"

while getopts ":m:v:h" opt; do
    case "$opt" in
        m)
            MODE=$(echo "$OPTARG" | tr '[:upper:]' '[:lower:]')
            ;;
        v)
            VM_ID="$OPTARG"
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
    both|profile|sched) ;;
    *)
        echo "Invalid mode: $MODE" >&2
        usage
        exit 1
        ;;
esac

PROFILER=${1:-all}
PROFILER=$(echo "$PROFILER" | tr '[:upper:]' '[:lower:]')

CONFIG=${2:-main}
CONFIG=$(echo "$CONFIG" | tr '[:upper:]' '[:lower:]')

run_profiler() {
    local p=$1
    local up=${p^^}

    echo ">>> Launching ${p} profiler (silent)"
    sudo "./${up}/ba_bawm_${p}" >/dev/null 2>&1 &
    PIDS+=($!)
}

start_profilers() {
    case "$PROFILER" in
        cpu|io|mem|net)
            run_profiler "$PROFILER"
            ;;
        all)
            for p in cpu io mem net; do
                run_profiler "$p"
            done
            ;;
        *)
            echo "Invalid profiler: $PROFILER" >&2
            usage
            exit 1
            ;;
    esac
}

run_dispatcher() {
    local cfg=${1:-main}

    echo ">>> Launching dispatcher (cfg=${cfg}, vm_id=${VM_ID:-none}) (silent)"

    if [[ "${cfg}" == "alt" ]]; then
        if [[ -n "$VM_ID" ]]; then
            (cd .. && sudo python dispatcher.py alt "${VM_ID}") >/dev/null 2>&1 &
        else
            (cd .. && sudo python dispatcher.py alt) >/dev/null 2>&1 &
        fi
    else
        if [[ -n "$VM_ID" ]]; then
            (cd .. && sudo python dispatcher.py "${VM_ID}") >/dev/null 2>&1 &
        else
            (cd .. && sudo python dispatcher.py) >/dev/null 2>&1 &
        fi
    fi

    PIDS+=($!)
}

case "$MODE" in
    profile)
        echo "Launching BA-BAWM profilers only. Press Ctrl+C to stop."
        start_profilers
        ;;
    sched)
        echo "Launching dispatcher only."
        run_dispatcher "${CONFIG}"
        ;;
    both)
        echo "Launching profilers + dispatcher. Press Ctrl+C to stop."
        start_profilers
        echo ">>> Waiting for /sys/fs/bpf/ba_bawm ..."
        for i in {1..20}; do
            [[ -e /sys/fs/bpf/ba_bawm ]] && break
            sleep 0.5
        done
        run_dispatcher "${CONFIG}"
        ;;
esac

wait
cleanup
