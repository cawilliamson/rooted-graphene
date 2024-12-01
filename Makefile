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
	docker run --rm -it \
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