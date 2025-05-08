from bcc import BPF
import ctypes
import time

HASH_KEY = ctypes.c_uint(1)

bpf_source = f"""
BPF_TABLE_PINNED("hash", u64, u64, ba_bawm, 1024, "/sys/fs/bpf/ba_bawm");

TRACEPOINT_PROBE(block, block_rq_issue) {{
    u64 key = {HASH_KEY.value};
    u64 zero = 0, *val;

    val = ba_bawm.lookup_or_init(&key, &zero);
    (*val) += 1;

    return 0;
}}
"""
b = BPF(text=bpf_source)

try:
    while True:
        time.sleep(3600)
except KeyboardInterrupt:
    print("Detaching and exiting.")
