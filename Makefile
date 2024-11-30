.PHONY: all build clean push

# Default target
all: build push clean

# Build sources using Docker
build:
ifndef DEVICE
	$(error DEVICE is not set. Usage: make build DEVICE=<device>)
endif
	docker run --rm -it \
		-v "$(PWD)":/src \
		-w /src \
			ubuntu:latest \
		/bin/bash -c "bash /src/scripts/1_build_sources.sh $(DEVICE)"

# Push OTA update
push:
ifndef OUTPUT
	$(error OUTPUT is not set. Usage: make push OUTPUT=<output_path>)
endif
	./scripts/2_push_ota.sh $(OUTPUT)

# Clean build directories
clean:
	rm -rfv device_tmp/ kernel/ kernel_out/ rom/