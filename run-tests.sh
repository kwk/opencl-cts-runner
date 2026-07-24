#!/usr/bin/env bash
# Runs OpenCL-CTS via the upstream run_conformance.py script.
set -euo pipefail

CTS_DIR=/opencl-cts/test_conformance
BUILD_DIR=/opencl-cts/build/test_conformance
CTS_LIST="${CTS_LIST:-${CTS_DIR}/opencl_conformance_tests_quick.csv}"
CL_DEVICE_TYPE="${CL_DEVICE_TYPE:-CL_DEVICE_TYPE_DEFAULT}"
# Space-separated substring filters forwarded to run_conformance.py.
# A test is included if its name contains any of the given strings.
CTS_TESTS="${CTS_TESTS:-}"

# ── Run parameters ────────────────────────────────────────────────────────────
echo "CTS_LIST:       $(basename "${CTS_LIST}")"
echo "CL_DEVICE_TYPE: ${CL_DEVICE_TYPE}"
echo "CTS_TESTS:      ${CTS_TESTS:-(all)}"
echo ""

# ── Platform diagnostics ───────────────────────────────────────────────────────
echo "=== OpenCL platform info ==="
clinfo --list 2>/dev/null || clinfo 2>/dev/null || echo "(clinfo not available)"
echo ""

# ── Run conformance tests ─────────────────────────────────────────────────────
# run_conformance.py resolves test commands relative to CWD, so cd first.
# PYTHONWARNINGS suppresses SyntaxWarnings in the upstream script's regexes.
cd "${BUILD_DIR}"
exec env PYTHONWARNINGS=ignore::SyntaxWarning \
    python3 "${CTS_DIR}/run_conformance.py" \
        "${CTS_LIST}" \
        "${CL_DEVICE_TYPE}" \
        ${CTS_TESTS}
