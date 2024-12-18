#!/usr/bin/env bash

# include common functions
# shellcheck disable=SC1091
. "scripts/0_includes.sh"

# include device-specific variables
DEVICE="${1,,}"
GRAPHENE_RELEASE="$(cat "${DEVICE}_building.txt")"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

### BUILD KERNEL

# fetch kernel sources
mkdir -p kernel/
pushd kernel/ || exit
  # sync kernel sources
  repo init -u "${KERNEL_REPO}" -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  repo_sync_until_success

  # remove abi_gki_protected_exports files
  rm -f "common/android/abi_gki_protected_exports_*"

  # fetch & apply ksu and \susfs patches
  pushd aosp/ || exit
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -s

    # fetch susfs
    #git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu.git" -b "${SUSFS_BRANCH}"
    git clone --depth=1 "https://gitlab.com/chrisaw/susfs4ksu.git" -b "${SUSFS_BRANCH}"

    # apply susfs to kernelsu
    pushd KernelSU/ || exit
      echo "Applying susfs for KernelSU..."
      patch -p1 < "../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    popd || exit

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
    pushd KernelSU/ || exit
      # determine kernelsu version
      KSU_VERSION=$(($(git rev-list --count HEAD) + 10200))

      # hardcode kernelsu version
      sed -i '/^ccflags-y += -DKSU_VERSION=/d' kernel/Makefile
      sed -i '1s/^/ccflags-y += -DKSU_VERSION='"${KSU_VERSION}"'\n/' kernel/Makefile
    popd || exit # KernelSU/
  popd || exit # aosp/

  # build kernel
  ${KERNEL_BUILD_COMMAND}
popd || exit

# stash parts we need
mv -v "kernel/out/${DEVICE_GROUP}/dist" "./kernel_out"

# remove kernel sources to save space before rom clone
rm -rf kernel/
