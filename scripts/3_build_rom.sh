#!/usr/bin/env bash

# exit on error
set -e

# include common functions
# shellcheck disable=SC1091
. "scripts/0_includes.sh"

# include device-specific variables
DEVICE="${1,,}"
GRAPHENE_RELEASE="$(cat "${DEVICE}_building.txt")"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### BUILD ROM

echo "=== Starting ROM Build Process ==="
echo "Device: ${DEVICE}"
echo "GrapheneOS Release: ${GRAPHENE_RELEASE}"

# fetch rom sources
echo "Creating and entering ROM directory..."
mkdir -p rom/
pushd rom/ || exit
  echo "Initializing ROM repository..."
  # sync rom sources
  repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  echo "Syncing ROM repository..."
  repo_sync_until_success

  # copy kernel sources
  echo "Copying kernel build artifacts..."
  # shellcheck disable=SC2010
  KERNEL_DIR=$(ls "device/google/${DEVICE_GROUP}-kernels/${KERNEL_VERSION}" | grep -v '.git')
  rm -rf "device/google/${DEVICE_GROUP}-kernels/${KERNEL_VERSION}/${KERNEL_DIR}/*"
  cp -Rfv ../kernel_out/* "device/google/${DEVICE_GROUP}-kernels/${KERNEL_VERSION}/${KERNEL_DIR}/"
  rm -rf ../kernel_out

  echo "Installing adevtool..."
  yarnpkg install --cwd vendor/adevtool/

  echo "Setting up build environment..."
  # shellcheck source=/dev/null
  source build/envsetup.sh

  echo "Building AAPT2..."
  lunch sdk_phone64_x86_64-cur-user
  m aapt2

  echo "Fetching vendor binaries for ${DEVICE}..."
  ./vendor/adevtool/bin/run generate-all -d "${DEVICE}"

  echo "=== Starting Main ROM Build ==="
  # shellcheck source=/dev/null
  source build/envsetup.sh
  lunch "${DEVICE}-cur-user"
  ${ROM_BUILD_COMMAND}

  echo "=== Generating Keys ==="
  mkdir -p "keys/${DEVICE}/"
  pushd "keys/${DEVICE}/" || exit
    echo "Generating signing keys..."
    CN=GrapheneOS
    printf "\n" | ../../development/tools/make_key releasekey "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key platform "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key shared "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key media "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key networkstack "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key sdk_sandbox "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key bluetooth "/CN=$CN/" || true
    echo "Generating AVB key..."
    openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem -passout pass:""
    expect ../../../expect/passphrase-prompts.exp ../../external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin
    echo "Generating SSH key..."
    ssh-keygen -t ed25519 -f id_ed25519 -N ""
  popd || exit

  echo "Encrypting keys..."
  expect ../expect/passphrase-prompts.exp ./script/encrypt-keys.sh "./keys/${DEVICE}"

  echo "Generating OTA package..."
  m otatools-package

  echo "Finalizing build..."
  expect ../expect/passphrase-prompts.exp script/finalize.sh

  echo "Generating release package..."
  expect ../expect/passphrase-prompts.exp script/generate-release.sh "${DEVICE}" "${BUILD_NUMBER}"
popd || exit

echo "=== Build Complete ==="
echo "Output file location:"
ls "rom/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"

echo "Updating version records..."
# Update version check file
echo "${GRAPHENE_RELEASE}" > "${DEVICE}_built.txt"

# Remove building file
rm -f "${DEVICE}_building.txt"

echo "=== Build Process Finished ==="
