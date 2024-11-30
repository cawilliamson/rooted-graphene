#!/usr/bin/env bash

# grab input variables
DEVICE="${1}"
OUTPUT="${2}"

# load in avbroot passwords
# shellcheck disable=SC1091
. "${HOME}/.avbroot/passwords.sh"

# find latest ota zip
OTA_ZIP_PATH=$(ls rom/releases/*/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename "${OTA_ZIP_PATH}")

# sign ota zip with avbroot
avbroot ota patch \
  --input "${OTA_ZIP_PATH}" \
  --key-avb "${HOME}/.avbroot/avb.key" \
  --pass-avb-env-var AVB_PASSWORD \
  --key-ota "${HOME}/.avbroot/ota.key" \
  --pass-ota-env-var OTA_PASSWORD \
  --cert-ota "${HOME}/.avbroot/ota.crt" \
  --rootless # we already prepatched in kernelsu

# move ota zip to web dir
cp -v "${OTA_ZIP_PATH}.patched" "${OUTPUT}/${OTA_ZIP_NAME}"

pushd "${OUTPUT}" || exit 1
  # generate csig for zip
  custota-tool gen-csig \
    --input "${OTA_ZIP_NAME}" \
    --key "${HOME}/.avbroot/ota.key" \
    --passphrase-env-var OTA_PASSWORD \
    --cert "${HOME}/.avbroot/ota.crt"

  # create / update the custota json file
  custota-tool gen-update-info \
    --file "${DEVICE}.json" \
    --location "${OTA_ZIP_NAME}"
popd || exit 1
