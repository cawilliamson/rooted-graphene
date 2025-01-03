.PHONY: all build clean push-ota

# optional inputs for CPU and memory limits (defaults to 100% of available resources)
BUILD_NUMBER_SUFFIX ?= 0
GRAPHENE_BRANCH ?= stable
KEYS_DIR ?= $(HOME)/.avbroot
MAX_CPU_PERCENT ?= 100
MAX_MEM_PERCENT ?= 100

CPU_LIMIT := $(shell echo $$(( $(shell nproc --all) * $(MAX_CPU_PERCENT) / 100 )))
MEM_LIMIT := $(shell echo "$$(( $(shell free -m | awk '/^Mem:/{print $$2}') * $(MAX_MEM_PERCENT) / 100 ))m")

# Default target must be first
all:
	$(call check_device)
	$(call check_web_dir)
	$(MAKE) clean
	$(MAKE) build-docker-image
	$(MAKE) check-versions
	$(MAKE) pull-repo
	$(MAKE) build-kernel
	$(MAKE) build-rom
	$(MAKE) push-ota

# Check required variables
check_device = $(if $(DEVICE),,$(error DEVICE is required))
check_web_dir = $(if $(WEB_DIR),,$(error WEB_DIR is required))

# Build docker image
build-docker-image:
	docker build --no-cache -t buildrom .

# Build kernel using Docker
build-kernel:
	$(call check_device)
	docker run --rm \
		--cpus="$(CPU_LIMIT)" \
		--memory="$(MEM_LIMIT)" \
		-v "$(PWD)":/src \
		-w /src \
		buildrom \
		/bin/bash /src/scripts/2_build_kernel.sh $(DEVICE)

# Build rom using Docker
build-rom:
	$(call check_device)
	docker run --rm \
		--cpus="$(CPU_LIMIT)" \
		--memory="$(MEM_LIMIT)" \
		-v "$(PWD)":/src \
		-w /src \
		buildrom \
		/bin/bash /src/scripts/3_build_rom.sh $(DEVICE)

# Check versions
check-versions:
	docker run --rm \
		-v "$(PWD)":/src \
		-w /src \
		buildrom \
		/bin/bash /src/scripts/1_check_versions.sh $(DEVICE) $(GRAPHENE_BRANCH) $(BUILD_NUMBER_SUFFIX)

# Pull repo updates
pull-repo:
	git reset --hard
	git pull

# Push OTA update
push-ota:
	$(call check_device)
	$(call check_web_dir)
	docker run --rm \
		--cpus="$(CPU_LIMIT)" \
		--memory="$(MEM_LIMIT)" \
		-v "$(PWD)":/src \
		-v "$(KEYS_DIR)":/keys \
		-v "$(WEB_DIR)":/web \
		-w /src \
		buildrom \
		/bin/bash /src/scripts/4_push_ota.sh $(DEVICE)

# Clean build directories
clean:
	rm -rfv "*_build_*.txt" device_tmp/ kernel/ kernel_out/ rom/
