#!/usr/bin/env bash

# create and run Ubuntu container with current directory mounted
docker run --rm -it \
    -v "$(pwd)":/src \
    -w /src \
    ubuntu:latest \
    /bin/bash -c "bash /src/scripts/1_build_comet.sh"
