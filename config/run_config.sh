#!/usr/bin/env bash
set -euo pipefail

q() { "$@" >/dev/null 2>&1; }

LOOPS=1

for arg in "$@"; do
  case "$arg" in
    --loops=*)
      LOOPS="${arg#*=}"
      ;;
    *)
      echo "Usage: $0 [--loops=N]" >&2
      exit 1
      ;;
  esac
done

if ! [[ "$LOOPS" =~ ^[0-9]+$ ]] || (( LOOPS <= 0 )); then
  echo "Error: --loops must be a positive integer." >&2
  exit 1
fi

echo '======== Installing prerequisites ========='
q ./ssh_vm.sh all -- sudo apt update

q ./ssh_vm.sh all -- sudo apt install -y sysbench
# q ./ssh_vm.sh all -- sudo apt install -y iperf3
q ./ssh_vm.sh all -- sudo apt install -y php-cli php-xml git
echo '===== END ====='
echo

echo '======== Preparation Phase ========'
echo -e "n\nY" | ./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite batch-setup
q ./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite install pts/tiobench

q ./ssh_vm.sh all -- sysbench fileio prepare
echo '===== END ====='
echo

for (( loop = 1; loop <= LOOPS; loop++ )); do
  echo "=== Loop ${loop}/${LOOPS}: Running tests ==="
  ./ssh_vm.sh all -- sudo /mnt/w/config/tests/run_tests.sh --runs=5

  echo "=== Loop ${loop}/${LOOPS}: Comparing vm1 vs vm2 ==="
  ./tests/compare.sh

  echo "=== Loop ${loop}/${LOOPS}: Running decision logic ==="
  ./decision_logic.py

  echo "=== Loop ${loop}/${LOOPS} complete ==="
  echo
done

echo "=== All ${LOOPS} loop(s) done. Check config/tests/results.log for summaries. ==="
