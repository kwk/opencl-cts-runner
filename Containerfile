FROM fedora:44

# ── Build dependencies ─────────────────────────────────────────────────────────
# OpenCL-ICD-Loader-devel → /usr/lib64/libOpenCL.so (CL_LIB_DIR=/usr/lib64)
# spirv-headers-devel → /usr/include/spirv/ (SPIRV_INCLUDE_DIR=/usr)
# spirv-tools      → /usr/bin/spirv-as, spirv-val (SPIRV_TOOLS_DIR=/usr/bin)
# pocl             → CPU-based OpenCL implementation (runs without GPU hardware)
RUN dnf install -y --setopt=install_weak_deps=False \
        git \
        cmake \
        make \
        ninja-build \
        gcc-c++ \
        python3 \
        OpenCL-ICD-Loader \
        OpenCL-ICD-Loader-devel \
        spirv-headers-devel \
        spirv-tools \
        pocl \
        mesa-libOpenCL \
        clinfo \
    && dnf clean all

# ── Fetch source ───────────────────────────────────────────────────────────────
RUN git clone --depth=1 \
        https://github.com/KhronosGroup/OpenCL-CTS.git \
        /opencl-cts

# Apply KhronosGroup/OpenCL-CTS#2755 (--conformance-results-dir for run_conformance.py).
# TODO: remove once the PR is merged.
RUN python3 -c "\
import urllib.request, subprocess; \
r = urllib.request.urlopen('https://github.com/KhronosGroup/OpenCL-CTS/pull/2755.patch'); \
subprocess.run(['git', 'apply'], input=r.read(), cwd='/opencl-cts', check=True)"

# Print the device actually selected by the first test binary so the log
# reflects which platform ran the tests (not just what clinfo reports).
COPY 0002-run_conformance-print-device-info-parsed-from-first-.patch /tmp/0002.patch
RUN git -C /opencl-cts apply /tmp/0002.patch && rm /tmp/0002.patch

# The Fedora opencl-headers package lags behind the CTS main branch
# (e.g. CL_COMMAND_BUFFER_STATE_FINALIZED_KHR is missing).  Clone the
# upstream headers directly so they stay in sync with the CTS source.
RUN git clone --depth=1 \
       https://github.com/KhronosGroup/OpenCL-Headers.git \
       /opencl-cts/extern/OpenCL-Headers

WORKDIR /opencl-cts

# ── Configure ──────────────────────────────────────────────────────────────────
RUN cmake -S . -B build \
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
RUN cmake --build build --parallel "$(nproc)"

# ── Extra ICD vendor directories ───────────────────────────────────────────────
# A POCL-only vendor dir lets run targets restrict to the CPU platform via
# OCL_ICD_VENDORS=/etc/OpenCL/vendors-pocl, preventing the rusticl platform
# (which has no device without /dev/dri) from appearing as platform 0.
RUN mkdir -p /etc/OpenCL/vendors-pocl \
    && ln -s /etc/OpenCL/vendors/pocl.icd /etc/OpenCL/vendors-pocl/pocl.icd

# ── Entrypoint ─────────────────────────────────────────────────────────────────
COPY run-tests.sh /usr/local/bin/run-tests.sh
RUN chmod +x /usr/local/bin/run-tests.sh

WORKDIR /opencl-cts/build

CMD ["/usr/local/bin/run-tests.sh"]
