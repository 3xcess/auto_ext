#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-b base_image] [-n name] [-p ssh_port] [-c cores] [-m memory_mb] [-a host_cores]

Launch a single VM using the specified cloud image overlay.

Options:
  -b base_image  Path to the base qcow2 image (default: plucky-server-cloudimg-amd64.img)
  -n name        Name for the VM instance (default: vm1)
  -p ssh_port    Host port exposed for SSH (default: 2222)
  -c cores       Number of vCPU cores (default: 2)
  -m memory_mb   Memory size in MiB (default: 2048)
  -a host_cores  Comma-separated list or range of host CPU cores to pin (e.g., 0-3 or 0,2)
  -h             Show this help message
EOF
}

BASE_IMG="plucky-server-cloudimg-amd64.img"
VM_NAME="vm1"
SSH_PORT=2222
VCPU_COUNT=2
MEMORY_MB=2048
HOST_CORES=""

while getopts ":b:n:p:c:m:a:h" opt; do
    case "$opt" in
        b) BASE_IMG=$OPTARG ;;
        n) VM_NAME=$OPTARG ;;
        p) SSH_PORT=$OPTARG ;;
        c) VCPU_COUNT=$OPTARG ;;
        m) MEMORY_MB=$OPTARG ;;
        a) HOST_CORES=$OPTARG ;;
        h)
            usage
            exit 0
            ;;
        :)
            echo "Option -$OPTARG requires an argument." >&2
            usage
            exit 1
            ;;
        \?)
            echo "Invalid option: -$OPTARG" >&2
            usage
            exit 1
            ;;
    esac
done

if ! [[ $SSH_PORT =~ ^[0-9]+$ ]] || [ "$SSH_PORT" -le 0 ] || [ "$SSH_PORT" -gt 65535 ]; then
    echo "Invalid SSH port: $SSH_PORT" >&2
    exit 1
fi

if ! [[ $VCPU_COUNT =~ ^[0-9]+$ ]] || [ "$VCPU_COUNT" -le 0 ]; then
    echo "Invalid CPU core count: $VCPU_COUNT" >&2
    exit 1
fi

if ! [[ $MEMORY_MB =~ ^[0-9]+$ ]] || [ "$MEMORY_MB" -le 0 ]; then
    echo "Invalid memory size: $MEMORY_MB" >&2
    exit 1
fi

if [ -n "$HOST_CORES" ] && ! [[ $HOST_CORES =~ ^[0-9,-]+$ ]]; then
    echo "Invalid host core list: $HOST_CORES" >&2
    exit 1
fi

BASE_IMG=$(readlink -f "$BASE_IMG")
if [ ! -f "$BASE_IMG" ]; then
    echo "Base image not found: $BASE_IMG" >&2
    exit 1
fi

WORKDIR=$(pwd)/vms
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SHARE_DIR="$(dirname "$SCRIPT_DIR")"
mkdir -p "$WORKDIR" "$SHARE_DIR"

KEYDIR="$WORKDIR/sshkey"
mkdir -p "$KEYDIR"
if [ ! -f "$KEYDIR/id_ed25519" ]; then
    echo "[+] Generating SSH key..."
    ssh-keygen -t ed25519 -N "" -f "$KEYDIR/id_ed25519"
else
    echo "[+] Using existing SSH key: $KEYDIR/id_ed25519"
fi
PUBKEY=$(cat "$KEYDIR/id_ed25519.pub")

create_seed() {
    local name=$1
    local dir=$WORKDIR/$name
    mkdir -p "$dir"
    cat > "$dir/user-data" <<EOF
#cloud-config
users:
  - name: u
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - $PUBKEY
ssh_pwauth: false
bootcmd:
  - [ mkdir, -p, /mnt/w ]
mounts:
  - [ "workloads", "/mnt/w", "9p", "trans=virtio,version=9p2000.L,msize=262144,rw,cache=none,_netdev", "0", "0" ]
EOF
    cat > "$dir/meta-data" <<EOF
instance-id: iid-$name
local-hostname: $name
EOF
    genisoimage -quiet -output "$dir/seed.iso" -volid cidata -joliet -rock "$dir/user-data" "$dir/meta-data"
}

create_overlay() {
    local name=$1
    qemu-img create -f qcow2 -b "$BASE_IMG" -F qcow2 "$WORKDIR/$name.qcow2" 20G
}

launch_vm() {
    local name=$1
    local ssh_port=$2
    local memory_mb=$3
    local vcpu_count=$4
    local host_cores=${5:-""}
    local mac=$(printf "52:54:00:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    if [ -f "$HOME/.ssh/known_hosts" ]; then
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:${ssh_port}" >/dev/null 2>&1 || true
    fi
    echo "[+] Launching $name (SSH port $ssh_port, ${vcpu_count} vCPU, ${memory_mb} MiB RAM)"
    local cmd=(
        qemu-system-x86_64
        -enable-kvm
        -m "$memory_mb" -smp "$vcpu_count"
        -drive "file=$WORKDIR/$name.qcow2,if=virtio"
        -drive "file=$WORKDIR/$name/seed.iso,if=virtio,media=cdrom"
        -nic "user,hostfwd=tcp::${ssh_port}-:22,model=virtio-net-pci,mac=${mac}"
        -fsdev "local,security_model=mapped,id=fsdev0,path=$SHARE_DIR"
        -device virtio-9p-pci,fsdev=fsdev0,mount_tag=workloads
        -display none -daemonize
        -name "$name"
    )
    if [ -n "$host_cores" ]; then
        echo "[+] Pinning $name to host cores: $host_cores"
        cmd=(taskset -c "$host_cores" "${cmd[@]}")
    fi
    nohup "${cmd[@]}" > "$WORKDIR/$name.log" 2>&1 || echo "❌ Failed to launch $name (see log)"
}

echo "=== Setting up $VM_NAME ==="
create_seed "$VM_NAME"
create_overlay "$VM_NAME"
launch_vm "$VM_NAME" "$SSH_PORT" "$MEMORY_MB" "$VCPU_COUNT" "$HOST_CORES"
echo "  -> SSH: ssh -i $KEYDIR/id_ed25519 u@localhost -p $SSH_PORT"

echo
echo "✅ VM launched successfully."
echo "Name: $VM_NAME"
echo "CPU cores: $VCPU_COUNT"
echo "Memory: ${MEMORY_MB} MiB"
echo "Shared folder: $SHARE_DIR (mounted as /mnt/w)"
echo "SSH key: $KEYDIR/id_ed25519"

