#!/bin/sh
 
payload=""
delim=""
for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`
do
  # for each interface, get mac addresses of connected stations/clients
  maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
  # for each mac address in that list...
  for mac in $maclist
  do
    ip="UNKN"
    host=""
    ip=`cat /tmp/dhcp.leases | cut -f 2,3,4 -s -d" " | grep $mac | cut -f 2 -s -d" "`
    host=`cat /tmp/dhcp.leases | cut -f 2,3,4 -s -d" " | grep $mac | cut -f 3 -s -d" "`

    payload="$payload$delim{\"mac\": \"$mac\",\"ip\": \"$ip\", \"host\": \"$host\"}"
    delim=","
  done
done

curl 192.168.1.3:8088/state -X POST --header 'Content-Type: application/json' --data-binary "[$payload]"
