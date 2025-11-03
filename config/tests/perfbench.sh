#!/bin/bash
# perfbench.sh — run "perf bench sched all" and save results per-VM

VM_ID=$(cat /etc/hostname 2>/dev/null || echo unknown)
OUTDIR="/home/u/results/${VM_ID}"
mkdir -p "$OUTDIR"

echo "Running perf bench sched all on ${VM_ID}..."
perf bench sched all | tee "$OUTDIR/perfbench.txt"

