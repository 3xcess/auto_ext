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
echo 'Updating packages'
q ./ssh_vm.sh all -- sudo apt update

echo 'Installing sysbench'
q ./ssh_vm.sh all -- sudo apt install -y sysbench
# q ./ssh_vm.sh all -- sudo apt install -y iperf3
echo 'Installing phoronix-test-suite'
q ./ssh_vm.sh all -- sudo apt install -y php-cli php-xml git
echo '===== Prerequisites Installed ====='
echo

echo '======== Preparation Phase ========'
echo -e "n\nY" | ./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite batch-setup

echo 'Installing tiobench'
./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite install pts/tiobench

echo 'Creating sysbench test files'
q ./ssh_vm.sh all -- sysbench fileio prepare
echo '===== END ====='
echo

echo '========== Starting Auto_Ext =========='
./ssh_vm.sh all -- /mnt/w/config/autostart.sh

echo "Waiting 20 seconds for profilers + dispatcher to stabilize..."
sleep 20
echo ''
echo '========== Auto_Ext Running =========='

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
