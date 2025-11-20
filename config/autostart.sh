#!/usr/bin/env bash

VM_ID=$(cat /etc/hostname 2>/dev/null || echo unknown)
AUTO_EXT_DIR="/mnt/w/"

cd "$AUTO_EXT_DIR" || exit 1

sudo chmod +x get-dependencies.sh
sudo ./get-dependencies.sh

echo "======================================"
echo "||      Dependencies Installed       ||"
echo "======================================"

case "$VM_ID" in
  vm1)
    echo ">>> Starting profilers only on vm1 (main config)."
    sudo ./start_c.sh -m both -v vm1 all main &
    ;;
  vm2)
    echo ">>> Starting profilers + dispatcher (alt config) on vm2."
    sudo ./start_c.sh -m both -v vm2 all alt &
    ;;
  *)
    echo "Unknown VM ($VM_ID), not launching auto_ext."
    ;;
esac
