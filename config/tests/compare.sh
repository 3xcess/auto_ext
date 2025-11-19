#!/usr/bin/env bash
set -euo pipefail

# Always compare these two static files located next to this script.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOG_FILE1="$SCRIPT_DIR/vm1-test.txt"
LOG_FILE2="$SCRIPT_DIR/vm2-test.txt"
RESULTS_LOG="$SCRIPT_DIR/results.log"

if [[ ! -f "$LOG_FILE1" ]]; then
  echo "Error: '$LOG_FILE1' does not exist."
  exit 1
fi
if [[ ! -f "$LOG_FILE2" ]]; then
  echo "Error: '$LOG_FILE2' does not exist."
  exit 1
fi

# Redirect output to results.log (append, do not truncate)
exec >>"$RESULTS_LOG" 2>&1
echo "===== $(date -Is) Benchmark comparison (vm2 vs vm1) ====="

echo "Comparing benchmark averages:"
echo "  vm1: $LOG_FILE1"
echo "  vm2: $LOG_FILE2"
echo "=== Average comparison (vm2 vs vm1) ==="

awk '
BEGIN {
    # Workload categories per benchmark
    w["perf_sched_all"]   = "CPU"
    w["schbench"]         = "CPU"
    w["sysbench_cpu"]     = "CPU"
    w["sysbench_memory"]  = "MEM"
    w["sysbench_fileio"]  = "IO"
    w["phoronix_tiobench"] = "IO"
    w["phoronix_pybench"] = "CPU/MEM"
    w["phoronix_sqlite"]  = "CPU/MEM/IO"
}
function add_sample(which, name, elapsed) {
    if (which == 1) {
        c1[name]++; s1[name] += elapsed
        if (!(name in min1) || elapsed < min1[name]) min1[name] = elapsed
        if (!(name in max1) || elapsed > max1[name]) max1[name] = elapsed
    } else {
        c2[name]++; s2[name] += elapsed
        if (!(name in min2) || elapsed < min2[name]) min2[name] = elapsed
        if (!(name in max2) || elapsed > max2[name]) max2[name] = elapsed
    }
    all[name] = 1
}
FNR==NR {
    delete kv
    for (i = 2; i <= NF; i++) { split($i, a, "="); kv[a[1]] = a[2] }
    n = kv["name"]; e = kv["elapsed_ms"] + 0
    add_sample(1, n, e)
    next
}
{
    delete kv
    for (i = 2; i <= NF; i++) { split($i, a, "="); kv[a[1]] = a[2] }
    n = kv["name"]; e = kv["elapsed_ms"] + 0
    add_sample(2, n, e)
}
function fmt_num(val, decimals) { return sprintf("%.*f", decimals, val) }
END {
    if (length(all) == 0) {
        print "No data found."
        exit
    }

    printf "%-18s %-6s %-12s %-6s %-12s %-12s %-9s\n", \
           "BENCHMARK", "N1", "AVG1_MS", "N2", "AVG2_MS", "DELTA_MS", "DELTA_%"
    printf "%-18s %-6s %-12s %-6s %-12s %-12s %-9s\n", \
           "---------", "--", "-------", "--", "-------", "--------", "--------"

    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (b in all) {
        has1 = (b in c1); has2 = (b in c2)
        avg1 = has1 ? (s1[b] / c1[b]) : 0
        avg2 = has2 ? (s2[b] / c2[b]) : 0

        delta = (has1 && has2) ? (avg2 - avg1) : 0
        pct = (has1 && has2 && avg1 > 0) ? (100.0 * delta / avg1) : 0

        n1s = has1 ? c1[b] : "-"
        a1s = has1 ? fmt_num(avg1, 1) : "-"
        n2s = has2 ? c2[b] : "-"
        a2s = has2 ? fmt_num(avg2, 1) : "-"
        ds  = (has1 && has2) ? fmt_num(delta, 1) : "-"
        ps  = (has1 && has2 && avg1 > 0) ? fmt_num(pct, 1) : "-"

        # Save to arrays for summary
        has1a[b] = has1; has2a[b] = has2
        avg1a[b] = avg1; avg2a[b] = avg2

        printf "%-18s %-6s %-12s %-6s %-12s %-12s %-9s\n", b, n1s, a1s, n2s, a2s, ds, ps
    }

    print ""
    print "=== Summary: vm2 vs vm1 (lower elapsed_ms is better) ==="
    any_better = 0
    PROCINFO["sorted_in"] = "@ind_str_asc"
    for (b in all) {
        wl = (b in w) ? w[b] : "-"
        if (has1a[b] && has2a[b]) {
            verdict = (avg2a[b] < avg1a[b]) ? "vm2 better" : ((avg2a[b] > avg1a[b]) ? "vm1 better" : "tie")
            if (avg2a[b] < avg1a[b]) any_better = 1
        } else {
            verdict = "insufficient data"
        }
        printf "%-18s %-12s %s\n", b, "(" wl ")", verdict
    }
    print ""
    print "Any case vm2 better: " (any_better ? "Yes" : "No")
    print ""
    print ""
}' "$LOG_FILE1" "$LOG_FILE2"

