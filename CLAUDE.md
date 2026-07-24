# OpenCL-CTS podman build — developer notes

This file captures non-obvious decisions for future reference. For usage, see README.md.

## Key files

| File | Purpose |
|---|---|
| `Containerfile` | Builds the image: installs deps, clones CTS + OpenCL-Headers, CMake build |
| `Makefile` | All make targets; see `make help` |
| `run-tests.sh` | Container entrypoint: prints platform info, sets up JSON dir, calls `run_conformance.py` |
| `logs/` | All log and JSON result files land here (mounted into the container at `/logs`) |

## Build decisions

**OpenCL-Headers** — the Fedora `opencl-headers` package lags behind the CTS
main branch (e.g. missing `CL_COMMAND_BUFFER_STATE_FINALIZED_KHR`).
`https://github.com/KhronosGroup/OpenCL-Headers` is cloned separately into
`/opencl-cts/extern/OpenCL-Headers` and `-DCL_INCLUDE_DIR` points there.

**OpenCL ICD Loader** — uses `OpenCL-ICD-Loader` / `OpenCL-ICD-Loader-devel`
(Khronos official, v3.0.6) rather than `ocl-icd` (community, v2.3.4).

**SPIRV_INCLUDE_DIR=/usr** — the CTS CMake appends `include/spirv/` internally,
so the correct value is `/usr`, not `/usr/include` (which doubles the path).

**POCL-only vendor directory** — `mesa-libOpenCL` is installed for Rusticl
support, but it also registers rusticl as platform 0 with no device when
`/dev/dri` is not forwarded, breaking POCL-only runs.  A
`/etc/OpenCL/vendors-pocl/` directory is created containing only `pocl.icd`
so the `run` target can restrict the ICD loader via `OCL_ICD_VENDORS`.

**libclc** — only `mesa-libOpenCL` (Rusticl) has libclc as a runtime RPM dep;
POCL does not.  Use `run-rusticl-cpu` (llvmpipe, no GPU needed) or
`run-intel-rusticl` to exercise libclc.

**kwk/OpenCL-CTS fork** — the fork branch `add-conformance-results-dir-option`
adds `--conformance-results-dir=<DIR>` to `run_conformance.py`, which sets
`CL_CONFORMANCE_RESULTS_FILENAME=<DIR>/<test>.json` before each test binary.
Switch back to `KhronosGroup/OpenCL-CTS` main once KhronosGroup/OpenCL-CTS#2755 is merged.

**CTS_TESTS** — forwarded as positional substring filter arguments to
`run_conformance.py`; plain substring matching only (no regex).

**JSON results** — each `run*` invocation writes per-test JSON files to
`logs/<target>.results.<stamp>/`.  These can be compared against a golden
reference with `make compare-results`.
