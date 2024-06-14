#!/usr/bin/env bash

set -e

### VARIABLES

# set static variables
AVBROOT_VERSION="3.2.2"
ROM_TARGET="felix"
TARGET_RELEASE="ap2a"

# determine rom target code
if [ "${ROM_TARGET}" == "husky" ]; then
  ROM_TARGET_GROUP="shusky"
else
  ROM_TARGET_GROUP="${ROM_TARGET}"
fi
export AVBROOT_VERSION ROM_TARGET ROM_TARGET_GROUP TARGET_RELEASE

### CLEANUP PREVIOUS BUILDS
rm -rfv kernel/ kernel-out/ rom/

### FUNCTIONS

# Function to run repo sync until successful
function repo_sync_until_success() {
  # disable exit on error - we expect this to fail a few times
  set +e

  # perform sync
  until repo sync -c -j$(nproc --all) --no-clone-bundle --no-tags; do
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
  build-essential \
  curl \
  expect \
  git \
  git-lfs \
  jq \
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

### FETCH LATEST GRAPHENE TAG
GRAPHENE_RELEASE=$(curl -s "https://api.github.com/repos/GrapheneOS/device_google_${ROM_TARGET_GROUP}/tags" | jq -r '.[0].name')
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
  if [ "${ROM_TARGET}" == "husky" ]; then
    # REMOVE
    echo "Temporarily disabled whilst I fix susfs for 5.15"
    exit 1
    # REMOVE

    repo init -u https://github.com/GrapheneOS/kernel_manifest-shusky.git -b 14 --depth=1 --git-lfs
  else
    repo init -u https://github.com/GrapheneOS/kernel_manifest-gs.git -b 14 --depth=1 --git-lfs
  fi
  repo_sync_until_success

  # fetch & apply ksu and susfs patches
  pushd aosp/
    # apply kernelsu
    curl -LSs "https://raw.githubusercontent.com/tiann/KernelSU/main/kernel/setup.sh" | bash -

    # apply susfs (to KernelSU)
    pushd KernelSU/
      git am ../../../patches/susfs/KernelSU/10_enable_susfs_for_ksu.patch
    popd

    # determine target kernel version
    if [ "${ROM_TARGET}" == "husky" ]; then
      TARGET_KERNEL_VERSION="5.15"
    else
      TARGET_KERNEL_VERSION="5.10"
    fi

    # apply susfs to kernel
    git am "../../patches/susfs/${TARGET_KERNEL_VERSION}/50_add_susfs_in_kernel.patch"

    # copy susfs files to kernel
    cp -v "../../patches/${TARGET_KERNEL_VERSION}/fs/susfs.c" fs/
    cp -v "../../patches/${TARGET_KERNEL_VERSION}/include/linux/susfs.h" include/linux/

    # enable wireguard by default
    git am "../../patches/wireguard/0001-Enable-wireguard-by-default.patch"
  popd

  # build kernel
  BUILD_AOSP_KERNEL=1 LTO=full ./build_${ROM_TARGET_GROUP}.sh
popd

# stash parts we need
if [ "${ROM_TARGET}" == "husky" ]; then
  mv -v "kernel/out/shusky/dist" "./kernel-out"
else
  mv -v "kernel/out/mixed/dist" "./kernel-out"
fi

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
  cp -Rfv ../kernel-out/* "device/google/${ROM_TARGET_GROUP}-kernel/"
  rm -rf ../kernel-out

  # fetch vendor binaries
  yarnpkg install --cwd vendor/adevtool/
  # shellcheck source=/dev/null
  . build/envsetup.sh
  m aapt2
  ./vendor/adevtool/bin/run generate-all -d "${ROM_TARGET}"

  # start build
  lunch "${ROM_TARGET}-${TARGET_RELEASE}-user"
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
    expect ../../../expect/passphrase-prompts.exp ../../external/avb/avbtool.py extract_public_key --key avb.pem --output avb_pkmd.bin
    ssh-keygen -t ed25519 -f id_ed25519 -N ""
  popd

  # encrypt keys
  expect ../expect/passphrase-prompts.exp ./script/encrypt_keys.sh ./keys/${ROM_TARGET}

  # generate ota package
  m otatools-package

  # build release
  expect ../expect/passphrase-prompts.exp script/release.sh ${ROM_TARGET}

  # Write output
  echo "The file you are likely looking for is:"
  ls out/release-*/*ota_update*.zip
popd
