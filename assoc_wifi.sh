#!/bin/sh
logger -t $0 "hostapd event $@"
iface=$1
msg=$2
mac=$3
host=`cat /tmp/dhcp.leases | cut -f 2,3,4 -s -d" " | grep $mac | cut -f 3 -s -d" "`
payload="{\"mac\":\"$mac\",\"msg\":\"$msg\",\"host\":\"$host\"}"
curl 192.168.1.3:8088/event -X POST --header 'Content-Type: application/json' --data-binary "$payload"
