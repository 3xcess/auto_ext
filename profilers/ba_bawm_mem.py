from bcc import BPF
import time
from ctypes import c_int

bpf = BPF(text="""
BPF_HASH(mem_cnt, u32, u64);

TRACEPOINT_PROBE(kmem, mm_page_alloc) {
    u32 key = 0;
    u64 zero = 0, *val;

    val = mem_cnt.lookup_or_try_init(&key, &zero);
    if (val) (*val) += 1;

    return 0;
}
""")

THRESHOLD = 500
INTERVAL = 5

print("Monitoring memory allocations...")
try:
    while True:
        time.sleep(INTERVAL)
        key = c_int(0)
        val = bpf["mem_cnt"].get(key)
        if val and val.value > THRESHOLD:
            print(f"Memory Activity: HIGH ({val.value} allocations)")
        else:
            print(f"Memory Activity: LOW ({val.value if val else 0} allocations)")
        bpf["mem_cnt"].clear()
except KeyboardInterrupt:
    print("Stopped.")

