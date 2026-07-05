# openwrt_hass_devicetracker

Package for a completely event-driven device/user presence tracker for [Home Assistant](https://www.home-assistant.io/components/openwrt/) on an OpenWrt access point.

## Description

Listens on hostapd wifi association events and then initiates appropriate service calls to the configured Home Assistant instance. On `AP-STA-CONNECTED` or `AP-STA-POLL-OK` the device is marked as seen with a timeout set by the `timeout_conn` config option. If an `AP-STA-DISCONNECTED` event is received, it is marked as seen with a timeout of `timeout_disc`.

Since restarting your access points removes any scripts connected via `hostapd_cli -a`, this package includes a daemon which monitors ubus for added APs so restarting/reconfiguring your radios doesn't kill the service.

## Building

The package is built using the official [`openwrt/sdk`](https://hub.docker.com/r/openwrt/sdk) Docker image and produces `.apk` packages for the apk-based OpenWrt package manager (25.12+). Since hass-tracker is `PKGARCH=all` (pure shell scripts), the same `.apk` works on any OpenWrt target.

### Using build script (Linux — requires Docker)

```bash
./build/build.sh
```

Uses the `openwrt/sdk:x86_64-main` image to build. The resulting `.apk` lands in `build/bin/`.

| Variable       | Default                  | Description                           |
|----------------|--------------------------|---------------------------------------|
| SDK_IMAGE_TAG  | x86_64-main              | openwrt/sdk image tag                 |
| OUTPUT_DIR     | build/bin                | Output directory for the .apk         |
| PACKAGE_DIR    | packages/net/hass-tracker | Package source directory             |

### Using Docker Compose

```bash
docker compose run pkgbuild       # x86_64 build
docker compose run pkgbuild-arm   # aarch64 build
```

The resulting `.apk` will be in `build/bin/`.

### Using GitHub Actions

Push a tag matching `v*` to automatically build and create a release with the `.apk` artifact. The CI runs against both `x86_64-main` and `aarch64_cortex-a72-main` as a sanity check. See `.github/workflows/build.yml`.

## Installation

On an OpenWrt system with apk as package manager (25.12+):

```bash
apk add hass-tracker_*.apk
```

### Configuration

Once the package is installed, you can modify `/etc/config/hass-tracker` to your liking and start/enable the service via `service hass-tracker start` and `service hass-tracker enable`. If you would like to use HTTPS, simply start your host string with the `https://` protocol specifier.

Authentication is done via a [long-lived access token](https://developers.home-assistant.io/docs/en/auth_api.html#long-lived-access-token) that can be generated from the web UI. This token needs to be set in the configuration file in the field `token`.

## Note on missed events

If Home Assistant or the OpenWrt access point is restarted frequently or unreliable in other ways, you should reduce the very long default timeout for connected devices, since a disconnect event may be missed. However, since association events for connected devices can happen as infrequently as every 2-4 hours, you might want to then add a cronjob which synchronizes the state to Home Assistant at least twice as often as your timeout for connected devices `timeout_conn`. A good value for this might be a timeout of 1 hour and a sync every 30 minutes. The cronjob should look like:

```
#!/bin/sh

source /lib/functions.sh
config_load hass-tracker

source /usr/lib/hass-tracker/functions.sh
sync_state
```

This ensures that missed disconnect events do not spuriously keep the device present for more than an hour.
