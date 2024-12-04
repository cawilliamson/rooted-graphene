.PHONY: all build clean push

# Default target must be first
all:
	$(call check_device)
	$(call check_output)
	$(MAKE) build
	$(MAKE) push
	$(MAKE) clean

# Check required variables
check_device = $(if $(DEVICE),,$(error DEVICE is required))
check_output = $(if $(OUTPUT),,$(error OUTPUT is required))

# Build sources using Docker
build:
	$(call check_device)
	CPU_LIMIT=$(shell echo $$(($(shell nproc) / 2)))
	MEM_LIMIT=$(shell echo "$$(($(shell free -m | awk '/^Mem:/{print $$2}') / 2))m")
	docker run --rm \
		--cpus="$$CPU_LIMIT" \
		--memory="$$MEM_LIMIT" \
		-v "$(PWD)":/src \
		-w /src \
		ubuntu:latest \
		/bin/bash /src/scripts/1_build_sources.sh $(DEVICE)

# Push OTA update
push:
	$(call check_device)
	$(call check_output)
	./scripts/2_push_ota.sh $(DEVICE) $(OUTPUT)

# Clean build directories
clean:
	rm -rfv device_tmp/ kernel/ kernel_out/ rom/
