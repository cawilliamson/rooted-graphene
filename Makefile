.PHONY: all build push

# Default target
all: build push

# Check if device parameter is provided
ifndef DEVICE
$(error DEVICE is not set. Usage: make DEVICE=<device>)
endif

# Build sources using Docker
build:
	docker run --rm -it \
		-v "$(PWD)":/src \
		-w /src \
		ubuntu:latest \
		/bin/bash -c "bash /src/scripts/1_build_sources.sh $(DEVICE)"

# Push OTA update
push: build
	./scripts/2_push_ota.sh
