#!/usr/bin/env bash
set -euo pipefail

./ssh_vm.sh all -- sudo apt update

./ssh_vm.sh all -- sudo apt install -y sysbench
#./ssh_vm.sh all -- sudo apt install -y iperf3
./ssh_vm.sh all -- sudo apt install -y php-cli php-xml git

echo -e "n\nY" | ./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite batch-setup
./ssh_vm.sh all -- /mnt/w/config/tests/phoronix-test-suite/./phoronix-test-suite install pts/tiobench

./ssh_vm.sh all -- sysbench fileio prepare


echo "=== Running run_tests.sh ==="
#./ssh_vm.sh vm2 -- sudo /mnt/w/get-dependencies.sh
./ssh_vm.sh all -- sudo /mnt/w/config/tests/run_tests.sh --runs=2

echo "=== Done ==="

