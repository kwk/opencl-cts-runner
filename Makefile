IMAGE_NAME       ?= opencl-cts
CONTAINER_NAME   ?= opencl-cts-run
CONTAINERFILE    ?= Containerfile
LOGS_DIR         := logs
LLVM_SRC_DIR     ?= ~/src/llvm/llvm-project/cts
LLVM_BUILD_DIR   ?= ~/src/llvm/llvm-project/cts/build
LLVM_INSTALL_DIR ?= ~/src/llvm/llvm-project/cts/install

# Evaluated once per make invocation; all targets in one run share the stamp.
LOG_STAMP := $(shell date +%Y-%m-%dT%H-%M-%S)

# pipefail is needed so the exit code of the left-hand command survives
# the tee pipe and reaches make.
SHELL := /bin/bash

# CSV test list passed to run_conformance.py.  Available presets (all under
# /opencl-cts/test_conformance/ inside the image):
#   opencl_conformance_tests_quick.csv           (default)
#   opencl_conformance_tests_full.csv
#   opencl_conformance_tests_math.csv
#   opencl_conformance_tests_conversions.csv
#   opencl_conformance_tests_full_spirv.csv
CTS_LIST ?= opencl_conformance_tests_quick.csv

# OpenCL device type passed to run_conformance.py.  Controls which
# device-type-specific CSV rows are included and sets CL_DEVICE_TYPE in
# the environment for each test.  Overridden per run-* target.
CL_DEVICE_TYPE ?= CL_DEVICE_TYPE_DEFAULT

# Space-separated substring filters forwarded to run_conformance.py.
# A test is included if its name contains any of the given strings.
# Examples:
#   make run CTS_TESTS="Printf API"
#   make run CTS_TESTS="SVM"
CTS_TESTS ?=

# Extra environment variables forwarded into the container at runtime.
RUN_ENV ?=

# Paths used by the compare-results target.
GOLDEN      ?=
RESULTS_DIR ?=

# Tee output to a timestamped file and update the <target>.log symlink to it.
# The symlink is updated even when the command fails so the latest log is
# always reachable under the stable name regardless of exit code.
define log_and_link
	set -o pipefail; \
	$(1) 2>&1 | tee $(LOGS_DIR)/$@.$(LOG_STAMP).log; \
	EC=$$?; \
	ln -sf $@.$(LOG_STAMP).log $(LOGS_DIR)/$@.log; \
	exit $$EC
endef

# ── Build ──────────────────────────────────────────────────────────────────────

.PHONY: all
all: help

$(LOGS_DIR):
	mkdir -p $@

.PHONY: build
## Build the container image (compiles OpenCL-CTS inside).
## This step takes several minutes; the result is cached by podman.
build: | $(LOGS_DIR)
	$(call log_and_link,podman build \
		--file $(CONTAINERFILE) \
		--tag $(IMAGE_NAME) \
		.)

# ── Inspection ─────────────────────────────────────────────────────────────────

.PHONY: list-lists
## List the CSV test-list presets available inside the image.
list-lists:
	@podman run --rm --entrypoint /bin/bash $(IMAGE_NAME) \
		-c "ls /opencl-cts/test_conformance/opencl_conformance_tests_*.csv \
		    | xargs -n1 basename"

.PHONY: list-tests-in-list
## List the tests defined in the currently selected CTS_LIST (default: quick).
## Columns: command (with any subtest args)  |  test name  |  [device type if restricted]
## Override with: make list-tests-in-list CTS_LIST=opencl_conformance_tests_full.csv
list-tests-in-list:
	@podman run --rm --entrypoint python3 $(IMAGE_NAME) -c \
		"f=open('/opencl-cts/test_conformance/$(CTS_LIST)'); \
		rows=[[x.strip() for x in l.split(',',2)] for l in f \
		      if l.strip() and not l.strip().startswith('#')]; \
		w=max(len(r[-1]) for r in rows); \
		[print(f'{r[-1]:{w}}  {r[-2]}' + (f'  [{r[0]}]' if len(r)==3 else '')) \
		 for r in rows]"

.PHONY: shell
## Open an interactive shell inside the built image for manual inspection.
shell:
	podman run --rm -it \
		--name $(CONTAINER_NAME)-shell \
		--entrypoint /bin/bash \
		$(IMAGE_NAME)

# ── Run tests ──────────────────────────────────────────────────────────────────

.PHONY: smoke-test
## Quick sanity check: run test_printf via Mesa Rusticl + llvmpipe (no GPU needed).
smoke-test:
	$(MAKE) run-rusticl-cpu CTS_TESTS="Printf"

.PHONY: run
## Run CTS tests via POCL (CPU, no GPU needed).
## OCL_ICD_VENDORS restricts the ICD loader to pocl.icd only so that rusticl
## (which has no device without /dev/dri) does not appear as platform 0.
run: CL_DEVICE_TYPE = CL_DEVICE_TYPE_CPU
run: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		-v $(CURDIR)/$(LOGS_DIR):/logs:z \
		-e OCL_ICD_VENDORS=/etc/OpenCL/vendors-pocl \
		-e CTS_LIST="$(CTS_LIST)" \
		-e CL_DEVICE_TYPE="$(CL_DEVICE_TYPE)" \
		-e CTS_TESTS="$(CTS_TESTS)" \
		-e LOG_DIR=/logs \
		-e RUN_TARGET=$@ \
		-e LOG_STAMP=$(LOG_STAMP) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: configure-llvm
configure-llvm: |	$(LOGS_DIR)
	$(call log_and_link,(mkdir -pv $(LLVM_BUILD_DIR) \
		&& cd $(LLVM_BUILD_DIR) \
		&& cmake -C $(LLVM_SRC_DIR)/libclc/cmake/caches/spirv.cmake \
				-G Ninja \
				-B . \
				-DCMAKE_INSTALL_PREFIX=$(LLVM_INSTALL_DIR) \
				-DRUNTIMES_spirv32-unknown-unknown_LIBCLC_USE_SPIRV_BACKEND:BOOL=ON \
        -DRUNTIMES_spirv64-unknown-unknown_LIBCLC_USE_SPIRV_BACKEND:BOOL=ON \
				$(LLVM_SRC_DIR)/llvm)

.PHONY: build-llvm
build-llvm: configure-llvm
build-llvm: |	$(LOGS_DIR)
	$(call log_and_link,(cd $(LLVM_BUILD_DIR) && ninja))

.PHONY: run-rusticl-cpu
## Run via Mesa Rusticl on the llvmpipe software device — no GPU required.
## Exercises libclc (a runtime dep of mesa-libOpenCL); POCL does not use libclc.
## llvmpipe exposes as CL_DEVICE_TYPE_CPU.
run-rusticl-cpu: CL_DEVICE_TYPE = CL_DEVICE_TYPE_CPU
run-rusticl-cpu: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		-v $(CURDIR)/$(LOGS_DIR):/logs:z \
		-e RUSTICL_ENABLE=llvmpipe \
		-e CTS_LIST="$(CTS_LIST)" \
		-e CL_DEVICE_TYPE="$(CL_DEVICE_TYPE)" \
		-e CTS_TESTS="$(CTS_TESTS)" \
		-e LOG_DIR=/logs \
		-e RUN_TARGET=$@ \
		-e LOG_STAMP=$(LOG_STAMP) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-intel-rusticl
## Run with Intel Iris/Xe GPU via Mesa Rusticl (requires i915/xe driver on host).
## RUSTICL_ENABLE=iris tells Mesa to expose the Iris/Xe GPU as an OpenCL device.
run-intel-rusticl: CL_DEVICE_TYPE = CL_DEVICE_TYPE_GPU
run-intel-rusticl: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/dri \
		-v $(CURDIR)/$(LOGS_DIR):/logs:z \
		-e RUSTICL_ENABLE=iris \
		-e CTS_LIST="$(CTS_LIST)" \
		-e CL_DEVICE_TYPE="$(CL_DEVICE_TYPE)" \
		-e CTS_TESTS="$(CTS_TESTS)" \
		-e LOG_DIR=/logs \
		-e RUN_TARGET=$@ \
		-e LOG_STAMP=$(LOG_STAMP) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-intel-gpu
## Run with Intel GPU passed through (requires i915/xe driver on the host).
run-intel-gpu: CL_DEVICE_TYPE = CL_DEVICE_TYPE_GPU
run-intel-gpu: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/dri \
		-v $(CURDIR)/$(LOGS_DIR):/logs:z \
		-e CTS_LIST="$(CTS_LIST)" \
		-e CL_DEVICE_TYPE="$(CL_DEVICE_TYPE)" \
		-e CTS_TESTS="$(CTS_TESTS)" \
		-e LOG_DIR=/logs \
		-e RUN_TARGET=$@ \
		-e LOG_STAMP=$(LOG_STAMP) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-amd-gpu
## Run with AMD GPU passed through (requires amdgpu + ROCm on the host).
run-amd-gpu: CL_DEVICE_TYPE = CL_DEVICE_TYPE_GPU
run-amd-gpu: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/kfd \
		--device=/dev/dri \
		--security-opt seccomp=unconfined \
		-v $(CURDIR)/$(LOGS_DIR):/logs:z \
		-e CTS_LIST="$(CTS_LIST)" \
		-e CL_DEVICE_TYPE="$(CL_DEVICE_TYPE)" \
		-e CTS_TESTS="$(CTS_TESTS)" \
		-e LOG_DIR=/logs \
		-e RUN_TARGET=$@ \
		-e LOG_STAMP=$(LOG_STAMP) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

# ── Compare ────────────────────────────────────────────────────────────────────

.PHONY: compare-results
## Compare a JSON results directory against a golden reference.
## Usage: make compare-results GOLDEN=<path> RESULTS_DIR=<path>
##   GOLDEN      path to the golden JSON file on the host
##   RESULTS_DIR path to a <target>.results.<stamp>/ directory on the host
compare-results:
	@test -n "$(GOLDEN)"      || { echo "ERROR: GOLDEN is not set";      exit 1; }
	@test -n "$(RESULTS_DIR)" || { echo "ERROR: RESULTS_DIR is not set"; exit 1; }
	podman run --rm \
		-v $(abspath $(GOLDEN)):/golden.json:z,ro \
		-v $(abspath $(RESULTS_DIR)):/results:z,ro \
		--entrypoint python3 \
		$(IMAGE_NAME) \
		/opencl-cts/ci/compare_results.py \
			--golden /golden.json \
			--results-dir /results

# ── Utilities ──────────────────────────────────────────────────────────────────

.PHONY: clean
## Remove the container (if still running) and the image.
clean:
	podman rm  --force $(CONTAINER_NAME)       2>/dev/null || true
	podman rmi --force $(IMAGE_NAME)            2>/dev/null || true

.PHONY: help
help:
	@printf 'Build:\n'
	@printf '  build              Build the OpenCL-CTS image (~5-20 min first time)\n'
	@printf '\nInspection:\n'
	@printf '  list-lists         List CSV test-list presets available in the image\n'
	@printf '  list-tests-in-list List tests in the selected CTS_LIST\n'
	@printf '  shell              Drop into a bash shell inside the image\n'
	@printf '\nRun tests:\n'
	@printf '  smoke-test         Run test_printf via Rusticl+llvmpipe (quick libclc check)\n'
	@printf '  run                Run CTS via POCL (CPU); RUSTICL_ENABLE: not set\n'
	@printf '  run-rusticl-cpu    Run via Mesa Rusticl + llvmpipe (CPU); uses libclc\n'
	@printf '                     RUSTICL_ENABLE=llvmpipe; CL_DEVICE_TYPE=CL_DEVICE_TYPE_CPU\n'
	@printf '  run-intel-rusticl  Run on Intel Iris/Xe GPU via Mesa Rusticl; uses libclc\n'
	@printf '                     RUSTICL_ENABLE=iris; CL_DEVICE_TYPE=CL_DEVICE_TYPE_GPU\n'
	@printf '  run-intel-gpu      Run with Intel /dev/dri; CL_DEVICE_TYPE=CL_DEVICE_TYPE_GPU\n'
	@printf '  run-amd-gpu        Run with AMD /dev/kfd+dri; CL_DEVICE_TYPE=CL_DEVICE_TYPE_GPU\n'
	@printf '\nCompare:\n'
	@printf '  compare-results    Compare a results dir against a golden JSON reference\n'
	@printf '\nUtilities:\n'
	@printf '  clean              Delete the container and image\n'
	@printf '\nLogs: each run creates $(LOGS_DIR)/<target>.<timestamp>.log;\n'
	@printf '      $(LOGS_DIR)/<target>.log is a symlink to the most recent one.\n'
	@printf '\nVariables:\n'
	@printf '  IMAGE_NAME     Image tag                    (default: opencl-cts)\n'
	@printf '  CTS_LIST       CSV test preset filename     (default: opencl_conformance_tests_quick.csv)\n'
	@printf '  CL_DEVICE_TYPE OpenCL device type           (set per target; override to change)\n'
	@printf '  CTS_TESTS      Substring filters for test names (default: empty = run all)\n'
	@printf '                 e.g.: make run CTS_TESTS="Printf SVM"\n'
	@printf '  GOLDEN         Path to the golden JSON file for compare-results\n'
	@printf '  RESULTS_DIR    Path to a <target>.results.<stamp>/ dir for compare-results\n'
	@printf '  RUN_ENV        Space-separated KEY=VALUE pairs forwarded into the container\n'
	@printf '                 e.g.: make run RUN_ENV="OCL_ICD_ENABLE_TRACE=1"\n'
	@printf '                       (trace every ICD dispatch — debugging only, very verbose)\n'
