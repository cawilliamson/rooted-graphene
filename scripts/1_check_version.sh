#!/usr/bin/env bash

# execute setup container script
. scripts/0_setup_container.sh

# include device-specific variables
DEVICE="${1,,}"
GRAPHENE_BRANCH="${2,,}"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### FETCH LATEST DEVICE-SPECIFIC GRAPHENE TAG

# determine tag
GRAPHENE_RELEASE=$(curl -s https://grapheneos.org/releases | pup "tr#${DEVICE}-${GRAPHENE_BRANCH} td:nth-of-type(2) text{}")

# Check if version has already been built
if [ -f "${DEVICE}_latest.txt" ]; then
  PREVIOUS_VERSION=$(cat "${DEVICE}_latest.txt")
  if [ "${PREVIOUS_VERSION}" = "${GRAPHENE_RELEASE}" ]; then
    echo "Version ${GRAPHENE_RELEASE} has already been built. Skipping..."
    exit 1
  fi
fi
