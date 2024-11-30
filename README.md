# Dependencies
- avbroot
- custota
- Docker

# avbroot configuration
- avbroot passwords are stored in `~/.avbroot/passwords.sh` as:

```sh
AVB_PASSWORD="PASSWORD_HERE"
OTA_PASSWORD="PASSWORD_HERE"
export AVB_PASSWORD OTA_PASSWORD
```
- avbroot keys and certs are stored in `~/.avbroot/`

# Usage

The DEVICE is the device codename (e.g. `comet`), and OUTPUT is the path to your web directory which you wish to serve the OTA updates from (i.e. configure custota to use this URL.)

```sh
make all DEVICE=<device> OUTPUT=<output_path>
```

You will, of course, need to add a .sh file for your device to the `devices/` directory and add necessary device-specific configuration there.
