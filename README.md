# devicetracker

for tracking device/user presence using an openwrt/lede access point

data is sent from access point in two ways:
1. a hostapd hook script (`assoc_wifi.sh`) is executed every time a wireless device has an association *event*
2. a sync script (`sync_wifi.sh`) syncs the *state* of connected devices, executed via cron (e.g. every 30 minutes)

`launch_assoc_wifi.sh` is used to register the hostapd hook.

data is sent to the event processor (`eventprocessor.py`) api endpoints `/event` and `/state`, respectively. the event processor uses apscheduler to create a job which sets the user's state to `gone` after some threshold (3 minutes). if the user reconnects within that timeframe, the job is deleted.
