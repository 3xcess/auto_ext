# SCX Ba-Bawm

In dynamic environments with changing workloads, such as personal computers, the burden of selecting and dispatching the appropriate scheduler often falls on the user. In this project, we propose a method for automating workload profiling using eBPF. Our solution, called SCX Ba-Bawm, is a portable and system-agnostic package.

This repository contains our current code for the implementations of the profilers and the dispatcher, a video demo, scripts to run the code, as well as the related [paper](https://github.com/EddieFed/scx_ba_bawm/blob/main/scx-Ba-Bawm.pdf).


## Prerequisites
- Linux Kernel >= 6.12 (Or kernel patched to enable sched_ext and eBPF capabilities).
- sched_ext/scx (if patched kernel)
- python
- bcc/BPF
- Optional:
  - tmux

Rest of the dependencies are handled by the install script

## Instructions to run
- Clone the repo: ``` https://github.com/3xcess/auto_ext.git ```
- Run the install script ```./install.sh```
- Start the profilers (choose any option):
  - Python Profilers ```./start.sh```
  - C profilers (recommended) ```./start_c.sh```
- Start the automatic dispatcher: ```sudo python dispatcher.py```

## Demo
- We have the profilers already running on the system using the start script (top left)
- The dispatcher script is also displaying current system load (HIGH/LOW output from the individual profilers)
- We run a sample network load test (bottom left)
- The dispatcher correctly identifies the network heavy workload and switches to the correct scheduler (right half)
![Demo](https://raw.githubusercontent.com/EddieFed/scx_ba_bawm/refs/heads/main/assets/demo.gif)



## Configuration & Benchmarking

## Setup

1. **Requirements**

    - Linux host with KVM enabled (`/dev/kvm` accessible).
    - QEMU system binaries (`qemu-system-x86_64`, `qemu-img`) and `genisoimage`.
    - OpenSSH client (used for provisioning and for the `supershell` backend).
    - Python 3.10+ for `supershell.py`.
    - An Ubuntu cloud image. We suggest to use [Ubuntu 25.05](https://cloud-images.ubuntu.com/plucky/current/) or newer (for [`sched_ext`](https://github.com/sched-ext/scx)), but you can supply your own when launching.

2. **Prerequisite.**
   ```bash
   sudo apt install -y genisoimage qemu-system-x86 git
   sudo usermod -aG kvm $USER    # Enable kvm w/o root priviledge
   newgrp kvm
   git clone https://github.com/sysec-uic/SelfTune-OS.git
   ```

   **Fetch a cloud image (e.g., Ubuntu 25.04).**
   ```bash
   cd SelfTune-OS
   wget https://cloud-images.ubuntu.com/plucky/current/plucky-server-cloudimg-amd64.img
   # Remember, use the same/similar version as your host machine to avoid 
   # any possible disparities within the binaries when built on the host
   # and run on the VMs.
   ```
3. **auto_ext Setup**
    ```bash
    ./config/shared/simple/core/install.sh
    ```

## Workflow
Run the following steps from the **host** machine.

### Launch and provision the VMs
```bash
cd config
mkdir results
./launch_3vms.sh
./ssh_vm.sh scp all -- setup_overlayfs.sh :/home/u
./ssh_vm.sh scp all -- autostart.sh :/home/u
./ssh_vm.sh scp all -- tests/perfbench.sh :/home/u #This will be updated to include other tests once available
./supershell.py
```

### Inside Supershell
```bash
sudo ./setup_overlayfs.sh
sudo ./autostart.sh
:q
```

### Re-enter Supershell to run benchmarks
```bash
./supershell.py
sudo ./tests/perfbench.sh
supersh> :pull /home/u/results ./results/
:q
```
### Results
Benchmark results will be stored on the host under:
```bash
auto_ext/config/results/
```

with subdirectories for each VM:
```bash
auto_ext/config/results/
├── vm1/
├── vm2/
└── vm3/
```