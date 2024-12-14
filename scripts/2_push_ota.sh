#!/usr/bin/env bash

AVBROOT_VERSION="1.0.0"
CUSTOTA_VERSION="5.4"
export AVBROOT_VERSION CUSTOTA_VERSION

# install all apt dependencies
apt update
apt dist-upgrade -y
apt install -y \
  curl \
  unzip

# install avbroot
curl -s -O /var/tmp/avbroot.zip "https://github.com/chenxiaolong/Custota/releases/download/v${AVBROOT_VERSION}/avbroot-${AVBROOT_VERSION}-x86_64-unknown-linux-gnu.zip" && \
unzip /var/tmp/avbroot.zip -d /usr/bin
chmod +x /usr/bin/avbroot
rm -f /var/tmp/avbroot.zip

# install custota-tool
curl -s -O /var/tmp/custota-tool.zip "https://github.com/custota/custota/releases/download/${CUSTOTA_VERSION}/custota-${CUSTOTA_VERSION}-x86_64-unknown-linux-gnu.zip"
unzip /var/tmp/custota-tool.zip -d /usr/bin
chmod +x /usr/bin/custota-tool
rm -f /var/tmp/custota-tool.zip

# grab input variables
DEVICE="${1}"
KEYS_DIR="${2}"
WEB_DIR="${3}"

# load in avbroot passwords
# shellcheck disable=SC1091
. "${KEYS_DIR}/passwords.sh"

# find latest ota zip
OTA_ZIP_PATH=$(ls rom/releases/*/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename "${OTA_ZIP_PATH}")

# sign ota zip with avbroot
avbroot ota patch \
  --input "${OTA_ZIP_PATH}" \
  --key-avb "${KEYS_DIR}/avb.key" \
  --pass-avb-env-var AVB_PASSWORD \
  --key-ota "${KEYS_DIR}/ota.key" \
  --pass-ota-env-var OTA_PASSWORD \
  --cert-ota "${KEYS_DIR}/ota.crt" \
  --rootless # we already prepatched in kernelsu

# move ota zip to web dir
cp -v "${OTA_ZIP_PATH}.patched" "${WEB_DIR}/${OTA_ZIP_NAME}"

pushd "${WEB_DIR}" || exit 1
  # generate csig for zip
  custota-tool gen-csig \
    --input "${OTA_ZIP_NAME}" \
    --key "${KEYS_DIR}/ota.key" \
    --passphrase-env-var OTA_PASSWORD \
    --cert "${KEYS_DIR}/ota.crt"

  # create / update the custota json file
  custota-tool gen-update-info \
    --file "${DEVICE}.json" \
    --location "${OTA_ZIP_NAME}"
popd || exit 1
