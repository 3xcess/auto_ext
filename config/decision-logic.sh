#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/../.." && pwd)"

RESULTS_LOG="$SCRIPT_DIR/results.log"
VM1_DETAIL="$SCRIPT_DIR/vm1-test_detail.txt"
VM2_DETAIL="$SCRIPT_DIR/vm2-test_detail.txt"
MAIN_JSON="$ROOT_DIR/dispatcher_config_main.json"
ALT_JSON="$ROOT_DIR/dispatcher_config_alt.json"

[[ -f "$RESULTS_LOG" && -f "$VM1_DETAIL" && -f "$VM2_DETAIL" ]] || { echo "[post-iter] Missing required logs (results/test_detail)." >&2; exit 0; }
[[ -f "$MAIN_JSON" && -f "$ALT_JSON" ]] || { echo "[post-iter] Missing dispatcher configs." >&2; exit 0; }

python3 - <<'PY'
import json, re, sys, os, random

script_dir = os.path.dirname(os.path.abspath(__file__))
root_dir = os.path.abspath(os.path.join(script_dir, '..', '..'))

results_log = os.path.join(script_dir, 'results.log')
vm1_d = os.path.join(script_dir, 'vm1-test_detail.txt')
vm2_d = os.path.join(script_dir, 'vm2-test_detail.txt')
main_path = os.path.join(root_dir, 'dispatcher_config_main.json')
alt_path = os.path.join(root_dir, 'dispatcher_config_alt.json')

def read(path):
    with open(path, 'r', encoding='utf-8', errors='ignore') as f:
        return f.read().splitlines()

res_lines = read(results_log)

# Extract last summary block and collect benchmarks where vm2 better
start = 0
for i, line in enumerate(res_lines):
    if line.startswith('=== Summary: vm2 vs vm1'):
        start = i
block = res_lines[start:]

vm2_better = []
for line in block:
    if re.search(r'\bvm2 better\s*$', line):
        # first column is benchmark name; handle possible padding
        name = line.split()[0]
        vm2_better.append(name)

if not vm2_better:
    print('[post-iter] No vm2-better cases in results.log; skipping config changes.')
    sys.exit(0)

detail1 = read(vm1_d)
detail2 = read(vm2_d)

def workload_keys_for(bench, detail_lines):
    keys = set()
    i = 0
    # accepted workload tokens
    valid = {'CPU','MEM','IO','NET','PARALLEL'}
    while i < len(detail_lines):
        line = detail_lines[i].strip()
        # header match variants
        hit = False
        if 'name=' + bench in line:
            hit = True
        else:
            m = re.match(r'^\[.*?\]\s*(.+)$', line)
            if m and bench == m.group(1).strip():
                hit = True
        if hit:
            i += 1
            # collect subsequent non-empty, non-header lines as categories
            while i < len(detail_lines):
                s = detail_lines[i].strip()
                if not s or s.startswith('['):
                    break
                # extract tokens; accept comma/space separated
                for tok in re.split(r'[^A-Z]+', s.upper()):
                    if tok in valid:
                        keys.add(tok)
                i += 1
            # do not break; continue to find other blocks for same bench
        else:
            i += 1
    return keys

work_keys = set()
for b in vm2_better:
    work_keys |= workload_keys_for(b, detail1)
    work_keys |= workload_keys_for(b, detail2)

if not work_keys:
    print('[post-iter] No workload keys found for vm2-better cases; nothing to sync.')
    sys.exit(0)

with open(main_path, 'r', encoding='utf-8') as f:
    main = json.load(f)
with open(alt_path, 'r', encoding='utf-8') as f:
    alt = json.load(f)

ms = main.get('scheds', {})
asched = alt.get('scheds', {})

changed = []
for k in sorted(work_keys):
    if k in ms and k in asched and ms[k] != asched[k]:
        ms[k] = asched[k]
        changed.append(k)

if changed:
    with open(main_path, 'w', encoding='utf-8') as f:
        json.dump(main, f, indent=2)
    print('[post-iter] Updated main keys from alt: ' + ', '.join(changed))
else:
    print('[post-iter] No differing keys to update in main.')

# Randomize one key in alt from allowed list
choices = [
    'build/scheds/c/scx_simple',
    'target/release/scx_bpfland',
    'build/scheds/c/scx_central',
    'build/scheds/c/scx_prev',
    'target/release/scx_flash',
]
if asched:
    rk = random.choice(list(asched.keys()))
    cur = asched[rk]
    new = random.choice(choices)
    # allow same value occasionally; keep simple
    asched[rk] = new
    with open(alt_path, 'w', encoding='utf-8') as f:
        json.dump(alt, f, indent=2)
    print(f"[post-iter] Alt key '{rk}' randomized to: {new}")
else:
    print('[post-iter] Alt scheds empty; nothing to randomize.')
PY

exit 0
