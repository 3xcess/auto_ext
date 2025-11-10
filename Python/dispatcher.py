from bcc import BPF
import ctypes
import subprocess
import time
import os

from eval import evaluate, SystemLoad

# TODO: For now each workload is a single scheduler, ideally we could have overlapping workloads do something else too
SCHED_PATH = "./scx"
scheds = {
    SystemLoad.CPU:     "build/scheds/c/scx_simple",
    SystemLoad.IO:      "target/release/scx_bpfland",
    SystemLoad.MEM:     "build/scheds/c/scx_simple",
    SystemLoad.NET:     "target/release/scx_bpfland",
    SystemLoad.PARALLEL: "build/scheds/c/scx_simple",
    SystemLoad.IDLE:    "build/scheds/c/scx_central"
}
load = { }
for s_load in list(scheds.keys())[:-1]:
    load[s_load] = False

curr_load = SystemLoad.CPU

SLEEP_INTERVAL = 3
THRESHOLDS = {
        SystemLoad.CPU: 1000,
        SystemLoad.IO: 1000,
        SystemLoad.MEM: 1200,
        SystemLoad.NET: 800,
        SystemLoad.PARALLEL: None
}

def get_sys_cpus():
    try:
        return int(os.getenv("NUM_CPUS", os.cpu_count()))
    except Exception:
        return os.cpu_count()

THRESHOLDS[SystemLoad.PARALLEL] = get_sys_cpus()
print(f"Parallelism threshold set to {THRESHOLDS[SystemLoad.PARALLEL]}")

p = subprocess.Popen([f'{SCHED_PATH}/{scheds[SystemLoad.CPU]}'], stdout=subprocess.DEVNULL)
while(True):
    b = BPF(text='BPF_TABLE_PINNED("hash", u64, u64, ba_bawm, 1024, "/sys/fs/bpf/ba_bawm");')

    for i, s_load in enumerate(load):
        val = b["ba_bawm"].get(ctypes.c_uint(i))
        load_val = val.value if val is not None else 0
        threshold = THRESHOLDS[s_load]
        load[s_load] = load_val >= threshold if threshold is not None else False

    print(load)

    new_load = evaluate(*list(load.values()))
    if not (curr_load == new_load and load[new_load] == True):
        curr_load = new_load
        p.kill()
        p = subprocess.Popen([f'{SCHED_PATH}/{scheds[curr_load]}'], stdout=subprocess.DEVNULL)
        print(f"Switched to {scheds[curr_load]}, {curr_load.name}")

    #b["ba_bawm"].clear()
    for k in list(b["ba_bawm"].keys()):
        if int(k.value) != 4:
            del b["ba_bawm"][k]


    time.sleep(SLEEP_INTERVAL)