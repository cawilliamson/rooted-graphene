#!/usr/bin/env bash

# load in avbroot passwords
# shellcheck disable=SC1091
. "${HOME}/.avbroot/passwords.sh"

CUSTOTA_WEB_DIR="/var/www/html/custota.chrisaw.io"

# find latest ota zip
OTA_ZIP_PATH=$(ls rom/out/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename "${OTA_ZIP_PATH}")

# determine device name
# shellcheck disable=SC2010
DEVICE_CODENAME=$(ls rom/out | grep "release-" | cut -d '-' -f2)

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
cp -v "${OTA_ZIP_PATH}.patched" "${CUSTOTA_WEB_DIR}/${OTA_ZIP_NAME}"

pushd "${CUSTOTA_WEB_DIR}" || exit 1
  # generate csig for zip
  custota-tool gen-csig \
    --input "${OTA_ZIP_NAME}" \
    --key "${HOME}/.avbroot/ota.key" \
    --passphrase-env-var OTA_PASSWORD \
    --cert "${HOME}/.avbroot/ota.crt"

  # create / update the custota json file
  custota-tool gen-update-info \
    --file "${DEVICE_CODENAME}.json" \
    --location "${OTA_ZIP_NAME}"
popd || exit 1
