from bcc import BPF
import ctypes
import subprocess
import time

SLEEP_INTERVAL = 2
THRESHOLD = 500

# TODO: Init automatically
load = {"CPU": False, "IO": False, "MEM": False, "NET": False}

bpf_source = f"""
BPF_TABLE_PINNED("hash", u64, u64, ba_bawm, 1024, "/sys/fs/bpf/ba_bawm");        
"""

while(True):
    b = BPF(text=bpf_source)
    
    for i in range(4):
        # TODO: This is fucked man, make an enum
        load[list(load.keys())[i]] = True if b["ba_bawm"].get(ctypes.c_uint(i)).value >= THRESHOLD else False
        print(b["ba_bawm"].get(ctypes.c_uint(i)).value)

    print(load)



    b["ba_bawm"].clear()
    time.sleep(SLEEP_INTERVAL)
