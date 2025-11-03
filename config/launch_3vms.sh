#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<EOF
Usage: $(basename "$0") [-b base_image] [-a core_sets]

Launch three VMs. Optionally pin each VM's QEMU process to specific host CPUs.

Options:
  -b base_image  Path to the base qcow2 image (default: plucky-server-cloudimg-amd64.img)
  -a core_sets   Semicolon-separated host CPU specs per VM (vm1;vm2;vm3), e.g. "0-1;2,3;4-5"
  -h             Show this help message

Passing a positional argument for the base image is still supported for backward compatibility.
EOF
}

BASE_IMG="plucky-server-cloudimg-amd64.img"
HOST_CORES_LIST=""

while getopts ":b:a:h" opt; do
    case "$opt" in
        b) BASE_IMG=$OPTARG ;;
        a) HOST_CORES_LIST=$OPTARG ;;
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
shift $((OPTIND - 1))

if [ $# -ge 1 ]; then
    BASE_IMG=$1
    shift
fi

if [ $# -gt 0 ]; then
    echo "Unexpected arguments: $*" >&2
    usage
    exit 1
fi

if [ ! -f "$BASE_IMG" ]; then
    echo "Base image not found: $BASE_IMG"
    exit 1
fi
BASE_IMG=$(readlink -f "$BASE_IMG")

declare -a HOST_CORES=()
if [ -n "$HOST_CORES_LIST" ]; then
    IFS=';' read -r -a HOST_CORES <<< "$HOST_CORES_LIST"
fi

validate_host_cores() {
    local spec=$1
    if [ -n "$spec" ] && ! [[ $spec =~ ^[0-9,-]+$ ]]; then
        echo "Invalid host core specification: $spec" >&2
        exit 1
    fi
}

for spec in "${HOST_CORES[@]}"; do
    clean_spec=${spec//[[:space:]]/}
    validate_host_cores "$clean_spec"
done

for idx in "${!HOST_CORES[@]}"; do
    HOST_CORES[$idx]=${HOST_CORES[$idx]//[[:space:]]/}
done

WORKDIR=$(pwd)/vms
SHARE_DIR=$(pwd)/shared
mkdir -p "$WORKDIR" "$SHARE_DIR"

# === Generate SSH key (if not exist) ===
KEYDIR="$WORKDIR/sshkey"
mkdir -p "$KEYDIR"
if [ ! -f "$KEYDIR/id_ed25519" ]; then
    echo "[+] Generating SSH key..."
    ssh-keygen -t ed25519 -N "" -f "$KEYDIR/id_ed25519"
else
    echo "[+] Using existing SSH key: $KEYDIR/id_ed25519"
fi
PUBKEY=$(cat "$KEYDIR/id_ed25519.pub")

# === Functions ===
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
    local host_cores=${3:-""}
    local mac=$(printf "52:54:00:%02x:%02x:%02x" $((RANDOM%256)) $((RANDOM%256)) $((RANDOM%256)))
    if [ -f "$HOME/.ssh/known_hosts" ]; then
        # Drop any stale host key so fresh guests don't trigger SSH warnings
        ssh-keygen -f "$HOME/.ssh/known_hosts" -R "[localhost]:${ssh_port}" >/dev/null 2>&1 || true
    fi
    if [ -n "$host_cores" ]; then
        echo "[+] Launching $name (SSH port $ssh_port, pinned to host cores: $host_cores)"
    else
        echo "[+] Launching $name (SSH port $ssh_port)"
    fi
    local cmd=(
        qemu-system-x86_64
        -enable-kvm
        -m 2048 -smp 2
        -drive "file=$WORKDIR/$name.qcow2,if=virtio"
        -drive "file=$WORKDIR/$name/seed.iso,if=virtio,media=cdrom"
        -nic "user,hostfwd=tcp::${ssh_port}-:22,model=virtio-net-pci,mac=${mac}"
        -fsdev "local,security_model=mapped,id=fsdev0,path=$SHARE_DIR"
        -device virtio-9p-pci,fsdev=fsdev0,mount_tag=workloads
        -display none -daemonize
        -name "$name"
    )
    if [ -n "$host_cores" ]; then
        cmd=(taskset -c "$host_cores" "${cmd[@]}")
    fi
    nohup "${cmd[@]}" > "$WORKDIR/$name.log" 2>&1 || echo "❌ Failed to launch $name (see log)"
}

# === Main loop ===
for i in 1 2 3; do
    name="vm${i}"
    port=$((2220 + i))
    host_spec=""
    if [ "${#HOST_CORES[@]}" -ge "$i" ]; then
        host_spec=${HOST_CORES[$((i - 1))]}
    fi
    echo "=== Setting up $name ==="
    create_seed "$name"
    create_overlay "$name"
    launch_vm "$name" "$port" "$host_spec"
    echo "  -> $name SSH: ssh -i $KEYDIR/id_ed25519 u@localhost -p $port"
done

echo
echo "✅ All VMs launched successfully."
echo "Shared folder: $SHARE_DIR (mounted as /mnt/workloads)"
echo "SSH key: $KEYDIR/id_ed25519"
