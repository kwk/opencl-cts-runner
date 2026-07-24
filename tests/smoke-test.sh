#!/bin/bash
# Runs the Printf conformance test natively (no container) and compares
# results against the golden reference.
set -exo pipefail

CTS_DIR=/opencl-cts/test_conformance
BUILD_DIR=/opencl-cts/build/test_conformance
CTS_LIST=opencl_conformance_tests_quick.csv
CL_DEVICE_TYPE=CL_DEVICE_TYPE_CPU
CTS_TESTS="Printf"
JSON_DIR=/tmp/smoke-test-results

mkdir -p "${JSON_DIR}"

# ── Platform diagnostics ──────────────────────────────────────────────────────
clinfo --list

# ── Run conformance test ──────────────────────────────────────────────────────
cd "${BUILD_DIR}"
RUSTICL_ENABLE=llvmpipe \
PYTHONWARNINGS=ignore::SyntaxWarning \
    python3 "${CTS_DIR}/run_conformance.py" \
        "${CTS_DIR}/${CTS_LIST}" \
        "${CL_DEVICE_TYPE}" \
        --conformance-results-dir="${JSON_DIR}" \
        ${CTS_TESTS}

# ── Compare against golden reference ─────────────────────────────────────────
python3 /opencl-cts/ci/compare_results.py \
    --golden "${TMT_TREE}/logs/example-comparison/golden/Printf.json" \
    --results-dir "${JSON_DIR}"
