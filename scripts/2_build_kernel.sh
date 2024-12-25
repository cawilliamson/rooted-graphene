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
  echo "Remove ABI GKI Protected Exports..."
  rm -fv "common/android/abi_gki_protected_exports_*"

  # fetch & apply ksu and susfs patches
  pushd aosp/ || exit
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/rifsxd/KernelSU-Next/next/kernel/setup.sh" | bash -s "${KERNELSU_NEXT_BRANCH}"

    # hardcode kernelsu version (workaround a bug where it defaults to v16 and breaks manager app)
    pushd KernelSU-Next/ || exit
      # determine kernelsu version
      KSU_VERSION=$(($(git rev-list --count HEAD) + 10200))

      # hardcode kernelsu version
      sed -i '/^ccflags-y += -DKSU_VERSION=/d' kernel/Makefile
      sed -i '1s/^/ccflags-y += -DKSU_VERSION='"${KSU_VERSION}"'\n/' kernel/Makefile
    popd || exit # KernelSU-Next/

    # fetch susfs
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu.git" -b "${SUSFS_BRANCH}"
    # TODO: REMOVE!!
    # simon broke susfs :(
    pushd susfs4ksu/ || exit
      git fetch --unshallow
      git reset --hard 810ecfce1a1d5e71442506e80993786296a0b768
    popd || exit # susfs4ksu/

    # apply susfs to kernel
    echo "Applying susfs for kernel..."
    patch -p1 < "susfs4ksu/kernel_patches/${SUSFS_KERNEL_PATCH}"

    # copy susfs files to kernel (same for all kernels)
    echo "Copying susfs files to kernel..."
    cp -v susfs4ksu/kernel_patches/fs/*.c fs/
    cp -v susfs4ksu/kernel_patches/include/linux/*.h include/linux/

    # enable wireguard by default
    echo "Applying wireguard patches..."
    patch -p1 < "../../patches/0001-Disable-defconfig-check.patch"
    patch -p1 < "../../patches/0002-Enable-wireguard-by-default.patch"
  popd || exit # aosp/

  # build kernel
  ${KERNEL_BUILD_COMMAND}
popd || exit

# stash parts we need
mv -v "kernel/out/${DEVICE_GROUP}/dist" "./kernel_out"

# remove kernel sources to save space before rom clone
rm -rf kernel/
