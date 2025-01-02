#!/usr/bin/env bash

# grab input variables
DEVICE="${1,,}"

echo "=== Starting OTA Push Process ==="
echo "Device: ${DEVICE}"

# exit on error
set -e

# include common functions
# shellcheck disable=SC1091
. "scripts/0_includes.sh"

# load in avbroot passwords
echo "Loading signing keys..."
# shellcheck disable=SC1091
. "/keys/passwords.sh"

# find latest ota zip
echo "Locating latest OTA package..."
OTA_ZIP_PATH=$(ls rom/releases/*/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename "${OTA_ZIP_PATH}")
echo "Found OTA package: ${OTA_ZIP_NAME}"

echo "=== Signing OTA Package ==="
# sign ota zip with avbroot
avbroot ota patch \
  --input "${OTA_ZIP_PATH}" \
  --key-avb "/keys/avb.key" \
  --pass-avb-env-var AVB_PASSWORD \
  --key-ota "/keys/ota.key" \
  --pass-ota-env-var OTA_PASSWORD \
  --cert-ota "/keys/ota.crt" \
  --rootless # we already prepatched in kernelsu

echo "=== Publishing OTA Package ==="
# remove old ota zip (if exists)
echo "Removing old OTA zip (if exists)..."
rm -fv "/web/${OTA_ZIP_NAME}"
# move ota zip to web dir
echo "Copying signed OTA to web directory..."
cp -v "${OTA_ZIP_PATH}.patched" "/web/${OTA_ZIP_NAME}"

pushd "/web" || exit
  echo "Generating CSIG signature..."
  # generate csig for zip
  custota-tool gen-csig \
    --input "${OTA_ZIP_NAME}" \
    --key "/keys/ota.key" \
    --passphrase-env-var OTA_PASSWORD \
    --cert "/keys/ota.crt"

  echo "Updating CustOTA JSON file..."
  # create / update the custota json file
  custota-tool gen-update-info \
    --file "${DEVICE}.json" \
    --location "${OTA_ZIP_NAME}"
popd || exit

echo "=== OTA Push Complete ==="