#!/usr/bin/env bash

# execute setup container script
. scripts/0_setup_container.sh

# include device-specific variables
DEVICE="${1,,}"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### BUILD KERNEL

# fetch kernel sources
mkdir -p kernel/
pushd kernel/
  # sync kernel sources
  repo init -u "${KERNEL_REPO}" -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  repo_sync_until_success

  # remove abi_gki_protected_exports files
  rm -f "common/android/abi_gki_protected_exports_*"

  # fetch & apply ksu and \susfs patches
  pushd aosp/
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s

    # fetch susfs
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu.git" -b "${SUSFS_BRANCH}"

    # apply susfs to kernelsu
    pushd KernelSU/
      echo "Applying susfs for KernelSU..."
      patch -p1 < "../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    popd

    # apply susfs to kernel
    echo "Applying susfs for kernel..."
    patch -p1 < "susfs4ksu/kernel_patches/${SUSFS_KERNEL_PATCH}"

    # copy susfs files to kernel (same for all kernels)
    echo "Copying susfs files to kernel..."
    cp -v susfs4ksu/kernel_patches/fs/*.c fs/
    cp -v susfs4ksu/kernel_patches/include/linux/*.h include/linux/

    # enable wireguard by default
    patch -p1 < "../../patches/0001-Disable-defconfig-check.patch"
    patch -p1 < "../../patches/0002-Enable-wireguard-by-default.patch"

    # hardcode kernelsu version (workaround a bug where it defaults to v16 and breaks manager app)
    pushd KernelSU/
      # determine kernelsu version
      KSU_VERSION=$(($(git rev-list --count HEAD) + 10200))

      # hardcode kernelsu version
      sed -i '/^ccflags-y += -DKSU_VERSION=/d' kernel/Makefile
      sed -i '1s/^/ccflags-y += -DKSU_VERSION='"${KSU_VERSION}"'\n/' kernel/Makefile
    popd # KernelSU/
  popd # aosp/

  # build kernel
  ${KERNEL_BUILD_COMMAND}
popd

# stash parts we need
mv -v "kernel/out/${DEVICE}/dist" "./kernel_out"

# remove kernel sources to save space before rom clone
rm -rf kernel/

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
