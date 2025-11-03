#!/bin/bash
set -e

echo "[*] Installing system dependencies..."
sudo apt update
sudo apt install -y git build-essential cmake clang llvm pkg-config \
    libelf-dev libseccomp-dev libbpf-dev python-is-python3

echo "[*] Core Dependencies Installed."