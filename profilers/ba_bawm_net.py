from bcc import BPF
import time
from ctypes import c_int

bpf = BPF(text="""
BPF_HASH(net_cnt, u32, u64);

TRACEPOINT_PROBE(net, net_dev_queue) {
    u32 key = 0;
    u64 zero = 0, *val;

    val = net_cnt.lookup_or_try_init(&key, &zero);
    if (val) (*val) += 1;

    return 0;
}
""")

print("Monitoring network activity...")
try:
    while True:
        time.sleep(5)
        key = c_int(0)
        val = bpf["net_cnt"].get(key)
        if val and val.value > 500:
            print(f"Network Activity: HIGH ({val.value} packets in 2s)")
        else:
            print(f"Network Activity: LOW ({val.value if val else 0} packets in 2s)")
        bpf["net_cnt"].clear()
except KeyboardInterrupt:
    print("Stopped.")

