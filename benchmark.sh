"""
Benchmark various scheduler extensions across different workloads using the stress-ng stressor.
The workloads included stress-ng --switch, which repeatedly switches context between threads and is CPU-intensive;
stress-ng --hdd, which continuously writes to temporary files to generate heavy disk I/O traffic;
stress-ng --vm, which allocates large chunks of memory.
Each workload and scheduler combination was executed 10 times, and the timing results were averaged.
"""
set -euo pipefail
# -e: exit on error
# -u: treat unset variables as an error
# -o pipefail: fail if any command in a pipeline fails

# "system" = default Linux scheduler
SCHEDULERS=("system" "scx_simple" "scx_central" "scx_flatcg" "scx_nest" "scx_prev" "scx_qmap" "scx_sdt")
ITERATIONS=10

sudo apt install -y stress-ng # Ensure stress-ng is installed

# Function to measure time for a command (millisecond precision)
measure_time() {
    local desc="$1"
    shift
    local start=$(date +%s.%3N)
    "$@" >/dev/null 2>&1 # Run the command but discard stdout/stderr
    local end=$(date +%s.%3N)
    local elapsed=$(echo "$end - $start" | bc)
    echo "$elapsed"
}

# Declare associative arrays (floats)
declare -A cpu_total
declare -A io_total
declare -A mem_total

for sched in "${SCHEDULERS[@]}"; do
    echo "=== Running scheduler: $sched ==="
    cpu_total[$sched]=0
    io_total[$sched]=0
    mem_total[$sched]=0

    for ((i=1; i<=ITERATIONS; i++)); do
        echo "Run $i/$ITERATIONS for $sched"

        if [[ "$sched" != "system" ]]; then
            cd auto_ext/scx/build/scheds/c/ || { echo "Scheduler directory not found"; exit 1; }
            sudo "./${sched}" >/dev/null 2>&1 &
            SCHED_PID=$!
            cd - >/dev/null
            sleep 2
        else
            SCHED_PID=""
        fi

        cpu_time=$(measure_time "CPU workload" \
            stress-ng --switch 4 --switch-ops 1000000)
        io_time=$(measure_time "I/O workload" \
            stress-ng --hdd 2 --hdd-ops 50000)
        mem_time=$(measure_time "Memory workload" \
            stress-ng --vm 2 --vm-bytes 1G --vm-ops 1000000)

        # Use bc for accumulation (float-safe)
        cpu_total[$sched]=$(echo "${cpu_total[$sched]} + $cpu_time" | bc)
        io_total[$sched]=$(echo "${io_total[$sched]} + $io_time" | bc)
        mem_total[$sched]=$(echo "${mem_total[$sched]} + $mem_time" | bc)

        if [[ -n "${SCHED_PID}" ]]; then
            sudo kill "$SCHED_PID" || true
        fi

        sleep 1
    done
    echo "=== Completed $sched ==="
    echo
done

# Print results
printf "\n%-15s | %-15s | %-15s | %-15s\n" "Scheduler" "Avg CPU (s)" "Avg IO (s)" "Avg MEM (s)"
printf "%s\n" "--------------------------------------------------------------------------------"

for sched in "${SCHEDULERS[@]}"; do
    avg_cpu=$(echo "scale=3; ${cpu_total[$sched]} / $ITERATIONS" | bc)
    avg_io=$(echo "scale=3; ${io_total[$sched]} / $ITERATIONS" | bc)
    avg_mem=$(echo "scale=3; ${mem_total[$sched]} / $ITERATIONS" | bc)
    printf "%-15s | %-15s | %-15s | %-15s\n" "$sched" "$avg_cpu" "$avg_io" "$avg_mem"
done

echo "=== Benchmark Complete ==="