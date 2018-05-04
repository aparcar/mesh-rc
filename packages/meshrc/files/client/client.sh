#!/bin/sh

. /usr/share/libubox/jshn.sh

# loads trusted bmx7 ids from lime(-defaults)
trusted_ids=$(uci -q get lime-defaults.meshrc.trusted)
[[ -z "$trusted_ids" ]]  && {
    trusted_ids=$(uci -q get lime.meshrc.trusted)
    [[ -z "$trusted_ids" ]] && {
        uci -q set lime.meshrc="lime"
        uci -q add_list lime.meshrc.trusted=""
        echo "please add section trusted_nodes in /etc/config/lime"
        exit 1
    }
}

# parses the own shortid and stores it in uci format
bmx7_shortid="$(uci -q get lime.system.bmx7_shortid)"
bmx7_nodeid="$(uci -q get lime.system.bmx7_nodeid)"
[[ -z "$bmx7_shortid" || -z "$bmx7_nodeid" ]] && {
    json_load "$(cat /var/run/bmx7/json/status)"
    json_select status
    json_get_var bmx7_shortid shortId
    json_get_var bmx7_nodeid nodeId
    uci -q set lime.system.bmx7_shortid="$bmx7_shortid"
    uci -q set lime.system.bmx7_nodeid="$bmx7_nodeid"
    uci commit lime
}

# return all node ids currently active in the network
active_node_ids() {
    echo "$(ls -1 /var/run/bmx7/json/originators/)"
}

# return all node ids which acked the comment $1
acked_command() {
    # own ack isn't in rcvdSms folder
    echo "$bmx7_nodeid"
    # trusted nodes may don't run the client and so no acks
    echo "$trusted_ids"
    # all acks from other nodes running the client
    echo "$(ls /var/run/bmx7/sms/rcvdSms/*:${1}-ack | cut -d '/' -f 7 | \
            cut -d ':' -f 1)"
}

# sync cmd $1-ack to the cloud and wait until all other nodes acked it
wait_cloud_synced() {
    logger meshrc "wait for cloud sync ${1}"
    # create & share acked file
    touch "/var/run/bmx7/sms/sendSms/${1}-ack"
    /usr/sbin/bmx7 -c syncSms="${1}-ack"

    # give it some time
    sleep 5

    # wait until cloud is synced
    while [[ "$(active_node_ids | sort)" != "$(acked_command $1 | sort)" ]]; do
        sleep 5
    done
    logger meshrc "synced cloud for ${1}"
}

while true; do
    changes=0
    for trusted_id in $trusted_ids; do
        [[ -z "$trusted_id" ]] && return
        for config_path in ls /var/run/bmx7/sms/rcvdSms/${trusted_id}*; do
            config_file="$(basename $config_path | cut -d ':' -f 2)"
            logger meshrc "received config of trusted node ${config_file}"
            case $config_file in
                # change the mesh password
                mesh)
                    logger meshrc "net mesh password received"
                    uci -q set lime.wifi.ieee80211s_key="$(cat $config_path)"
                    wait_cloud_synced "$config_file"
                    changes=1
                    ;;
                # change access point password
                ap|ap_${bmx7_shortid})
                    logger meshrc "change nodes access point password"
                    uci -q set lime.wifi.ap_key="$(cat $config_path)"
                    [ ! "$config_file" = *"_$bmx7_shortid" ] && \
                        wait_cloud_synced "$config_file"
                    changes=1
                    ;;
                # resets everything
                fb|fb_${bmx7_shortid})
                    logger meshrc "resetting system via firstboot"
                    wait_cloud_synced "$config_file"
                    firstboot -y
                    reboot
                    ;;
                # change the lime-defaults file
                ld|ld_${bmx7_shortid})
                    logger meshrc "apply new lime-defaults"
                    [ ! "$config_file" = *"_$bmx7_shortid" ] && \
                        wait_cloud_synced "$config_file"
                    cp $config_path /etc/config/lime-defaults

                    # remove everything except the given hostname
                    uci delete lime.wifi
                    uci delete lime.network
                    changes=1
                    ;;
                # change hostname of single node
                hn_${bmx7_shortid})
                    logger meshrc "change hostname"
                    uci -q set lime.system.hostname="$(cat $config_path)"
                    changes=1
                    ;;
                raw|raw_${bmx7_shortid})
                    logger meshrc "run raw command : $(cat $config)"
                    eval "$(cat $config_path)"
                    ;;
                as|as_${bmx7_shortid})
                    logger meshrc "add ssh key: $(cat $config)"
                    echo "$(cat $config_path)" >> /etc/dropbear/authorized_keys
                    ;;
                ds|ds_${bmx7_shortid})
                    logger meshrc "remove ssh key: $(cat $config)"
                    sed -i "/$(cat $config_path)/" /etc/dropbear/authorized_keys
                    ;;
            esac
        done
    done
    if [[ "$changes" == "1" ]]; then
        uci commit lime
        lime-config
        lime-apply
    fi

    # wait for received sms
    inotifywait -e delete -e create -e modify /var/run/bmx7/sms/rcvdSms
done