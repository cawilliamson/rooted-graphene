#!/usr/bin/env bash

DEVICE_REPO="https://github.com/GrapheneOS/device_google_comet.git"
KERNEL_BUILD_COMMAND="./build_comet.sh --config=no_download_gki --config=no_download_gki_fips140 --lto=full"
KERNEL_REPO="https://github.com/GrapheneOS/kernel_manifest-zumapro.git"
KERNEL_VERSION="6.1"
ROM_BUILD_COMMAND="m vendorbootimage vendorkernelbootimage target-files-package"
SUSFS_BRANCH="gki-android14-6.1"
SUSFS_KERNEL_PATCH="50_add_susfs_in_gki-android14-6.1.patch"

export DEVICE_REPO \
    KERNEL_BUILD_COMMAND \
    KERNEL_REPO \
    KERNEL_VERSION \
    ROM_BUILD_COMMAND \
    SUSFS_BRANCH \
    SUSFS_KERNEL_PATCH \
    VERSION_CHECK_FILE

