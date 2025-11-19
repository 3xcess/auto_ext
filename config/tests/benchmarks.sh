#!/usr/bin/env bash
set -euo pipefail

LOG_FILE="${1:-test.txt}"

if [[ ! -f "$LOG_FILE" ]]; then
    echo "Error: log file '$LOG_FILE' does not exist."
    echo "Usage: $0 [path/to/test.txt]"
    exit 1
fi

echo "Reading benchmark log from: $LOG_FILE"
echo


echo "=== Per-run results (sorted by benchmark, then iteration) ==="
printf "%-18s %-8s %-12s %-8s %s\n" "BENCHMARK" "ITER" "ELAPSED_MS" "STATUS" "TIMESTAMP"
printf "%-18s %-8s %-12s %-8s %s\n" "---------" "----" "----------" "------" "---------"


awk '
{
    ts = $1
    delete kv
    for (i = 2; i <= NF; i++) {
        split($i, a, "=")
        kv[a[1]] = a[2]
    }
    name      = kv["name"]
    iter      = kv["iter"]
    status    = kv["status"]
    elapsed   = kv["elapsed_ms"]

    # Print in stable, parseable columns
    printf "%-18s %-8s %-12s %-8s %s\n", name, iter, elapsed, status, ts
}' "$LOG_FILE" | sort -k1,1 -k2,2n

echo


echo "=== Per-benchmark summary (elapsed_ms) ==="

awk '
{
    delete kv
    for (i = 2; i <= NF; i++) {
        split($i, a, "=")
        kv[a[1]] = a[2]
    }

    name    = kv["name"]
    elapsed = kv["elapsed_ms"] + 0

    count[name]++
    sum[name]   += elapsed

    if (!(name in min) || elapsed < min[name]) {
        min[name] = elapsed
    }
    if (!(name in max) || elapsed > max[name]) {
        max[name] = elapsed
    }
}
END {
    if (length(count) == 0) {
        print "No data found."
        exit
    }

    printf "%-18s %-8s %-12s %-12s %-12s\n", "BENCHMARK", "N", "MIN_MS", "AVG_MS", "MAX_MS"
    printf "%-18s %-8s %-12s %-12s %-12s\n", "---------", "-", "------", "------", "------"

    # gawk-specific: sort keys alphabetically
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (b in count) {
        avg = (sum[b] / count[b])
        printf "%-18s %-8d %-12d %-12.1f %-12d\n", b, count[b], min[b], avg, max[b]
    }
}' "$LOG_FILE"

