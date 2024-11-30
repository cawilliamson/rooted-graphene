#!/usr/bin/env bash

DEVICE_REPO="https://github.com/GrapheneOS/device_google_comet.git"
KERNEL_BUILD_COMMAND="./build_comet.sh --config=use_source_tree_aosp --config=no_download_gki --lto=full"
KERNEL_REPO="https://github.com/GrapheneOS/kernel_manifest-zumapro.git"
KERNEL_VERSION="6.1"
SUSFS_BRANCH="gki-android14-6.1"
SUSFS_KERNEL_PATCH="50_add_susfs_in_gki-android14-6.1.patch"