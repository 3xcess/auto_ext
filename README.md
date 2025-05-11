# SCX Ba-Bawm

In dynamic environments with changing workloads, such as personal computers, the burden of selecting and dispatching the appropriate scheduler often falls on the user. In this project, we propose a method for automating workload profiling using eBPF. Our solution, called SCX Ba-Bawm, is a portable and system-agnostic package.

## Prerequisites
- Linux Kernel >= 6.12 (Or kernel patched to enable sched_ext and eBPF capabilities).
- sched_ext/scx (if patched kernel)
- python
- bcc/BPF

## Instructions to run
- Clone the repo: ``` git clone https://github.com/EddieFed/scx_ba_bawm ```
- Start the profilers: ```sudo sh ./start.sh```
- Start the automatic dispatcher: ```sudo python dispatcher.py```

## Demo
- We have the profilers already running on the system using the start script (top left)
- The dispatcher script is also displaying current system load (HIGH/LOW output from the individual profilers)
- We run a sample network load test (bottom left)
- The dispatcher correctly identifies the network heavy workload and switches to the correct scheduler (right half)
