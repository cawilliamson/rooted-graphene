.PHONY: all build clean push-ota

# optional inputs for CPU and memory limits (defaults to 100% of available resources)
MAX_CPU_PERCENT ?= 100
MAX_MEM_PERCENT ?= 100

CPU_LIMIT := $(shell echo $$(( $(shell nproc --all) * $(MAX_CPU_PERCENT) / 100 )))
MEM_LIMIT := $(shell echo "$$(( $(shell free -m | awk '/^Mem:/{print $$2}') * $(MAX_MEM_PERCENT) / 100 ))m")

# Default target must be first
all:
	$(call check_device)
	$(call check_output)
	$(MAKE) clean
	$(MAKE) pull-repo
	$(MAKE) build
	$(MAKE) push-ota
	$(MAKE) clean

# Check required variables
check_device = $(if $(DEVICE),,$(error DEVICE is required))
check_output = $(if $(OUTPUT),,$(error OUTPUT is required))

# Build sources using Docker
build:
	$(call check_device)
	docker run --rm \
		--cpus="$(CPU_LIMIT)" \
		--memory="$(MEM_LIMIT)" \
		-v "$(PWD)":/src \
		-w /src \
		ubuntu:latest \
		/bin/bash /src/scripts/1_build_sources.sh $(DEVICE)

# Pull repo updates
pull-repo:
	git reset --hard
	git pull

# Push OTA update
push-ota:
	$(call check_device)
	$(call check_output)
	./scripts/2_push_ota.sh $(DEVICE) $(OUTPUT)

# Clean build directories
clean:
	rm -rfv device_tmp/ kernel/ kernel_out/ rom/
