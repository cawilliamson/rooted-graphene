#!/usr/bin/env bash

# execute setup container script
. scripts/0_setup_container.sh

# include device-specific variables
DEVICE="${1,,}"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### BUILD ROM

# fetch rom sources
mkdir -p rom/
pushd rom/
  # sync rom sources
  repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  repo_sync_until_success

  # copy kernel sources
  # shellcheck disable=SC2010
  KERNEL_DIR=$(ls "device/google/${DEVICE}-kernels/${KERNEL_VERSION}" | grep -v '.git')
  cp -Rfv ../kernel_out/* "device/google/${DEVICE}-kernels/${KERNEL_VERSION}/${KERNEL_DIR}/"
  rm -rf ../kernel_out

  # install adevtool
  yarnpkg install --cwd vendor/adevtool/

  # shellcheck source=/dev/null
  source build/envsetup.sh

  # build aapt2
  lunch sdk_phone64_x86_64-cur-user
  m aapt2

  # fetch vendor binaries
  ./vendor/adevtool/bin/run generate-all -d "${DEVICE}"

  # start build
  # shellcheck source=/dev/null
  source build/envsetup.sh
  lunch "${DEVICE}-cur-user"
  ${ROM_BUILD_COMMAND}

  # generate keys
  mkdir -p "keys/${DEVICE}/"
  pushd "keys/${DEVICE}/"
    # generate and sign
    CN=GrapheneOS
    printf "\n" | ../../development/tools/make_key releasekey "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key platform "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key shared "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key media "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key networkstack "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key sdk_sandbox "/CN=$CN/" || true
    printf "\n" | ../../development/tools/make_key bluetooth "/CN=$CN/" || true
    openssl genrsa 4096 | openssl pkcs8 -topk8 -scrypt -out avb.pem -passout pass:""
    expect ../../../expect/passphrase-prompts.exp ../../external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin
    ssh-keygen -t ed25519 -f id_ed25519 -N ""
  popd # keys/${DEVICE}/

  # encrypt keys
  expect ../expect/passphrase-prompts.exp ./script/encrypt-keys.sh "./keys/${DEVICE}"

  # generate ota package
  m otatools-package

  # finalize
  expect ../expect/passphrase-prompts.exp script/finalize.sh

  # build release
  expect ../expect/passphrase-prompts.exp script/generate-release.sh "${DEVICE}" "${BUILD_NUMBER}"
popd # rom/

# Write output
echo "The file you are likely looking for is:"
ls "rom/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"

# Update version check file
echo "${GRAPHENE_RELEASE}" > "${DEVICE}_latest.txt"
