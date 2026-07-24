#!/usr/bin/env bash
# Thin wrapper around run_conformance.py.
# Prints platform info, sets up the per-run JSON results directory, then
# delegates to the upstream script (which handles CSV parsing, device-type
# filtering, CL_DEVICE_TYPE env var, and CL_CONFORMANCE_RESULTS_FILENAME).
set -euo pipefail

CTS_DIR=/opencl-cts/test_conformance
BUILD_DIR=/opencl-cts/build/test_conformance
CTS_LIST="${CTS_LIST:-opencl_conformance_tests_quick.csv}"
CL_DEVICE_TYPE="${CL_DEVICE_TYPE:-CL_DEVICE_TYPE_DEFAULT}"
CTS_TESTS="${CTS_TESTS:-}"
LOG_DIR="${LOG_DIR:-}"
RUN_TARGET="${RUN_TARGET:-run}"
LOG_STAMP="${LOG_STAMP:-$(date +%Y-%m-%dT%H-%M-%S)}"

# Resolve a bare filename to the CTS source directory.
[[ "${CTS_LIST}" != /* ]] && CTS_LIST="${CTS_DIR}/${CTS_LIST}"

# ── Run parameters ────────────────────────────────────────────────────────────
echo "CTS_LIST:       $(basename "${CTS_LIST}")"
echo "CL_DEVICE_TYPE: ${CL_DEVICE_TYPE}"
echo "CTS_TESTS:      ${CTS_TESTS:-(all)}"
echo ""

# ── Platform diagnostics ───────────────────────────────────────────────────────
echo "=== OpenCL platform info ==="
clinfo --list 2>/dev/null || clinfo 2>/dev/null || echo "(clinfo not available)"
echo ""

# ── Per-run JSON results directory ────────────────────────────────────────────
RESULTS_ARG=""
if [[ -n "${LOG_DIR}" ]]; then
    stamp="${LOG_STAMP:+.${LOG_STAMP}}"
    JSON_DIR="${LOG_DIR}/${RUN_TARGET}.results${stamp}"
    mkdir -p "${JSON_DIR}"
    RESULTS_ARG="--conformance-results-dir=${JSON_DIR}"
fi

# ── Run conformance tests ─────────────────────────────────────────────────────
# run_conformance.py resolves test commands relative to CWD, so cd first.
# PYTHONWARNINGS suppresses SyntaxWarnings in the script's regexes.
cd "${BUILD_DIR}"
exec env PYTHONWARNINGS=ignore::SyntaxWarning \
    python3 "${CTS_DIR}/run_conformance.py" \
        "${CTS_LIST}" \
        "${CL_DEVICE_TYPE}" \
        ${RESULTS_ARG} \
        ${CTS_TESTS}
