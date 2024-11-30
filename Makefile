.PHONY: all build clean push

# Default target
all: build push clean

# Check if device parameter is provided for build or all targets
ifeq ($(filter build all,$(MAKECMDGOALS)),$(MAKECMDGOALS))
ifndef DEVICE
$(error DEVICE is not set. Usage: make DEVICE=<device>)
endif
endif

# Build sources using Docker
build:
	docker run --rm -it \
		-v "$(PWD)":/src \
		-w /src \
			ubuntu:latest \
		/bin/bash -c "bash /src/scripts/1_build_sources.sh $(DEVICE)"

# Push OTA update
push:
	./scripts/2_push_ota.sh

# Clean build directories
clean:
	rm -rfv device_tmp/ kernel/ kernel_out/ rom/