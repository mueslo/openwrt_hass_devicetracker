err_msg() {
    logger -t $0 -p error $@
    echo $1 1>&2
}

register_hook() {
    logger -t $0 -p debug "register_hook $@"
    if [ "$#" -ne 1 ]; then
        err_msg "register_hook missing interface"
        exit 1
    fi
    interface=$1
    
    hostapd_cli -i$interface -a/usr/lib/hass-tracker/push_event.sh &
}

post() {
    logger -t $0 -p debug "post $@"
    if [ "$#" -ne 1 ]; then
        err_msg "POST missing payload"
        exit 1
    fi
    payload=$1
    
    config_get hass_host global host
    config_get hass_token global token
    
    resp=$(curl "$hass_host/api/services/device_tracker/see" -sfSX POST \
        -H 'Content-Type: application/json' \
        -H "Authorization: Bearer $hass_token" \
        --data-binary "$payload" 2>&1)
    
    if [ $? -eq 0 ]; then
        level=debug
    else
        level=error
    fi
    
    logger -t $0 -p $level "post response $resp"
}

build_payload() {
    logger -t $0 -p debug "build_payload $@"
    if [ "$#" -ne 4 ]; then
        err_msg "Invalid payload parameters"
        logger -t $0 -p warning "push_event not handled"
        exit 1
    fi
    mac=$1
    host=$2
    consider_home=$3
    source_name=$4
    
    echo "{\"mac\":\"$mac\",\"host_name\":\"$host\",\"consider_home\":\"$consider_home\",\"source_type\":\"router\",\"attributes\":{\"source_name\":\"$source_name\"}}"
}

get_ip() {
    # get ip for mac
    grep "0x2\s\+$1" /proc/net/arp | cut -f 1 -s -d" "
}

get_host_name() {
    # get hostname for mac
    nslookup "$(get_ip $1)" | grep -o "name = .*$" | cut -d ' ' -f 3
}

push_event() {
    logger -t $0 -p debug "push_event $@"
    if [ "$#" -eq 3 ]; then
        iface=$1
        msg=$2
        mac=$3
    elif [ "$#" -eq 4 ]; then
        # wlan1 STA-OPMODE-SMPS-MODE-CHANGED 84:c7:de:ed:be:ef off
        if [ "$2" -ne "STA-OPMODE-SMPS-MODE-CHANGED" ]; then
          err_msg "Unknown type of push_event"
          exit 1
        fi

        iface=$1
        msg=$2
        mac=$3
        status=$4
    else
        err_msg "Illegal number of push_event parameters"
        exit 1
    fi
    
    config_get hass_timeout_conn global timeout_conn
    config_get hass_timeout_disc global timeout_disc
    config_get hass_source_name global source_name `uci get system.@system[0].hostname`
    config_get hass_whitelist_devices global whitelist
    
    case $msg in 
        "AP-STA-CONNECTED")
            timeout=$hass_timeout_conn
            ;;
        "AP-STA-POLL-OK")
            timeout=$hass_timeout_conn
            ;;
        "AP-STA-DISCONNECTED")
            timeout=$hass_timeout_disc
            ;;
        "STA-OPMODE-SMPS-MODE-CHANGED")
            timeout=$hass_timeout_conn
            ;;
        *)
            logger -t $0 -p warning "push_event not handled"
            return
            ;;
    esac

    hostname="$(get_host_name $mac)"
    if [ -n "$hass_whitelist_devices" ] && ! array_contains "$hostname" $hass_whitelist_devices; then
        logger -t $0 -p warning "push_event ignored, $hostname not in whitelist."
    elif [ -z "$hostname" ]; then
        logger -t $0 -p warning "sync_state ignored, hostname for $mac is empty."
    else
        post $(build_payload "$mac" "$hostname" "$timeout" "$hass_source_name")
    fi
}

array_contains() {
    for i in `seq 2 $(($#+1))`; do
        next=$(eval "echo \$$i")
        if [ "${next}" == "${1}" ]; then
            echo "y"
            return 0
        fi
    done
    echo "n"
    return 1
}

sync_state() {
    logger -t $0 -p debug "sync_state $@"

    config_get hass_timeout_conn global timeout_conn
    config_get hass_source_name global source_name `uci get system.@system[0].hostname`
    config_get hass_whitelist_devices global whitelist

    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
        for mac in $maclist; do
            hostname="$(get_host_name $mac)"
            if [ -n "$hass_whitelist_devices" ] && ! array_contains "$hostname" $hass_whitelist_devices; then
                logger -t $0 -p warning "sync_state ignored, $hostname not in whitelist."
            elif [ -z "$hostname" ]; then
                logger -t $0 -p warning "sync_state ignored, hostname for $mac is empty."
            else
                post $(build_payload "$mac" "$hostname" "$hass_timeout_conn" "$hass_source_name") &
            fi
        done
    done
}
