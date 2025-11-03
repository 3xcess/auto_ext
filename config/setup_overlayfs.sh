#!/usr/bin/env bash
set -euo pipefail

LOWER="/mnt/workloads_shared"
UPPER="/tmp/overlay_upper"
WORK="/tmp/overlay_work"
MERGED="/mnt/w"

# 1. Mount 9p shared folder (read-only)
if ! mountpoint -q "$LOWER"; then
    mkdir -p "$LOWER"
    echo "[+] Mounting 9p shared folder at $LOWER"
    mount -t 9p -o trans=virtio,version=9p2000.L,msize=262144,ro workloads "$LOWER"
fi

# 2. Create local overlay directories
mkdir -p "$UPPER" "$WORK" "$MERGED"

# 3. Skip if already mounted
if mountpoint -q "$MERGED"; then
    echo "[=] $MERGED is already mounted."
    exit 0
fi

# 4. Mount overlay
echo "[+] Mounting overlay: lower=$LOWER upper=$UPPER"
mount -t overlay overlay -o lowerdir=$LOWER,upperdir=$UPPER,workdir=$WORK $MERGED

echo "[✅] OverlayFS is ready at $MERGED"
