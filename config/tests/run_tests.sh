#!/usr/bin/env bash

set -u
set -o pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

VM_ID=$(cat /etc/hostname 2>/dev/null || echo unknown)

TEST_FILE="${SCRIPT_DIR}/${VM_ID}-test.txt" 
DETAIL_FILE="${SCRIPT_DIR}/${VM_ID}-test_detail.txt"

if [[ ! -f "$TEST_FILE" ]]; then
  echo "Warning: $TEST_FILE does not exist yet; it will be created."
fi
if [[ ! -f "$DETAIL_FILE" ]]; then
  echo "Warning: $DETAIL_FILE does not exist yet; it will be created."
fi

RUNS=""

for arg in "$@"; do
  case "$arg" in
    --runs=*)
      RUNS="${arg#*=}"
      ;;
    *)
      echo "Usage: $0 --runs=<number_of_iterations>"
      exit 1
      ;;
  esac
done

if [[ -z "${RUNS:-}" ]]; then
  echo "Error: --runs=<N> is required."
  exit 1
fi

if ! [[ "$RUNS" =~ ^[0-9]+$ ]] || (( RUNS <= 0 )); then
  echo "Error: --runs must be a positive integer."
  exit 1
fi

: > "$TEST_FILE"
: > "$DETAIL_FILE"

echo "[INFO] Cleared previous test logs: $TEST_FILE and $DETAIL_FILE"

BENCHMARKS=(
  "perf_sched_all:::perf bench sched all"
  "schbench:::${SCRIPT_DIR}/schbench/./schbench -r 10"
  "sysbench_cpu:::sysbench cpu run"
  "sysbench_memory:::sysbench memory run"
  "sysbench_fileio:::sysbench fileio run --file-test-mode=rndrw"
  "phoronix_compress:::${SCRIPT_DIR}/phoronix-test-suite/./phoronix-test-suite batch-benchmark tiobench"
  "phoronix_pybench:::${SCRIPT_DIR}/phoronix-test-suite/./phoronix-test-suite batch-benchmark pybench"
  "phoronix_sqlite:::${SCRIPT_DIR}/phoronix-test-suite/./phoronix-test-suite batch-benchmark sqlite"
  # Adjust server and duration for your iperf setup
  #"iperf3:::iperf3 -c 127.0.0.1 -t 10"
)

run_benchmark() {
  local iter="$1"
  local name="$2"
  local cmd="$3"

  local stdout_file stderr_file
  stdout_file=$(mktemp)
  stderr_file=$(mktemp)

  local start_ns end_ns elapsed_ms status
  start_ns=$(date +%s%N || echo 0)

  bash -c "$cmd" >"$stdout_file" 2>"$stderr_file"
  status=$?

  end_ns=$(date +%s%N || echo 0)

  if [[ "$start_ns" != 0 && "$end_ns" != 0 ]]; then
    elapsed_ms=$(( (end_ns - start_ns) / 1000000 ))
  else
    elapsed_ms=0
  fi

  # Format: ISO_TIMESTAMP iter=<n> name=<benchmark_name> status=<exit_code> elapsed_ms=<ms>
  printf '%s iter=%s name=%s status=%s elapsed_ms=%s\n' \
    "$(date -Is)" "$iter" "$name" "$status" "$elapsed_ms" >>"$TEST_FILE"

  local metrics=""
  case "$name" in
    sysbench_cpu|sysbench_memory|sysbench_fileio)
      metrics=$(grep -Ei 'total time|events|transferred|throughput' "$stdout_file" || true)
      ;;
    perf_sched_all)
      metrics=$(grep -Ei 'Total time:|summary' "$stdout_file" || true)
      ;;
    schbench)
      metrics=$(grep -Ei 'rps|sched' "$stdout_file" || true)
      ;;
    phoronix)
      metrics=$(grep -Ei 'Average|Deviation|pts' "$stdout_file" || true)
      ;;
    iperf3)
      metrics=$(grep -Ei 'sender|receiver' "$stdout_file" || true)
      ;;
  esac

  {
    printf '[%s] iter=%s name=%s status=%s elapsed_ms=%s\n' \
      "$(date -Is)" "$iter" "$name" "$status" "$elapsed_ms"

    if [[ -n "$metrics" ]]; then
      echo "$metrics"
    else
      # If no filter matched, you can either:
      #   - leave it empty, OR
      #   - fall back to full stdout for debugging.
      # For now, we keep it compact and *do not* dump full output.
      echo "(no metric filter matched for $name)"
    fi
    echo
  } >>"$DETAIL_FILE"

  rm -f "$stdout_file" "$stderr_file"
}


for ((iter = 1; iter <= RUNS; iter++)); do
  echo "=== Iteration $iter / $RUNS ==="

  # Pick 3 random benchmarks from the list
  mapfile -t selection < <(printf '%s\n' "${BENCHMARKS[@]}" | shuf -n 3)

  for entry in "${selection[@]}"; do
    name="${entry%%:::*}"
    cmd="${entry#*:::}"

    echo "========= ${VM_ID} Running benchmark: $name ==========="
    run_benchmark "$iter" "$name" "$cmd"
  done
done

echo "Done. Timing logged to $TEST_FILE, details to $DETAIL_FILE."

