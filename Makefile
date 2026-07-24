IMAGE_NAME     ?= opencl-cts
CONTAINER_NAME ?= opencl-cts-run
CONTAINERFILE  ?= Containerfile
LOGS_DIR       := logs

# Evaluated once per make invocation; all targets in one run share the stamp.
LOG_STAMP := $(shell date +%Y-%m-%dT%H-%M-%S)

# pipefail is needed so the exit code of the left-hand command survives
# the tee pipe and reaches make.
SHELL := /bin/bash

# Space-separated list of ERE patterns matched against the full test path.
# Each word is tested with bash =~ so plain substrings and full regexes both
# work.  A test is included if any pattern matches.  Empty = run all tests.
# Examples:
#   make run CTS_TESTS="test_api test_basic"      # two specific tests
#   make run CTS_TESTS="extensions"               # all extension tests
#   make run CTS_TESTS="test_(api|basic)"         # regex alternation
CTS_TESTS ?=

# Extra environment variables forwarded into the container at runtime.
# EXIT_ON_FAIL=1 stops after the first failing test suite.
RUN_ENV ?=

# podman options forwarded to the clinfo prerequisite so it sees exactly the
# same devices and environment as the actual test run.  Each run-* target
# overrides this with its own --device and -e flags.
CLINFO_OPTS ?=

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

.PHONY: all
all: build

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

.PHONY: clinfo
## Show OpenCL platforms visible inside the container and log the output.
## Runs automatically before each run* target with CLINFO_OPTS matching the
## test run, so the log reflects exactly what the tests will see.
clinfo: | $(LOGS_DIR)
	$(call log_and_link,podman run --rm \
		$(CLINFO_OPTS) \
		--entrypoint clinfo \
		$(IMAGE_NAME))

.PHONY: list-tests
## List all test executables built into the image (full paths, one per line).
list-tests:
	@podman run --rm --entrypoint /bin/bash $(IMAGE_NAME) \
		-c "cd /opencl-cts/build && find test_conformance \
		    -name 'test_*' -type f -executable | sort"

.PHONY: run
## Run OpenCL-CTS tests using the POCL CPU-based OpenCL implementation.
## No GPU hardware required.
## OCL_ICD_VENDORS restricts the ICD loader to pocl.icd only so that the
## mesa-libOpenCL rusticl platform (which has no device without /dev/dri)
## does not become platform 0 and cause CL_DEVICE_NOT_FOUND failures.
run: CLINFO_OPTS = -e OCL_ICD_VENDORS=/etc/OpenCL/vendors-pocl
run: clinfo | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		-e OCL_ICD_VENDORS=/etc/OpenCL/vendors-pocl \
		-e CTS_TESTS="$(CTS_TESTS)" \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: smoke-test
## Quick sanity check: run test_printf via Mesa Rusticl + llvmpipe (no GPU needed).
smoke-test:
	$(MAKE) run-rusticl-cpu CTS_TESTS="test_conformance/printf/test_printf"

.PHONY: run-rusticl-cpu
## Run via Mesa Rusticl on the llvmpipe software device — no GPU required.
## This is the simplest way to exercise libclc (a runtime dep of mesa-libOpenCL)
## without physical GPU hardware.  POCL does NOT depend on libclc; this target does.
run-rusticl-cpu: CLINFO_OPTS = -e RUSTICL_ENABLE=llvmpipe
run-rusticl-cpu: clinfo | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		-e RUSTICL_ENABLE=llvmpipe \
		-e CTS_TESTS="$(CTS_TESTS)" \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-intel-rusticl
## Run with Intel Iris/Xe GPU via Mesa Rusticl (requires i915/xe driver on host).
## RUSTICL_ENABLE=iris tells Mesa to expose the Iris/Xe GPU as an OpenCL device;
## without it Rusticl registers no platforms even with /dev/dri forwarded.
run-intel-rusticl: CLINFO_OPTS = --device=/dev/dri -e RUSTICL_ENABLE=iris
run-intel-rusticl: clinfo | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/dri \
		-e RUSTICL_ENABLE=iris \
		-e CTS_TESTS="$(CTS_TESTS)" \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-intel-gpu
## Run with Intel GPU passed through (requires i915/xe driver on the host).
run-intel-gpu: CLINFO_OPTS = --device=/dev/dri
run-intel-gpu: clinfo | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/dri \
		-e CTS_TESTS="$(CTS_TESTS)" \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: run-amd-gpu
## Run with AMD GPU passed through (requires amdgpu + ROCm on the host).
run-amd-gpu: CLINFO_OPTS = --device=/dev/kfd --device=/dev/dri
run-amd-gpu: clinfo | $(LOGS_DIR)
	$(call log_and_link,podman run --rm --replace \
		--name $(CONTAINER_NAME) \
		--device=/dev/kfd \
		--device=/dev/dri \
		--security-opt seccomp=unconfined \
		-e CTS_TESTS="$(CTS_TESTS)" \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME))

.PHONY: shell
## Open an interactive shell inside the built image for manual inspection.
shell:
	podman run --rm -it \
		--name $(CONTAINER_NAME)-shell \
		--entrypoint /bin/bash \
		$(IMAGE_NAME)

.PHONY: clean
## Remove the container (if still running) and the image.
clean:
	podman rm  --force $(CONTAINER_NAME)       2>/dev/null || true
	podman rmi --force $(IMAGE_NAME)            2>/dev/null || true

.PHONY: help
help:
	@printf 'Targets:\n'
	@printf '  build              Build the OpenCL-CTS image (~5-20 min first time)\n'
	@printf '  smoke-test         Run test_printf via Rusticl+llvmpipe (quick libclc check)\n'
	@printf '  list-tests         List all test executables built into the image\n'
	@printf '  clinfo             Show OpenCL platforms visible inside the container\n'
	@printf '  run                Run CTS tests via POCL (CPU, no GPU needed)\n'
	@printf '                     RUSTICL_ENABLE: not set; does NOT use libclc\n'
	@printf '  run-rusticl-cpu    Run via Mesa Rusticl + llvmpipe (CPU, no GPU needed)\n'
	@printf '                     RUSTICL_ENABLE=llvmpipe; uses libclc\n'
	@printf '  run-intel-rusticl  Run tests on Intel Iris/Xe GPU via Mesa Rusticl\n'
	@printf '                     RUSTICL_ENABLE=iris; uses libclc\n'
	@printf '  run-intel-gpu      Run tests with Intel /dev/dri passed through\n'
	@printf '                     RUSTICL_ENABLE: not set; falls back to POCL\n'
	@printf '  run-amd-gpu        Run tests with AMD /dev/kfd + /dev/dri passed through\n'
	@printf '                     RUSTICL_ENABLE: not set; falls back to POCL\n'
	@printf '  shell              Drop into a bash shell inside the image\n'
	@printf '  clean              Delete the container and image\n'
	@printf '\nLogs: each run creates $(LOGS_DIR)/<target>.<timestamp>.log;\n'
	@printf '      $(LOGS_DIR)/<target>.log is a symlink to the most recent one.\n'
	@printf '\nVariables:\n'
	@printf '  IMAGE_NAME   Image tag           (default: opencl-cts)\n'
	@printf '  CTS_TESTS    Space-separated test names/path fragments to run\n'
	@printf '               (default: empty = run all tests)\n'
	@printf '               e.g.: make run CTS_TESTS="test_api test_basic"\n'
	@printf '  RUN_ENV      Extra env vars passed into the container\n'
	@printf '               e.g.: make run RUN_ENV="EXIT_ON_FAIL=1"\n'
