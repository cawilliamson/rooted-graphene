#!/usr/bin/env bash

set -e

### VARIABLES

AVBROOT_VERSION="3.2.2"
ROM_TARGET="felix"
export AVBROOT_VERSION ROM_TARGET

### CLEANUP PREVIOUS BUILDS
rm -rf kernel/ rom/

### SETUP BUILD SYSTEM

# set apt to noninteractive mode
export DEBIAN_FRONTEND=noninteractive

# install all apt dependencies
apt update
apt dist-upgrade -y
apt install -y \
  build-essential \
  curl \
  expect \
  git \
  git-lfs \
  jq \
  openjdk-21-jdk-headless \
  python3 \
  python3-googleapi \
  python3-protobuf \
  rsync \
  ssh \
  unzip \
  yarnpkg \
  zip

### FETCH LATEST GRAPHENE TAG
GRAPHENE_RELEASE=$(curl -s "https://api.github.com/repos/GrapheneOS/device_google_${ROM_TARGET}/tags" | jq -r '.[0].name')
export GRAPHENE_RELEASE

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

### BUILD KERNEL

# fetch kernel sources
mkdir -p kernel/
pushd kernel/
  # sync kernel sources
  repo init -u https://github.com/GrapheneOS/kernel_manifest-gs.git -b 14 --depth=1 --git-lfs
  repo sync -j4 # limit to 4 to avoid throttling
  while [ $? -ne 0 ]; do !!; done # just incase - retry until success

  # fetch & apply ksu and susfs patches
  pushd aosp/
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

    # apply susfs (to KernelSU)
    pushd KernelSU/
      git am ../../../patches/KernelSU/*.patch
    popd

    # apply susfs (to kernel itself)
    git am ../../patches/kernel-5.10/*.patch
  popd

  # build kernel
  BUILD_AOSP_KERNEL=1 LTO=full ./build_${ROM_TARGET}.sh
popd

# stash parts we need
mv -v "kernel/out/mixed/dist" "./kernel-out"

# remove kernel sources to save space before rom clone
rm -rf kernel/

### BUILD ROM

# fetch rom sources
mkdir -p rom/
pushd rom/
  # sync rom sources
  repo init -u https://github.com/GrapheneOS/platform_manifest.git -b "refs/tags/${GRAPHENE_RELEASE}" --depth=1 --git-lfs
  repo sync -j4 # limit to 4 to avoid throttling
  while [ $? -ne 0 ]; do !!; done # just incase - retry until success

  # copy kernel sources
  cp -Rfv ../kernel-out/* "device/google/${ROM_TARGET}-kernel/"
  rm -rf ../kernel-out

  # fetch vendor binaries
  yarnpkg install --cwd vendor/adevtool/
  # shellcheck source=/dev/null
  . build/envsetup.sh
  TARGET_RELEASE=ap1a m aapt2
  ./vendor/adevtool/bin/run generate-all -d "${ROM_TARGET}"

  # start build
  lunch "${ROM_TARGET}-ap1a-user"
  m vendorbootimage vendorkernelbootimage target-files-package

  # generate keys
  mkdir -p "keys/${ROM_TARGET}/"
  pushd "keys/${ROM_TARGET}/"
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
    expect ../../../expect/extract-public-key.exp
    ssh-keygen -t ed25519 -f id_ed25519 -N ""
  popd

  # encrypt keys
  expect ../expect/encrypt-keys.exp "${ROM_TARGET}"

  # generate ota package
  m otatools-package

  # build release
  expect ../expect/release.exp "${ROM_TARGET}"
popd
