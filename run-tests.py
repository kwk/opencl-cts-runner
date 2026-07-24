#!/usr/bin/env python3
"""
OpenCL-CTS runner.

Parses the CSV test list, filters by device type and test name, runs each
test binary with CL_DEVICE_TYPE and CL_CONFORMANCE_RESULTS_FILENAME set, and
prints a pass/fail summary.  JSON result files are written to a per-run
subdirectory of LOG_DIR so they can later be compared with compare_results.py.
"""
import os
import re
import subprocess
import sys

CTS_DIR   = '/opencl-cts/test_conformance'
BUILD_DIR = '/opencl-cts/build/test_conformance'

_cts_list_raw  = os.environ.get('CTS_LIST',       'opencl_conformance_tests_quick.csv')
cts_list       = _cts_list_raw if os.path.isabs(_cts_list_raw) else os.path.join(CTS_DIR, _cts_list_raw)
cl_device_type = os.environ.get('CL_DEVICE_TYPE', 'CL_DEVICE_TYPE_DEFAULT')
cts_tests      = os.environ.get('CTS_TESTS',      '').split()
log_dir        = os.environ.get('LOG_DIR',        '')
run_target     = os.environ.get('RUN_TARGET',     'run')
log_stamp      = os.environ.get('LOG_STAMP',      '')

# ── Run parameters ────────────────────────────────────────────────────────────
print(f"CTS_LIST:       {os.path.basename(cts_list)}")
print(f"CL_DEVICE_TYPE: {cl_device_type}")
print(f"CTS_TESTS:      {' '.join(cts_tests) if cts_tests else '(all)'}")
print()

# ── Platform diagnostics ───────────────────────────────────────────────────────
print("=== OpenCL platform info ===")
r = subprocess.run(['clinfo', '--list'])
if r.returncode != 0:
    r = subprocess.run(['clinfo'])
if r.returncode != 0:
    print("(clinfo not available)")
print()

# ── Parse test list ───────────────────────────────────────────────────────────
tests = []
with open(cts_list) as f:
    for line in f:
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        parts = [p.strip() for p in line.split(',', 2)]
        if len(parts) == 3:
            row_device, row_name, row_cmd = parts
        else:
            row_device, row_name, row_cmd = '', parts[0], parts[1]

        # Skip device-type-restricted rows that don't match the active type.
        # CL_DEVICE_TYPE_ALL includes every row; DEFAULT skips restricted rows.
        if row_device and cl_device_type not in ('CL_DEVICE_TYPE_ALL', row_device):
            continue

        # Apply CTS_TESTS substring filter.
        if cts_tests and not any(f in row_name or f in row_cmd for f in cts_tests):
            continue

        tests.append((row_name, row_cmd))

print(f"Running {len(tests)} test(s)")
print()

# ── Set up JSON results directory ─────────────────────────────────────────────
json_dir = ''
if log_dir:
    stamp    = f'.{log_stamp}' if log_stamp else ''
    json_dir = f'{log_dir}/{run_target}.results{stamp}'
    os.makedirs(json_dir, exist_ok=True)
    print(f"JSON results → {json_dir}/")
    print()

# ── Run tests ─────────────────────────────────────────────────────────────────
passed        = 0
failed        = 0
failed_names  = []

for name, cmd in tests:
    print(f"┌── {name}")

    env = os.environ.copy()
    env['CL_DEVICE_TYPE'] = cl_device_type
    if json_dir:
        safe = re.sub(r'[^A-Za-z0-9._-]', '_', cmd)
        env['CL_CONFORMANCE_RESULTS_FILENAME'] = f'{json_dir}/{safe}.json'

    proc = subprocess.run(cmd, shell=True, cwd=BUILD_DIR, env=env)

    if proc.returncode == 0:
        print(f"└── PASS: {name}")
        passed += 1
    else:
        print(f"└── FAIL: {name}")
        failed += 1
        failed_names.append(name)
    print()

# ── Summary ───────────────────────────────────────────────────────────────────
print("=== Results ===")
print(f"  Passed: {passed}")
print(f"  Failed: {failed}")
if failed_names:
    print("  Failed tests:")
    for n in failed_names:
        print(f"    - {n}")

sys.exit(0 if failed == 0 else 1)
