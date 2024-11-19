#!/usr/bin/env bash

set -e

### RESYNC THIS REPO
# This is because the creator of this is forgetful and
# NEVER remembers to sync again before running a build! :/
git pull

# set static variables
AVBROOT_VERSION="3.9.0"
export AVBROOT_VERSION

### CLEANUP PREVIOUS BUILDS
rm -rf device_tmp/ kernel/ kernel_out/ rom/

### FUNCTIONS

# Function to run repo sync until successful
function repo_sync_until_success() {
  # disable exit on error - we expect this to fail a few times
  set +e

  # perform sync
  # (using -j4 makes the sync less likely to hit rate limiting)
  until repo sync -c -j4 --fail-fast --no-clone-bundle --no-tags; do
    echo "repo sync failed, retrying in 1 minute..."
    sleep 60
  done

  # re-enable exit on error - we're done failing now! :)
  set -e
}

### SETUP BUILD SYSTEM

# set apt to noninteractive mode
export DEBIAN_FRONTEND=noninteractive

# install all apt dependencies
apt update
apt dist-upgrade -y
apt install -y \
  bison \
  build-essential \
  curl \
  expect \
  flex \
  git \
  git-lfs \
  jq \
  libncurses-dev \
  libssl-dev \
  openjdk-21-jdk-headless \
  python3 \
  python3-googleapi \
  python3-protobuf \
  rsync \
  ssh \
  unzip \
  yarnpkg \
  zip

# install repo command
curl -s https://storage.googleapis.com/git-repo-downloads/repo > /usr/bin/repo
chmod +x /usr/bin/repo

# install libncurses5
pushd /var/tmp
  curl -O http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb
  dpkg -i libtinfo5_6.4-2_amd64.deb
  curl -LO http://launchpadlibrarian.net/648013227/libncurses5_6.4-2_amd64.deb
  dpkg -i libncurses5_6.4-2_amd64.deb
  rm -f ./*.deb
popd

# configure git
git config --global color.ui false
git config --global user.email "androidbuild@localhost"
git config --global user.name "Android Build"

# install avbroot
pushd /var/tmp
  curl -LSs "https://github.com/chenxiaolong/avbroot/releases/download/v${AVBROOT_VERSION}/avbroot-${AVBROOT_VERSION}-x86_64-unknown-linux-gnu.zip" > avbroot.zip
  unzip -o -p avbroot.zip avbroot > /usr/bin/avbroot
  chmod +x /usr/bin/avbroot
  rm -f avbroot.zip
popd

### FETCH LATEST DEVICE-SPECIFIC GRAPHENE TAG

# fetch latest device sources temporarily
git clone "https://github.com/GrapheneOS/device_google_comet.git" device_tmp/

# determine tag
pushd device_tmp
  GRAPHENE_RELEASE=$(git describe --tags --abbrev=0)

  # remove any extension (like "-redfin" for example)
  GRAPHENE_RELEASE="${GRAPHENE_RELEASE%%-*}"
  export GRAPHENE_RELEASE

  # write out status
  echo "Building GrapheneOS release: ${GRAPHENE_RELEASE}"
popd

# cleanup device sources
rm -rf device_tmp/

### BUILD KERNEL

# fetch kernel sources
mkdir -p kernel/
pushd kernel/
  # sync kernel sources
  repo init -u https://github.com/GrapheneOS/kernel_manifest-zumapro.git -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  
  repo_sync_until_success

  # fetch & apply ksu and \susfs patches
  pushd aosp/
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

    # fetch susfs
    git clone "https://gitlab.com/cawilliamson/susfs4ksu.git" -b gki-android14-6.1

    # apply susfs to KernelSU
    pushd KernelSU/
      echo "Applying SUSFS for KernelSU..."
      patch -p1 < "../susfs4ksu/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch"
    popd

    # apply susfs to kernel
    echo "Applying SUSFS for kernel..."
    patch -p1 < "susfs4ksu/kernel_patches/50_add_susfs_in_kernel-6.1.patch"

    # copy susfs files to kernel (same for all kernels)
    echo "Copying susfs files to kernel..."
    # KernelSU files
    cp -v susfs4ksu/kernel_patches/KernelSU/kernel/sucompat.h KernelSU/kernel/
    # FS files
    cp -v susfs4ksu/kernel_patches/fs/susfs.c fs/
    cp -v susfs4ksu/kernel_patches/fs/sus_su.c fs/
    # Include files
    cp -v susfs4ksu/kernel_patches/include/linux/susfs.h include/linux/
    cp -v susfs4ksu/kernel_patches/include/linux/sus_su.h include/linux/

    # enable wireguard by default
    patch -p1 < "../../patches/0001-Disable-defconfig-check.patch"
    patch -p1 < "../../patches/0002-Enable-wireguard-by-default.patch"
  popd

  # build kernel
  ./build_comet.sh --config=use_source_tree_aosp --config=no_download_gki --lto=full
popd

# stash parts we need
mv -v "kernel/out/zumapro/dist" "./kernel_out"

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
  cp -Rfv ../kernel_out/* "device/google/comet-kernel/"
  rm -rf ../kernel_out

  # fetch vendor binaries
  yarnpkg install --cwd vendor/adevtool/

  # shellcheck source=/dev/null
  . build/envsetup.sh

  # determine target release
  TARGET_RELEASE=$(find build/release/aconfig/* -type d ! -name 'root' -print -quit | xargs basename)
  export TARGET_RELEASE

  # build aapt2
  m aapt2

  # fetch vendor binaries
  ./vendor/adevtool/bin/run generate-all -d "comet"

  # start build
  lunch "comet-${TARGET_RELEASE}-user"
  # pixel 6:
  #m vendorbootimage target-files-package
  m vendorbootimage vendorkernelbootimage target-files-package

  # generate keys
  mkdir -p "keys/comet/"
  pushd "keys/comet/"
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
  popd

  # encrypt keys
  expect ../expect/passphrase-prompts.exp ./script/encrypt-keys.sh ./keys/comet

  # generate ota package
  m otatools-package

  # finalize
  expect ../expect/passphrase-prompts.exp script/finalize.sh

  # build release
  expect ../expect/passphrase-prompts.exp script/generate-release.sh comet ${BUILD_NUMBER}
popd

# Write output
echo "The file you are likely looking for is:"
ls rom/releases/${BUILD_NUMBER}/release-comet-${BUILD_NUMBER}/comet-ota_update-${BUILD_NUMBER}.zip
