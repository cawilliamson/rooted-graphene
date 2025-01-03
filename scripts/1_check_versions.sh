#!/usr/bin/env bash

# exit on error
set -e
# include common functions
# shellcheck disable=SC1091
. "scripts/0_includes.sh"

# include device-specific variables
DEVICE="${1,,}"
GRAPHENE_BRANCH="${2,,}"
BUILD_NUMBER_SUFFIX="${3}"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### FETCH LATEST DEVICE-SPECIFIC GRAPHENE TAG

# determine tag
echo "Fetching latest GrapheneOS release for ${DEVICE} (${GRAPHENE_BRANCH})..."
GRAPHENE_RELEASE=$(curl -s https://grapheneos.org/releases | pup "tr#${DEVICE}-${GRAPHENE_BRANCH} td:nth-of-type(2) text{}")
echo "Latest release: ${GRAPHENE_RELEASE}"

# Check if version has already been built
if [ -f "${DEVICE}_built.txt" ]; then
  PREVIOUS_VERSION=$(cat "${DEVICE}_built.txt")
  echo "Found previous build version: ${PREVIOUS_VERSION}"
  if [ "${PREVIOUS_VERSION}" = "${GRAPHENE_RELEASE}" ]; then
    echo "Version ${GRAPHENE_RELEASE} has already been built. Skipping..."
    exit 1
  fi
  echo "New version detected. Proceeding with build..."
fi

echo "Creating build markers for version ${GRAPHENE_RELEASE}..."
echo "${GRAPHENE_RELEASE}" > "${DEVICE}_build_release.txt"
date +%s > "${DEVICE}_build_datetime.txt"
echo "$(date +%Y%m%d).${BUILD_NUMBER_SUFFIX}" > "${DEVICE}_build_number.txt"
