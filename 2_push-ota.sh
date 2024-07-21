#!/usr/bin/env bash

# set static variables
CUSTOTA_VERSION="4.5"
export CUSTOTA_VERSION

# load in avbroot passwords
. $HOME/.avbroot/passwords.sh

# install all $installer dependencies
$installer update
$installer dist-upgrade -y
$installer install -y nginx

# install custota
pushd /var/tmp
  curl -LSs "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_VERSION}/custota-tool-${CUSTOTA_VERSION}-x86_64-unknown-linux-gnu.zip" > custota-tool.zip
  unzip -o -p custota-tool.zip custota-tool > /usr/bin/custota-tool
  chmod +x /usr/bin/custota-tool
  rm -f custota-tool.zip
popd

# find latest ota zip
OTA_ZIP_PATH=$(ls rom/out/release-*/*ota_update*.zip)
OTA_ZIP_NAME=$(basename $OTA_ZIP_PATH)

# determine device name
DEVICE_CODENAME=$(ls rom/out | grep "release-" | cut -d '-' -f2)

# sign ota zip with avbroot
avbroot ota patch \
  --input $OTA_ZIP_PATH \
  --key-avb $HOME/.avbroot/avb.key \
  --pass-avb-env-var AVB_PASSWORD \
  --key-ota $HOME/.avbroot/ota.key \
  --pass-ota-env-var OTA_PASSWORD \
  --cert-ota $HOME/.avbroot/ota.crt \
  --rootless # we already prepatched in kernelsu

# move ota zip to web dir
cp -v $OTA_ZIP_PATH.patched /var/www/html/$OTA_ZIP_NAME

pushd /var/www/html
  # generate csig for zip
  custota-tool gen-csig \
    --input $OTA_ZIP_NAME \
    --key $HOME/.avbroot/ota.key \
    --passphrase-env-var OTA_PASSWORD \
    --cert $HOME/.avbroot/ota.crt

  # create / update the custota json file
  custota-tool gen-update-info \
    --file $DEVICE_CODENAME.json \
    --location $OTA_ZIP_NAME
popd
