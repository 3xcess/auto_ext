from bcc import BPF
from system_load_enum import SystemLoad
import ctypes
import subprocess
import time
import os
import json
import sys
from datetime import datetime, timezone

from eval import evaluate

# ---- Argument parsing ----
# Patterns:
#   dispatcher.py
#   dispatcher.py alt
#   dispatcher.py vm1
#   dispatcher.py alt vm2
args = sys.argv[1:]

cfg_name = "dispatcher_config_main.json"
vm_id = None

if args:
    if args[0] == "alt":
        cfg_name = "dispatcher_config_alt.json"
        args = args[1:]

    if args:
        vm_id = args[0]

# print(f"[dispatcher] Using configuration: {cfg_name}")
# if(args):
#   print("logging = ACTIVE")

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
cfg_path = os.path.join(SCRIPT_DIR, cfg_name)


LOG_DIR = os.path.join(SCRIPT_DIR, "config", "tests")
if vm_id is not None:
    os.makedirs(LOG_DIR, exist_ok=True)
    SCHED_LOG_PATH = os.path.join(LOG_DIR, f"{vm_id}-test_detail.txt")
else:
    SCHED_LOG_PATH = None

def reload_scheds():
    global config, SCHED_PATH, scheds
    with open(cfg_path, "r", encoding="utf-8") as f:
        config = json.load(f)
    SCHED_PATH = config["SCHED_PATH"]
    scheds = {SystemLoad[k]: v for k, v in config["scheds"].items()}

reload_scheds()
last_mtime = os.path.getmtime(cfg_path)

#print(scheds)

load = {}
for s_load in list(scheds.keys())[:-1]:
    load[s_load] = False

curr_load = SystemLoad.CPU

SLEEP_INTERVAL = 3
THRESHOLDS = {
    SystemLoad.CPU: 1000,
    SystemLoad.IO: 1000,
    SystemLoad.MEM: 2000,
    SystemLoad.NET: 1000,
    SystemLoad.PARALLEL: None,
}

def get_sys_cpus():
    try:
        return int(os.getenv("NUM_CPUS", os.cpu_count()))
    except Exception:
        return os.cpu_count()

THRESHOLDS[SystemLoad.PARALLEL] = get_sys_cpus()
#print(f"Parallelism threshold set to {THRESHOLDS[SystemLoad.PARALLEL]}")

def log_load_switch(load_enum: SystemLoad):
    if SCHED_LOG_PATH is None:
        return
    ts = datetime.now(timezone.utc).isoformat()
    line = f"[{ts}] load={load_enum.name}\n"
    try:
        with open(SCHED_LOG_PATH, "a", encoding="utf-8") as f:
            f.write(line)
    except Exception:
        pass


p = subprocess.Popen(
    [f"{SCHED_PATH}/{scheds[SystemLoad.CPU]}"],
    stdout=subprocess.DEVNULL
)



b = BPF(text="""
BPF_TABLE_PINNED("hash", u64, u64, ba_bawm, 1024, "/sys/fs/bpf/ba_bawm");
""")
ba_bawm = b["ba_bawm"]

while True:
    try:
        mtime = os.path.getmtime(cfg_path)
        if mtime != last_mtime:
            last_mtime = mtime
            reload_scheds()
    except FileNotFoundError:
        pass


    for i, s_load in enumerate(load):
        val = ba_bawm.get(ctypes.c_uint(i))
        load_val = val.value if val is not None else 0
        threshold = THRESHOLDS[s_load]
        load[s_load] = load_val >= threshold if threshold is not None else False
    
    # print(load)

    new_load = evaluate(*list(load.values()))
    if not (curr_load == new_load and load[new_load] is True):
        curr_load = new_load
        p.kill()
        p = subprocess.Popen(
            [f"{SCHED_PATH}/{scheds[curr_load]}"],
            stdout=subprocess.DEVNULL
        )
        log_load_switch(curr_load)
        # print(f"\n==========\nSwitched to {scheds[curr_load]}, {curr_load.name}\n==========\n")

    #b["ba_bawm"].clear()
    for k in list(ba_bawm.keys()):
        if int(k.value) != 4:
            del ba_bawm[k]

    time.sleep(SLEEP_INTERVAL)