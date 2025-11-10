"""
Switches the scheduler every 5 seconds based on BPF map readings.
First version:
-Uses a simple heuristic: if the current reading is twice as large as the previous two readings, it is treated as a surge.
-Cannot yet automatically select the most suitable scheduler; I currently assign schedulers manually based on the results from benchmark.sh
-Assumes that only 1 of the 4 monitored features can spike at a time, so now only 4 schedulers are defined in SCHED_MAP, rather than the full set of 15 possible combinations.
"""
set -euo pipefail

DEFAULT_SCHED="system"

declare -A SCHED_MAP=(
    [CPU]="scx_prev"
    [MEM]="system"
    [IO]="scx_simple"
    [NET]="system"
)

declare -A prevDelta prevDelta2 currDelta prevVals currVals
current_sched="$DEFAULT_SCHED"
sched_pid=""

read_bpf_map() {
    local raw
    raw=$(sudo bpftool map dump pinned /sys/fs/bpf/ba_bawm -j 2>/dev/null || echo "[]")
    for i in 0 1 2 3; do
        currVals[$i]=$(echo "$raw" | jq -r ".[] | select(.formatted.key == $i) | .formatted.value // 0" | tr -d '[:space:]')
        currVals[$i]=${currVals[$i]:-0}
    done
}

compute_deltas() {
    for i in "${!currVals[@]}"; do
        local old=${prevVals[$i]:-0}
        local new=${currVals[$i]:-0}
        local diff=$(( new - old ))
        currDelta[$i]=$diff
    done
}

detect_spikes() {
    local spikes=()
    for i in "${!currDelta[@]}"; do
        local now=${currDelta[$i]:-0}
        local d1=${prevDelta[$i]:-0}
        local d2=${prevDelta2[$i]:-0}
        if (( now >= 2 * d1 && now >= 2 * d2 && now > 0 )); then
            case $i in
                0) spikes+=("CPU") ;;
                1) spikes+=("IO") ;;
                2) spikes+=("MEM") ;;
                3) spikes+=("NET") ;;
            esac
        fi
    done
    echo "${spikes[*]}"
}

stop_scheduler() {
    if [[ -n "${sched_pid:-}" ]]; then
        echo "Stopping scheduler PID $sched_pid..."
        sudo kill "$sched_pid" 2>/dev/null || true
        sched_pid=""
    fi
}

start_scheduler() {
    local key="$1"
    local sched_name=${SCHED_MAP[$key]:-$DEFAULT_SCHED}
    if [[ "$sched_name" == "$DEFAULT_SCHED" ]]; then
        echo "Using system default scheduler"
        current_sched="$DEFAULT_SCHED"
        return
    fi
    echo "Loading scheduler: $sched_name"
    cd "$HOME/auto_ext/scx/build/scheds/c"
    #sudo "./$sched_name" &
    sudo "./$sched_name" > /dev/null 2>&1 &
    sched_pid=$!
    current_sched="$sched_name"
}

# Initialization
read_bpf_map
for i in "${!currVals[@]}"; do
    prevVals[$i]=${currVals[$i]}
    prevDelta[$i]=0
    prevDelta2[$i]=0
done

while true; do
    sleep 5

    read_bpf_map
    compute_deltas

    spikes=($(detect_spikes))
    if (( ${#spikes[@]} > 0 )); then
        echo "Spike detected in: ${spikes[*]}."
        s="${spikes[0]}" # Only handle the first flag - "spikes" is a set of flag(s)
        if [[ "$current_sched" != "${SCHED_MAP[$s]}" ]]; then
            stop_scheduler
            start_scheduler "$s"
        fi
    else
        echo "No spikes detected."
    fi

    for i in "${!currDelta[@]}"; do
        prevDelta2[$i]=${prevDelta[$i]}
        prevDelta[$i]=${currDelta[$i]}
        prevVals[$i]=${currVals[$i]}
    done
done
