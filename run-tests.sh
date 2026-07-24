#!/usr/bin/env bash
# Runs OpenCL-CTS conformance test executables found under the build tree.
set -euo pipefail

BUILD_DIR="${BUILD_DIR:-/opencl-cts/build}"
TESTS_DIR="${BUILD_DIR}/test_conformance"
EXIT_ON_FAIL="${EXIT_ON_FAIL:-0}"
# Space-separated list of ERE patterns matched against the full test path.
# Each pattern is tested with bash =~; plain substrings and regexes both work.
# A test is included if any pattern matches.  Empty = run all.
CTS_TESTS="${CTS_TESTS:-}"

# ── Run parameters ────────────────────────────────────────────────────────────
echo "CTS_TESTS: ${CTS_TESTS:-(all)}"
echo ""

# ── Platform diagnostics ───────────────────────────────────────────────────────
echo "=== OpenCL platform info ==="
clinfo --list 2>/dev/null || clinfo 2>/dev/null || echo "(clinfo not available)"
echo ""

# ── Discover test executables ──────────────────────────────────────────────────
mapfile -t ALL_TESTS < <(
    find "${TESTS_DIR}" -name 'test_*' -type f -executable | sort
)

if [[ ${#ALL_TESTS[@]} -eq 0 ]]; then
    echo "ERROR: no test executables found under ${TESTS_DIR}" >&2
    exit 1
fi

# ── Filter by CTS_TESTS if set ─────────────────────────────────────────────────
if [[ -n "${CTS_TESTS}" ]]; then
    TESTS=()
    for exe in "${ALL_TESTS[@]}"; do
        for pattern in ${CTS_TESTS}; do
            if [[ "${exe}" =~ ${pattern} ]]; then
                TESTS+=("${exe}")
                break
            fi
        done
    done
    if [[ ${#TESTS[@]} -eq 0 ]]; then
        echo "ERROR: CTS_TESTS='${CTS_TESTS}' matched no test executables" >&2
        exit 1
    fi
else
    TESTS=("${ALL_TESTS[@]}")
fi

echo "Running ${#TESTS[@]} of ${#ALL_TESTS[@]} test executable(s)"
echo ""

# ── Run each test ──────────────────────────────────────────────────────────────
pass=0
fail=0
failed_tests=()

for exe in "${TESTS[@]}"; do
    name=$(basename "${exe}")
    dir=$(dirname "${exe}")
    echo "┌── ${name} ─────────────────────────────────────────────"
    if (cd "${dir}" && "${exe}"); then
        echo "└── PASS: ${name}"
        pass=$((pass + 1))
    else
        echo "└── FAIL: ${name}"
        fail=$((fail + 1))
        failed_tests+=("${name}")
        if [[ "${EXIT_ON_FAIL}" == "1" ]]; then
            break
        fi
    fi
    echo ""
done

# ── Summary ────────────────────────────────────────────────────────────────────
echo "=== Results ==="
echo "  Passed: ${pass}"
echo "  Failed: ${fail}"
if [[ ${#failed_tests[@]} -gt 0 ]]; then
    echo "  Failed tests:"
    for t in "${failed_tests[@]}"; do
        echo "    - ${t}"
    done
fi

[[ "${fail}" -eq 0 ]]
