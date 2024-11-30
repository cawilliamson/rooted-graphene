#!/usr/bin/env bash

# Exit on error
set -e

# Check if device argument is provided
if [ $# -ne 1 ]; then
    echo "Usage: $0 <device>"
    exit 1
fi

# create and run Ubuntu container with current directory mounted
docker run --rm -it \
    -v "$(pwd)":/src \
    -w /src \
    ubuntu:latest \
    /bin/bash -c "bash /src/scripts/1_build_sources.sh ${1}"

# push update to web dir
# shellcheck disable=SC2181
if [ "${?}" -eq 0 ]; then
    ./scripts/2_push_ota.sh
fi
