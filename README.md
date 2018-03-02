# openwrt_hass_devicetracker

Package for a completely event-driven device/user presence tracker for [Home Assistant](https://github.com/home-assistant/home-assistant/) on an OpenWRT/LEDE access point. 


## Description

Listens on hostapd wifi association events and then initiates appropriate service calls to the configured Home Assistant instance. On `AP-STA-CONNECTED` or `AP-STA-POLL-OK` the device is marked as seen with a timeout set by the `timeout_conn` config option. If an `AP-STA-DISCONNECTED` event is received, it is marked as seen with a timeout of `timeout_disc`.


## Note on missed events

If Home Assistant or the OpenWRT access point is restarted frequently or unreliable in other ways, you should reduce the very long default timeout for connected devices (since a disconnect event may be missed). However, since association events for connected devices can happen as infrequently as every 2-4 hours, you might want to then add a cronjob which synchronizes the state to the Home Assistant update at least twice as often as your timeout for connected devices `timeout_conn`. A good value for this might be a timeout of 1 hour and a sync every 30 minutes. The cronjob should look like:

```
#!/bin/sh

source "/lib/functions.sh"
config_load hass

source /usr/lib/hass/functions.sh
sync_state
```

This ensures that missed disconnect events do not spuriously keep the device present for more than an hour. This will be implemented by default in a future version.
