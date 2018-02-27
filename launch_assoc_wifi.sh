#!/bin/sh

for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`
do
    hostapd_cli -i$interface -a/etc/config/assoc_wifi.sh -B
done
 
