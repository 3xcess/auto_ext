from bcc import BPF
from ctypes import c_uint
import time

bpf_source = """
BPF_HASH(io_count, u32, u64, 1);

TRACEPOINT_PROBE(block, block_rq_issue) {
    u32 key = 0;
    u64 zero = 0, *val;

    val = io_count.lookup_or_init(&key, &zero);
    (*val) += 1;
    return 0;
}
"""

b = BPF(text=bpf_source)
io_count = b["io_count"]

KEY = c_uint(0)

THRESHOLD = 500
INTERVAL = 5

print("Monitoring block I/O activity...")
while True:
    time.sleep(INTERVAL)

    val = io_count[KEY].value if KEY in io_count else 0
    status = "HIGH" if val >= THRESHOLD else "LOW"
    print(f"[{val} requests] I/O Activity: {status}")

    io_count.clear()

