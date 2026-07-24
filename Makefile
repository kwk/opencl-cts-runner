IMAGE_NAME     ?= opencl-cts
CONTAINER_NAME ?= opencl-cts-run
CONTAINERFILE  ?= Containerfile
LOGS_DIR       := logs

# pipefail is needed so the exit code of the left-hand command survives
# the tee pipe and reaches make.
SHELL := /bin/bash

# Passed into the container at runtime; override on the command line.
# EXIT_ON_FAIL=1 stops after the first failing test suite.
RUN_ENV ?=

.PHONY: all build run run-intel-gpu run-amd-gpu shell clean help

all: build

$(LOGS_DIR):
	mkdir -p $@

## Build the container image (compiles OpenCL-CTS inside).
## This step takes several minutes; the result is cached by podman.
build: | $(LOGS_DIR)
	set -o pipefail; \
	podman build \
		--file $(CONTAINERFILE) \
		--tag $(IMAGE_NAME) \
		. 2>&1 | tee $(LOGS_DIR)/$@.log

## Run OpenCL-CTS tests using the POCL CPU-based OpenCL implementation.
## No GPU hardware required.
run: | $(LOGS_DIR)
	set -o pipefail; \
	podman run --rm \
		--name $(CONTAINER_NAME) \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME) 2>&1 | tee $(LOGS_DIR)/$@.log

## Run with Intel GPU passed through (requires i915/xe driver on the host).
run-intel-gpu: | $(LOGS_DIR)
	set -o pipefail; \
	podman run --rm \
		--name $(CONTAINER_NAME) \
		--device=/dev/dri \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME) 2>&1 | tee $(LOGS_DIR)/$@.log

## Run with AMD GPU passed through (requires amdgpu + ROCm on the host).
run-amd-gpu: | $(LOGS_DIR)
	set -o pipefail; \
	podman run --rm \
		--name $(CONTAINER_NAME) \
		--device=/dev/kfd \
		--device=/dev/dri \
		--security-opt seccomp=unconfined \
		$(addprefix -e ,$(RUN_ENV)) \
		$(IMAGE_NAME) 2>&1 | tee $(LOGS_DIR)/$@.log

## Open an interactive shell inside the built image for manual inspection.
shell:
	podman run --rm -it \
		--name $(CONTAINER_NAME)-shell \
		--entrypoint /bin/bash \
		$(IMAGE_NAME)

## Remove the container (if still running) and the image.
clean:
	podman rm  --force $(CONTAINER_NAME)       2>/dev/null || true
	podman rmi --force $(IMAGE_NAME)            2>/dev/null || true

help:
	@printf 'Targets:\n'
	@printf '  build            Build the OpenCL-CTS image (~5-20 min first time)\n'
	@printf '  run              Run all CTS tests via POCL (CPU, no GPU needed)\n'
	@printf '  run-intel-gpu    Run tests with Intel /dev/dri passed through\n'
	@printf '  run-amd-gpu      Run tests with AMD /dev/kfd + /dev/dri passed through\n'
	@printf '  shell            Drop into a bash shell inside the image\n'
	@printf '  clean            Delete the container and image\n'
	@printf '\nAll build/run output is also written to $(LOGS_DIR)/<target>.log\n'
	@printf '\nVariables:\n'
	@printf '  IMAGE_NAME       Image tag           (default: opencl-cts)\n'
	@printf '  CONTAINER_NAME   Container name      (default: opencl-cts-run)\n'
	@printf '  RUN_ENV          Extra env vars, space-separated KEY=VALUE pairs\n'
	@printf '                   e.g.: make run RUN_ENV="EXIT_ON_FAIL=1"\n'
