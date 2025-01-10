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

# fetch latest GrapheneOS release tag
echo "Fetching latest GrapheneOS release for ${DEVICE} (${GRAPHENE_BRANCH})..."
GRAPHENE_RELEASE=$(curl -s https://grapheneos.org/releases | pup "tr#${DEVICE}-${GRAPHENE_BRANCH} td:nth-of-type(2) text{}")
echo "Latest release: ${GRAPHENE_RELEASE}"

# fetch latest KernelSU release version
echo "Fetching latest KernelSU commit..."
CURRENT_KSU_COMMIT=$(git ls-remote https://github.com/tiann/KernelSU.git refs/heads/main | cut -f1)
echo "Latest KernelSU commit: ${CURRENT_KSU_COMMIT}"

# fetch latest SUSFS commit
echo "Fetching latest SUSFS commit..."
CURRENT_SUSFS_COMMIT=$(git ls-remote https://gitlab.com/simonpunk/susfs4ksu.git refs/heads/"${SUSFS_BRANCH}" | cut -f1)
echo "Latest SUSFS commit: ${CURRENT_SUSFS_COMMIT}"

# check if version has already been built
if [ -f "data/${DEVICE}_built.txt" ]; then
  PREVIOUS_GRAPHENE_VERSION=$(sed -n '1p' "data/${DEVICE}_built.txt")
  PREVIOUS_KSU_COMMIT=$(sed -n '2p' "data/${DEVICE}_built.txt")
  PREVIOUS_SUSFS_COMMIT=$(sed -n '3p' "data/${DEVICE}_built.txt")

  if [ "${PREVIOUS_GRAPHENE_VERSION}" = "${GRAPHENE_RELEASE}" ] && \
     [ "${PREVIOUS_KSU_COMMIT}" = "${CURRENT_KSU_COMMIT}" ] && \
     [ "${PREVIOUS_SUSFS_COMMIT}" = "${CURRENT_SUSFS_COMMIT}" ]; then
    echo "GrapheneOS ${GRAPHENE_RELEASE}, KernelSU commit ${CURRENT_KSU_COMMIT}, and SUSFS commit ${CURRENT_SUSFS_COMMIT} have already been built. Skipping..."
    exit 1
  fi

  # Output what triggered the build
  echo "Build triggered by:"
  [ "${PREVIOUS_GRAPHENE_VERSION}" != "${GRAPHENE_RELEASE}" ] && echo "- GrapheneOS update: ${PREVIOUS_GRAPHENE_VERSION} -> ${GRAPHENE_RELEASE}"
  [ "${PREVIOUS_KSU_COMMIT}" != "${CURRENT_KSU_COMMIT}" ] && echo "- KernelSU update: ${PREVIOUS_KSU_COMMIT} -> ${CURRENT_KSU_COMMIT}"
  [ "${PREVIOUS_SUSFS_COMMIT}" != "${CURRENT_SUSFS_COMMIT}" ] && echo "- SUSFS update: ${PREVIOUS_SUSFS_COMMIT} -> ${CURRENT_SUSFS_COMMIT}"
  echo "Proceeding with build..."
else
  echo "No previous build record found. Proceeding with build..."
fi

echo "Creating build markers..."
mkdir -p data/
echo "${GRAPHENE_RELEASE}" > "data/${DEVICE}_build_graphene.txt"
echo "${CURRENT_KSU_COMMIT}" > "data/${DEVICE}_build_ksu.txt"
echo "${CURRENT_SUSFS_COMMIT}" > "data/${DEVICE}_build_susfs.txt"
date +%s > "data/${DEVICE}_build_datetime.txt"
echo "$(date +%Y%m%d).${BUILD_NUMBER_SUFFIX}" > "data/${DEVICE}_build_number.txt"
