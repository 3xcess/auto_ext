from bcc import BPF
import ctypes
import subprocess
import time

from eval import evaluate, SystemLoad

# TODO: For now each workload is a single scheduler, ideally we could have overlapping workloads do something else too
SCHED_PATH = "/home/finale/scx"
scheds = {
    SystemLoad.CPU:     "build/scheds/c/scx_simple",
    SystemLoad.IO:      "target/release/scx_bpfland",
    SystemLoad.MEM:     "build/scheds/c/scx_simple",
    SystemLoad.NET:     "target/release/scx_bpfland",
    SystemLoad.IDLE:    "build/scheds/c/scx_central"
}
load = { }
for s_load in list(scheds.keys())[:-1]:
    load[s_load] = False

curr_load = SystemLoad.CPU

SLEEP_INTERVAL = 2
THRESHOLD = 500

p = subprocess.Popen([f'{SCHED_PATH}/{scheds[SystemLoad.CPU]}'], stdout=subprocess.DEVNULL)
while(True):
    b = BPF(text='BPF_TABLE_PINNED("hash", u64, u64, ba_bawm, 1024, "/sys/fs/bpf/ba_bawm");')
    
    # TODO: Move this logic to the individual ebpf programs
    # This should also include making a bool value to mark if the load is high or not
    for i, s_load in enumerate(load): 
        load[s_load] = True if b["ba_bawm"].get(ctypes.c_uint(i)).value >= THRESHOLD else False

    print(load)

    new_load = evaluate(*list(load.values()))
    if not (curr_load == new_load and load[new_load] == True):
        curr_load = new_load
        p.kill()
        p = subprocess.Popen([f'{SCHED_PATH}/{scheds[curr_load]}'], stdout=subprocess.DEVNULL)
        print(f"Switched to {scheds[curr_load]}, {curr_load.name}")

    b["ba_bawm"].clear()
    time.sleep(SLEEP_INTERVAL)
