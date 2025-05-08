from bcc import BPF
from ctypes import c_uint
import time

bpf_text = """
BPF_HASH(cpu_cs_count, u32, u64);

TRACEPOINT_PROBE(sched, sched_switch) {
    u32 key = 0;
    u64 *val = cpu_cs_count.lookup(&key);
    if (val) {
        (*val) += 1;
    } else {
        u64 init = 1;
        cpu_cs_count.update(&key, &init);
    }
    return 0;
}
"""

b = BPF(text=bpf_text)

KEY = c_uint(0)

THRESHOLD = 1000
INTERVAL = 5

print("Monitoring CPU context switches...")

while True:
    time.sleep(INTERVAL)
    val = b["cpu_cs_count"].get(KEY)
    count = val.value if val else 0

    status = "HIGH" if count >= THRESHOLD else "LOW"
    print(f"[{count} context switches] CPU Activity: {status}")

    b["cpu_cs_count"].clear()

