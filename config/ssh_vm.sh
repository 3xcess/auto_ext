#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
SSH_KEY="$SCRIPT_DIR/vms/sshkey/id_ed25519"
USER="u"
HOST="localhost"

usage() {
    cat <<EOF >&2
Usage:
  $0 [ssh] <vm1|vm2|1|2> [--] [remote command...]
  $0 ssh all -- [remote command...]
  $0 scp <vm1|vm2|1|2> [--] <src...> <dest>
  $0 scp all -- <src...> <dest>

Examples:
  $0 vm2
  $0 ssh 3 -- uname -a
  $0 scp vm1 -- shared/setup_overlayfs.sh :/home/u/
  $0 scp 2 -- -r shared/simple :/home/u/simple
  $0 scp all -- shared/hostfile :/home/u/
  (prefix guest paths with ':' to target the VM, e.g. :/home/u/)
EOF
    exit 1
}

[ $# -ge 1 ] || usage

action="ssh"
case "$1" in
    ssh|scp)
        action=$1
        shift
        ;;
esac

[ $# -ge 1 ] || usage

resolve_vm() {
    case "$1" in
        vm1|1) printf '%s %s\n' "vm1" "2221" ;;
        vm2|2) printf '%s %s\n' "vm2" "2222" ;;
        *) return 1 ;;
    esac
}

run_scp_for_vm() {
    local label="$1"
    local port="$2"
    shift 2
    local expanded=()
    for arg in "$@"; do
        if [[ "$arg" == :* ]]; then
            expanded+=("${USER}@${HOST}${arg}")
        else
            expanded+=("$arg")
        fi
    done
    echo "[vm-connect] scp -> $label ($HOST:$port)"
    scp \
        "${COMMON_OPTS[@]}" \
        -P "$port" \
        "${expanded[@]}"
}

if [ ! -f "$SSH_KEY" ]; then
    echo "SSH key not found: $SSH_KEY" >&2
    echo "Launch the VMs first so the key is generated." >&2
    exit 1
fi

COMMON_OPTS=(-i "$SSH_KEY" -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null)

if [ "$action" = "ssh" ]; then
    target="$1"
    shift
    if [ "$target" = "all" ]; then
        if [ "${1:-}" = "--" ]; then
            shift
        fi
        if [ $# -lt 1 ]; then
            echo "ssh all requires a remote command (non-interactive)." >&2
            usage
        fi
        all_args=("$@")
        pids=()
        for vm in vm1 vm2; do
            if ! read -r label port < <(resolve_vm "$vm"); then
                echo "Unknown VM selector: $vm" >&2
                exit 1
            fi
            echo "[vm-connect] ssh -> $label ($HOST:$port) [parallel]"
            (
                ssh \
                    "${COMMON_OPTS[@]}" \
                    -p "$port" \
                    "$USER@$HOST" \
                    "${all_args[@]}"
            ) | sed -u "s/^/[$label] /" &
            pids+=("$!")
        done
        status=0
        for pid in "${pids[@]}"; do
            if ! wait "$pid"; then
                status=1
            fi
        done
        exit "$status"
    fi
    if ! read -r label port < <(resolve_vm "$target"); then
        echo "Unknown VM selector: $target" >&2
        usage
    fi
    if [ "${1:-}" = "--" ]; then
        shift
    fi
    echo "[vm-connect] ssh -> $label ($HOST:$port)"
    exec ssh \
        "${COMMON_OPTS[@]}" \
        -p "$port" \
        "$USER@$HOST" \
        "$@"
fi

if [ "$action" = "scp" ]; then
    target="$1"
    shift
    if [ "$target" = "all" ]; then
        if [ "${1:-}" = "--" ]; then
            shift
        fi
        if [ $# -lt 2 ]; then
            usage
        fi
        all_args=("$@")
        for vm in vm1 vm2; do
            if ! read -r label port < <(resolve_vm "$vm"); then
                echo "Unknown VM selector: $vm" >&2
                exit 1
            fi
            run_scp_for_vm "$label" "$port" "${all_args[@]}"
        done
        exit 0
    fi
    if ! read -r label port < <(resolve_vm "$target"); then
        echo "Unknown VM selector: $target" >&2
        usage
    fi
    if [ "${1:-}" = "--" ]; then
        shift
    fi
    if [ $# -lt 2 ]; then
        usage
    fi
    run_scp_for_vm "$label" "$port" "$@"
    exit 0
fi

echo "Unknown action: $action" >&2
usage

