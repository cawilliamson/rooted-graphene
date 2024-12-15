#!/usr/bin/env bash

# include common functions
# shellcheck disable=SC1091
. "scripts/0_includes.sh"

# grab input variables
DEVICE="${1}"

# load in avbroot passwords
# shellcheck disable=SC1091
. "/keys/passwords.sh"

# find latest ota zip
OTA_ZIP_PATH=$(ls rom/releases/*/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename "${OTA_ZIP_PATH}")

# sign ota zip with avbroot
avbroot ota patch \
  --input "${OTA_ZIP_PATH}" \
  --key-avb "/keys/avb.key" \
  --pass-avb-env-var AVB_PASSWORD \
  --key-ota "/keys/ota.key" \
  --pass-ota-env-var OTA_PASSWORD \
  --cert-ota "/keys/ota.crt" \
  --rootless # we already prepatched in kernelsu

# move ota zip to web dir
cp -v "${OTA_ZIP_PATH}.patched" "/web/${OTA_ZIP_NAME}"

pushd "/web" || exit
  # generate csig for zip
  custota-tool gen-csig \
    --input "${OTA_ZIP_NAME}" \
    --key "/keys/ota.key" \
    --passphrase-env-var OTA_PASSWORD \
    --cert "/keys/ota.crt"

  # create / update the custota json file
  custota-tool gen-update-info \
    --file "${DEVICE}.json" \
    --location "${OTA_ZIP_NAME}"
popd || exit