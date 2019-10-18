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
    config_get hass_token global token "0"
    config_get hass_pw global pw
    
    if [ "$hass_token" != "0" ]; then
        auth_head="Authorization: Bearer $hass_token"
    else
        auth_head="X-HA-Access: $hass_pw"
    fi
    
    resp=$(curl "$hass_host/api/services/device_tracker/see" -sfSX POST \
        -H 'Content-Type: application/json' \
        -H "$auth_head" \
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
    if [ "$#" -ne 3 ]; then
        err_msg "Invalid payload parameters"
        logger -t $0 -p warning "push_event not handled"
        exit 1
    fi
    mac=$1
    host=$2
    consider_home=$3
    
    echo "{\"mac\":\"$mac\",\"host_name\":\"$host\",\"consider_home\":\"$consider_home\",\"source_type\":\"router\"}"
}

get_ip() {
    # get ip for mac
    grep "0x2\s\+$1" /proc/net/arp | cut -f 1 -s -d" "
}

get_host_name() {
    # get hostname for mac
    nslookup "$(get_ip $1)" | grep -o "name = .*$" | cut -d ' ' -f 3
}

is_connected() {
    # check if MAC address is still connected to any wireless interface
    mac=$1

    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        if iw dev $interface station dump | grep Station | grep -q $mac; then
            return 0
        fi
    done

    return 1
}

push_event() {
    logger -t $0 -p debug "push_event $@"
    if [ "$#" -ne 3 ]; then
        err_msg "Illegal number of push_event parameters"
        exit 1
    fi
    iface=$1
    msg=$2
    mac=$3
    
    config_get hass_timeout_conn global timeout_conn
    config_get hass_timeout_disc global timeout_disc
    
    case $msg in 
        "AP-STA-CONNECTED")
            timeout=$hass_timeout_conn
            ;;
        "AP-STA-POLL-OK")
            timeout=$hass_timeout_conn
            ;;
        "AP-STA-DISCONNECTED")
            sleep 2
            if is_connected $mac; then
                logger -t $0 -p debug "push_event ignored as device is still online"
                return
            fi
            timeout=$hass_timeout_disc
            ;;
        *)
            logger -t $0 -p warning "push_event not handled"
            return
            ;;
    esac

    post $(build_payload "$mac" "$(get_host_name $mac)" "$timeout")
}

sync_state() {
    logger -t $0 -p debug "sync_state $@"

    config_get hass_timeout_conn global timeout_conn

    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
        for mac in $maclist; do
            post $(build_payload "$mac" "$(get_host_name $mac)" "$hass_timeout_conn") &
        done
    done
}
