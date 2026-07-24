#!/bin/bash
# Mirrors the Containerfile fetch/configure/build steps for native execution.
set -exo pipefail

# ── Fetch OpenCL-CTS ──────────────────────────────────────────────────────────
git clone --depth=1 \
    https://github.com/KhronosGroup/OpenCL-CTS.git \
    /opencl-cts

# Apply KhronosGroup/OpenCL-CTS#2755 (--conformance-results-dir).
# TODO: remove once the PR is merged.
python3 -c "
import urllib.request, subprocess
r = urllib.request.urlopen('https://github.com/KhronosGroup/OpenCL-CTS/pull/2755.patch')
subprocess.run(['git', 'apply'], input=r.read(), cwd='/opencl-cts', check=True)
"

# Apply local patch (surfaces actual device from first test binary's output).
git -C /opencl-cts apply \
    "${TMT_TREE}/0002-run_conformance-print-device-info-parsed-from-first-.patch"

# ── Fetch OpenCL-Headers ──────────────────────────────────────────────────────
# The Fedora package lags; clone upstream so headers stay in sync with the CTS.
git clone --depth=1 \
    https://github.com/KhronosGroup/OpenCL-Headers.git \
    /opencl-cts/extern/OpenCL-Headers

# ── Configure ─────────────────────────────────────────────────────────────────
cmake -S /opencl-cts -B /opencl-cts/build \
    -G Ninja \
    -DCMAKE_BUILD_TYPE=Release \
    -DCL_INCLUDE_DIR=/opencl-cts/extern/OpenCL-Headers \
    -DCL_LIB_DIR=/usr/lib64 \
    -DSPIRV_INCLUDE_DIR=/usr \
    -DSPIRV_TOOLS_DIR=/usr/bin \
    -DOPENCL_LIBRARIES=OpenCL \
    -DGL_IS_SUPPORTED=OFF \
    -DVULKAN_IS_SUPPORTED=OFF

# ── Build ──────────────────────────────────────────────────────────────────────
cmake --build /opencl-cts/build --parallel "$(nproc)"

# ── POCL-only vendor directory ────────────────────────────────────────────────
# Prevents rusticl (no device without /dev/dri) from appearing as platform 0.
mkdir -p /etc/OpenCL/vendors-pocl
ln -s /etc/OpenCL/vendors/pocl.icd /etc/OpenCL/vendors-pocl/pocl.icd
