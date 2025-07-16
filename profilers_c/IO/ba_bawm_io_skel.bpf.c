#include "vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>

char LICENSE[] SEC("license") = "GPL";
struct {
    __uint(type, BPF_MAP_TYPE_HASH);
    __uint(max_entries, 1024);
    __type(key, __u64);
    __type(value, __u64);
    __uint(pinning, LIBBPF_PIN_BY_NAME);
} ba_bawm SEC(".maps");

SEC("tracepoint/block/block_rq_issue")

int handle_block_rq_issue(struct trace_event_raw_block_rq_issue *ctx) {
    __u64 key = 1;
    __u64 zero = 0, *val;

    val = bpf_map_lookup_elem(&ba_bawm, &key);
    if (!val) {
        bpf_map_update_elem(&ba_bawm, &key, &zero, BPF_ANY);
        val = &zero;
    }

    __sync_fetch_and_add(val, 1);
    return 0;
}