# OpenCL-CTS podman build

This directory contains a `Makefile` and `Containerfile` that build the
[Khronos OpenCL Conformance Test Suite](https://github.com/KhronosGroup/OpenCL-CTS)
inside a `fedora:44` container and run it against one of several OpenCL backends.

## Quick start

```
make build                                          # build the image (~5-20 min, cached after)
make list-tests                                     # list every test executable in the image

# Run a single test via Mesa Rusticl + llvmpipe to exercise libclc — no GPU needed.
# (POCL does not depend on libclc; only Mesa Rusticl does.)
make smoke-test         # one test only — not a full conformance run
```

## Run targets

| Target | Backend | libclc | Devices forwarded |
|---|---|---|---|
| `run` | POCL (CPU) | no (pocl has no libclc dep) | none |
| `run-rusticl-cpu` | Mesa Rusticl + llvmpipe (CPU) | yes — runtime RPM dep of mesa-libOpenCL | none |
| `run-intel-rusticl` | Mesa Rusticl (Intel Iris/Xe) | yes — runtime RPM dep of mesa-libOpenCL | `/dev/dri` |
| `run-intel-gpu` | falls back to POCL (no GPU OCL backend installed) | no | `/dev/dri` |
| `run-amd-gpu` | falls back to POCL (no GPU OCL backend installed) | no | `/dev/kfd` + `/dev/dri` |

Every `run*` target runs `clinfo` first (with matching device flags) and logs
the output separately.

## Key variables

| Variable | Default | Purpose |
|---|---|---|
| `CTS_TESTS` | _(empty = all)_ | Space-separated ERE patterns matched against the full test path (substring or regex); a test runs if any pattern matches |
| `RUN_ENV` | _(empty)_ | Extra env vars forwarded into the container |
| `IMAGE_NAME` | `opencl-cts` | podman image tag |

Examples:

```
make run CTS_TESTS="test_api test_basic"         # two specific tests
make run CTS_TESTS="extensions"                  # all under extensions/
make run CTS_TESTS="test_(api|basic)"            # regex alternation
make run RUN_ENV="EXIT_ON_FAIL=1"
make run-intel-rusticl CTS_TESTS="test_svm"
```

## Logs

Every `build` and `run*` invocation writes to `logs/<target>.<timestamp>.log`
and updates `logs/<target>.log` as a symlink to the most recent file.  Logs
are kept for all runs; nothing is overwritten.

## Build decisions

**OpenCL-Headers** — the Fedora `opencl-headers` package lags behind the CTS
main branch.  The `Containerfile` clones
`https://github.com/KhronosGroup/OpenCL-Headers` directly into
`/opencl-cts/extern/OpenCL-Headers` and points `-DCL_INCLUDE_DIR` there.

**OpenCL ICD Loader** — uses `OpenCL-ICD-Loader` / `OpenCL-ICD-Loader-devel`
(Khronos official, v3.0.6) rather than `ocl-icd` (community, v2.3.4).

**SPIRV_INCLUDE_DIR=/usr** — the CTS CMake appends `include/spirv/` internally,
so the correct value is `/usr`, not `/usr/include` (which would double the
path component).

**POCL-only vendor directory** — `mesa-libOpenCL` is installed to support
`run-intel-rusticl`, but it also causes Rusticl to appear as platform 0 with
no device when `/dev/dri` is not forwarded.  A `/etc/OpenCL/vendors-pocl/`
directory is created in the image containing only `pocl.icd`; the `run`
target sets `OCL_ICD_VENDORS` to that directory to pin to POCL.
