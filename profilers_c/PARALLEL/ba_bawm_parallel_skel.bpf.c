#include "../vmlinux.h"
#include <bpf/bpf_helpers.h>
#include <bpf/bpf_tracing.h>
#include <bpf/bpf_core_read.h>

char LICENSE[] SEC("license") = "GPL";

struct {
        __uint(type, BPF_MAP_TYPE_HASH);
        __uint(max_entries, 1024);
        __type(key, __u64);
        __type(value, __s64);
        __uint(pinning, LIBBPF_PIN_BY_NAME);
} ba_bawm SEC(".maps");

SEC("tracepoint/sched/sched_wakeup")
int handle_sched_wakeup(struct trace_event_raw_sched_wakeup *ctx) {
        __u64 key = 4;
        __s64 zero = 0;
        __s64 *val;

        val = bpf_map_lookup_elem(&ba_bawm, &key);
        if (!val) {
                bpf_map_update_elem(&ba_bawm, &key, &zero, BPF_ANY);
                val = &zero;
        }

        __sync_fetch_and_add(val, 1); // runnable++
        return 0;
}


SEC("tracepoint/sched/sched_switch")
int handle_sched_switch(struct trace_event_raw_sched_switch *ctx) {
        __u64 key = 4;
        __s64 zero = 0;
        __s64 *val;

        val = bpf_map_lookup_elem(&ba_bawm, &key);
        if (!val) {
                bpf_map_update_elem(&ba_bawm, &key, &zero, BPF_ANY);
                val = &zero;
        }


        if (ctx->prev_state != UTASK_RUNNING) {
                __sync_fetch_and_sub(val, 1); //runnable--
                if (*val < 0){
                        *val = 0;
                }
        }
        return 0;
}