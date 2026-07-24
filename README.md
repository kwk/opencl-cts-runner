# OpenCL-CTS podman builder

Builds the [Khronos OpenCL Conformance Test Suite](https://github.com/KhronosGroup/OpenCL-CTS)
inside a `fedora:44` container and runs it against one of several OpenCL backends.
No GPU hardware is required for the default workflow.

## Prerequisites

- `podman`
- `make`

## Quick start

```sh
make build        # pull fedora:44, install deps, compile the CTS (~5-20 min; cached after)
make smoke-test   # run test_printf via Mesa Rusticl + llvmpipe — exercises libclc, no GPU needed

# smoke-test writes JSON results to logs/run-rusticl-cpu.results.<timestamp>/
# Compare against the golden reference (substitute the actual timestamp):
make compare-results \
  GOLDEN=logs/example-comparison/golden/Printf.json \
  RESULTS_DIR=logs/run-rusticl-cpu.results.<timestamp>
```

## Make targets

Run `make help` for the full listing. Targets are grouped by type:

### Build
| Target | Description |
|---|---|
| `build` | Build the container image |

### Inspection
| Target | Description |
|---|---|
| `list-lists` | List the CSV test-list presets available in the image |
| `list-tests-in-list` | List tests in the active `CTS_LIST` (command, name, device restriction) |
| `shell` | Open an interactive bash shell inside the image |

### Run tests
| Target | Backend | libclc | GPU required |
|---|---|---|---|
| `smoke-test` | Mesa Rusticl + llvmpipe (Printf only) | yes | no |
| `run` | POCL (CPU) | no | no |
| `run-rusticl-cpu` | Mesa Rusticl + llvmpipe (CPU) | yes | no |
| `run-intel-rusticl` | Mesa Rusticl, Intel Iris/Xe | yes | yes (`/dev/dri`) |
| `run-intel-gpu` | POCL fallback with `/dev/dri` forwarded | no | yes (`/dev/dri`) |
| `run-amd-gpu` | POCL fallback with AMD devices forwarded | no | yes (`/dev/kfd` + `/dev/dri`) |

### Compare
| Target | Description |
|---|---|
| `compare-results` | Compare a JSON results directory against a golden reference |

## Variables

| Variable | Default | Description |
|---|---|---|
| `CTS_LIST` | `opencl_conformance_tests_quick.csv` | CSV test preset (see `make list-lists`) |
| `CL_DEVICE_TYPE` | set per target | OpenCL device type passed to `run_conformance.py` |
| `CTS_TESTS` | _(empty = all)_ | Space-separated substring filters on test names |
| `GOLDEN` | — | Path to golden JSON file for `compare-results` |
| `RESULTS_DIR` | — | Path to results directory for `compare-results` |
| `RUN_ENV` | _(empty)_ | Extra `KEY=VALUE` pairs forwarded into the container |
| `IMAGE_NAME` | `opencl-cts` | podman image tag |

### Examples

```sh
# Run only the Printf and SVM tests
make run-rusticl-cpu CTS_TESTS="Printf SVM"

# Run the full test list instead of the quick one
make run-rusticl-cpu CTS_LIST=opencl_conformance_tests_full.csv

# Enable ICD loader tracing (very verbose — for debugging dispatch issues)
make run RUN_ENV="OCL_ICD_ENABLE_TRACE=1"
```

## Logs

Every `build` and `run*` invocation writes output to `logs/<target>.<timestamp>.log`
and updates `logs/<target>.log` as a symlink to the most recent file.

Each `run*` invocation also writes per-test JSON result files to
`logs/<target>.results.<timestamp>/`, one file per test binary.

## Comparing results against a golden reference

After a run, use `compare-results` to detect regressions against a known-good baseline:

```sh
# Run and capture results
make run-rusticl-cpu CTS_TESTS="Printf"

# Compare against a golden file
make compare-results \
  GOLDEN=logs/example-comparison/golden/Printf.json \
  RESULTS_DIR=logs/run-rusticl-cpu.results.<timestamp>
```

The comparison uses `ci/compare_results.py` from the CTS and exits non-zero
if any regressions (previously passing tests now failing) are found.
