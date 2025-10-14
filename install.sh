#!/bin/bash
set -e

echo "[*] Installing system dependencies..."
sudo apt update
sudo apt install -y git build-essential cmake clang llvm pkg-config \
    libelf-dev protobuf-compiler libseccomp-dev libbpf-dev rustup

if [ ! -d "sched_ext" ]; then
    echo "[*] Cloning sched_ext repository..."
    git clone https://github.com/sched-ext/scx.git
else
    echo "[*] sched_ext directory already exists, pulling latest changes..."
    cd scx
    git pull
    cd ..
fi


cd scx

echo "[*] Setting up Rust nightly..."
rustup install nightly
rustup override set nightly

echo "[*] Building C schedulers..."
make all
echo "[*] Installing C schedulers..."
make install INSTALL_DIR=~/bin
echo "[*] C schedulers install complete..."

echo "[*] Building Rust schedulers..."
cargo build --release
echo "[*] Installing Rust schedulers..."
ls -d scheds/rust/scx_* | xargs -I{} cargo install --path {}
echo "[*] Rust schedulers install complete"

cd ../profilers_c
echo "[*] Generating vmlinux.h"
bpftool btf dump file /sys/kernel/btf/vmlinux format c > vmlinux.h

echo "[*] Building C profilers"
make

cd ../

echo "[*] All done! scx-ba-bawm is ready to use."