#!/usr/bin/env bash

set -e

# set variables
PUP_VERSION="0.4.0"
export PUP_VERSION

# include device-specific variables
DEVICE="${1,,}"
GRAPHENE_BRANCH="${2,,}"

# shellcheck disable=SC1090
. "devices/${DEVICE}.sh"

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

# install pup command
curl -o /var/tmp/pup.zip -L "https://github.com/ericchiang/pup/releases/download/v${PUP_VERSION}/pup_v${PUP_VERSION}_linux_amd64.zip"
unzip /var/tmp/pup.zip -d /usr/bin
chmod +x /usr/bin/pup
rm -f /var/tmp/pup.zip

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

### FETCH LATEST DEVICE-SPECIFIC GRAPHENE TAG

# determine tag
GRAPHENE_RELEASE=$(curl -s https://grapheneos.org/releases | pup "tr#${DEVICE}-${GRAPHENE_BRANCH} td:nth-of-type(2) text{}")

# Check if version has already been built
if [ -f "${DEVICE}_latest.txt" ]; then
  PREVIOUS_VERSION=$(cat "${DEVICE}_latest.txt")
  if [ "${PREVIOUS_VERSION}" = "${GRAPHENE_RELEASE}" ]; then
    echo "Version ${GRAPHENE_RELEASE} has already been built. Skipping..."
    exit 1
  fi
fi

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

    # patch kernelsu versioning
    pushd KernelSU/
      patch -p1 < "../../../patches/0003-Fix-kernelsu-versioning.patch"
    popd

    # fetch susfs
    git clone --depth=1 "https://gitlab.com/simonpunk/susfs4ksu.git" -b "${SUSFS_BRANCH}"

    # apply susfs to KernelSU
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
  popd

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
  popd

  # encrypt keys
  expect ../expect/passphrase-prompts.exp ./script/encrypt-keys.sh "./keys/${DEVICE}"

  # generate ota package
  m otatools-package

  # finalize
  expect ../expect/passphrase-prompts.exp script/finalize.sh

  # build release
  expect ../expect/passphrase-prompts.exp script/generate-release.sh "${DEVICE}" "${BUILD_NUMBER}"
popd

# Write output
echo "The file you are likely looking for is:"
ls "rom/releases/${BUILD_NUMBER}/release-${DEVICE}-${BUILD_NUMBER}/${DEVICE}-ota_update-${BUILD_NUMBER}.zip"

# Update version check file
echo "${GRAPHENE_RELEASE}" > "${DEVICE}_latest.txt"
