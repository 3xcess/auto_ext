PROFILERS := CPU IO MEM NET

.PHONY: all clean $(PROFILERS)

all: $(PROFILERS)

$(PROFILERS):
        @echo ">>> Building $@ profiler..."
        @lc=$(shell echo $@ | tr '[:upper:]' '[:lower:]'); \
                clang -O2 -g -target bpf -D__TARGET_ARCH_x86 -c $@/ba_bawm_$${lc}_skel.bpf.c -o $@/ba_bawm_$${lc}_skel.bpf.o; \
                bpftool gen skeleton $@/ba_bawm_$${lc}_skel.bpf.o > $@/ba_bawm_$${lc}.skel.h; \
                gcc -O2 -g -o $@/ba_bawm_$${lc} $@/ba_bawm_$${lc}.c -lbpf

clean:
        rm -f CPU/*.o CPU/*.skel.h CPU/ba_bawm_cpu \
                IO/*.o IO/*.skel.h IO/ba_bawm_io \
                MEM/*.o MEM/*.skel.h MEM/ba_bawm_mem \
                NET/*.o NET/*.skel.h NET/ba_bawm_net
