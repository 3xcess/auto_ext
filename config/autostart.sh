#!/bin/bash


VM_ID=$(cat /etc/hostname 2>/dev/null || echo unknown)
AUTO_EXT_DIR="/mnt/w/"

cd "$AUTO_EXT_DIR" || exit 1
sudo chmod +x get-dependencies.sh
sudo ./get-dependencies.sh
echo "======================================"
echo "||      Dependencies Installed      ||"
echo "====================================="

case "$VM_ID" in
  vm1)
    sudo ./start_c.sh -m profile &
    ;;
  vm2)
    sudo ./start_c.sh -m both all main &
    ;;
  vm3)
    sudo ./start_c.sh -m both all alt &
    ;;
  *)
    echo "Unknown VM ($VM_ID), skipping auto_ext launch."
    ;;
esac

