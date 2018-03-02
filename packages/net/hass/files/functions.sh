function err_msg {
    logger -t $0 -p error $@
    echo $1 1>&2
}

function register_hook {
    logger -t $0 -p info "register_hook $@"
    if [ "$#" -ne 1 ]; then
        err_msg "register_hook missing interface"
        exit 1
    fi
    interface=$1
    
    hostapd_cli -i$interface -a/usr/lib/hass/push_event.sh &
}

function post {
    logger -t $0 -p info "post $@"
    if [ "$#" -ne 1 ]; then
        err_msg "POST missing payload"
        exit 1
    fi
    payload=$1
    
    config_get hass_host global host
    config_get hass_pw global pw
    
    curl "$hass_host/api/services/device_tracker/see" -X POST \
        -H 'Content-Type: application/json' \
        -H "X-HA-Access: $hass_pw" \
        --data-binary "$payload"
}

function build_payload {
    logger -t $0 -p info "build_payload $@"
    if [ "$#" -ne 3 ]; then
        err_msg "Invalid payload parameters"
        logger -t $0 -p warning "push_event not handled"
        exit 1
    fi
    mac=$1
    host=$2
    consider_home=$3
    
    echo "{\"mac\":\"$mac\",\"host_name\":\"$host\",\"consider_home\":$consider_home,\"source_type\":\"router\"}"
}

function get_info {
    cat /tmp/dhcp.leases | cut -f 2,3,4 -s -d" " | grep $1
}

function host_name {
    # todo: if openwrt is not dhcp issuer, get hostname from local reverse dns
    get_info $1 | cut -f 3 -s -d" "
}

function ip {
    # todo: if openwrt is not dhcp issuer, get ip from arp table
    get_info $1 | cut -f 2 -s -d" "
}

function push_event {
    logger -t $0 -p info "push_event $@"
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
            timeout=$hass_timeout_disc
            ;;
        *)
            logger -t $0 -p warning "push_event not handled"
            return
            ;;
    esac

    post $(build_payload "$mac" "$(host_name $mac)" "$timeout")
}

function sync_state {
    logger -t $0 -p info "sync_state $@"

    config_get hass_timeout_conn global timeout_conn

    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
        for mac in $maclist; do
            post $(build_payload "$mac" "$(host_name $mac)" "$hass_timeout_conn")
        done
    done
}
