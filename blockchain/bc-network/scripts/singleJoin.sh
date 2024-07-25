#!/bin/bash
ROOT="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"

export CORE_PEER_TLS_ENABLED=true
CLIENT_CA_relpath='tls/ca.crt'

setGlobals() {
    if [ "$#" -eq 2 ]; then
        local ORG="$1"
    elif [ "$#" -eq 0 ]; then
        local ORG="$CHANNEL_CREATOR"
    fi
    CONFIG_PARAMS=$(listConfigParams 'client' "$ORG")
    source "$CONFIG_PARAMS"
    exportGlobalParams
    exportOrgParams
    if [ "$#" -eq 2 ]; then
        local ORG="$1"
        local NODE="$2"
        local NODE_INDEX="$(getNodeIndex $NODE)"
    elif [ "$#" -eq 0 ]; then
        local ORG="$CHANNEL_CREATOR"
        local NODE_INDEX='1'
    else
        echo "expected usage: setGlobals [ORG_NAME NODE_NAME]"
        exit 1
    fi
    [ $LOG_LEVEL -ge 3 ] && echo "Using organization $ORG"

    exportNode"$NODE_INDEX"Params
    export CORE_PEER_TLS_ROOTCERT_FILE="$NODE_PATH/$CLIENT_CA_relpath"
    export CORE_PEER_ADDRESS="$NODE_HOST:$NODE_PORT"
    export CORE_PEER_LOCALMSPID="$MSP_NAME"
    export CORE_PEER_MSPCONFIGPATH="$BASE_DIR/users/Admin@$ORG_NAME/msp"
    export FABRIC_LOGGING_SPEC="${FABRIC_LOGS[$LOG_LEVEL]}"

    [ $LOG_LEVEL -ge 4 ] && env | grep CORE
}

function matchip() {
    PUBLIC_IP="localhost"
    ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
    ip6=$(/sbin/ip -o -6 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
    AVIABLE_CHOICES_PEERS=()
    AVIABLE_CHOICES_ORGS=()
    AVIABLE_CHOICES_TYPES=()
    local all='false'
    if [ "$#" -eq 2 ]; then
        local type="$1"
        local name="$2"
        echo "$ROOT/organizations/$type/$name/configParams.sh"
    elif [ "$#" -eq 1 ]; then
        # list all organizations of the given type if no name is specified
        local type="$1"
        for org in $(ls "$ROOT/organizations/$type"); do
            source "$ROOT/organizations/$type/$org/configParams.sh"
            exportNode1Params
            if [ "$NODE_HOST" = "$PUBLIC_IP" ]; then
                # echo "ip are equal"
                AVIABLE_CHOICES_PEERS+=("$NODE_NAME")
                AVIABLE_CHOICES_ORGS+=("$org")
                AVIABLE_CHOICES_TYPES+=("$type")
            else
                # echo "ip are not equal"
                REMOTE_CHOICES_PEERS+=("$NODE_NAME")
                REMOTE_CHOICES_ORGS+=("$org")
                REMOTE_CHOICES_TYPES+=("$type")
            fi
        done
    elif [ "$#" -eq 0 ]; then
        # list all organizations if none is specified
        for type in 'client' 'order'; do
            matchip $type
        done
    else
        echo "expected usage: matchip [ <client|order> [ORG_NAME] ]"
        exit 1
    fi
}
function newPeerJoin() {

    ORG="$1"
    PEERS_STRING="$2"

    IFS=' '
    ARR_NODE=($PEERS_STRING)
    IFS=$'\n'

    export FABRIC_CFG_PATH="$ROOT/../config/"

    for node in "${!ARR_NODE[@]}"; do
        NODE=${ARR_NODE[node]}

        echo $NODE
        setGlobals "$ORG" "$NODE"
        local rc=1
        local COUNTER=0
        ## Sometimes Join takes time, hence retry
        while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
            sleep $CLI_DELAY
            [ $LOG_LEVEL -ge 4 ] && set -x

            peer channel join -b "$ROOT/channel-artifacts/$CHANNEL_NAME.block" >&log.txt
            rc=$?
            [ $LOG_LEVEL -ge 4 ] && set +x
            ((COUNTER++))
        done

        cat log.txt
        rm log.txt
        echo "CHECKING BLOCK HEIGHT"
        while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
            sleep $CLI_DELAY
            [ $LOG_LEVEL -ge 4 ] && set -x
            peer channel getinfo -c $CHANNEL_NAME >&channelInfo.txt
            rc=$?
            [ $LOG_LEVEL -ge 4 ] && set +x
            ((COUNTER++))
        done
    done
    cat channelInfo.txt
    rm channelInfo.txt
}

function main() {
    source "$ROOT/globalParams.sh"
    exportNetworkParams
    read -p "In which channel should this organization first join? Available choice : ${NETWORK_CHANNELS[*]} : " CH_NAME

    for num in "${!NETWORK_CHANNELS[@]}"; do

        if [[ ${NETWORK_CHANNELS[num]} = $CH_NAME ]]; then

            index=$((num + 1))
        fi

    done
    exportChannel"$index"Params

    CLIENT_ORGS=""
    CLIENT_NODES=""

    matchip 'client'
    for i in "${!AVIABLE_CHOICES_PEERS[@]}"; do

        CLIENT_ORGS+="${AVIABLE_CHOICES_ORGS[i]} "
        CLIENT_NODES+="${AVIABLE_CHOICES_PEERS[i]} "

    done

    echo
    read -p "Enter ORG NAME ( Available choice: $CLIENT_ORGS) : " ORG_NAME
    read -p "Enter PEERS NAMES separated by space ( e.g Peer1 Peer2) : " NEW_MEMBERS_STR

    newPeerJoin "$ORG_NAME" "$NEW_MEMBERS_STR"

    filename="$ROOT/globalParams.sh"

    echo "UPDATING GLOBAL PARAMS"

    NEW_ORGS=$(echo "${CHANNEL_ORGS[@]} $NEW_ORG_NAME")
    OLD_ORGS=$(echo "${CHANNEL_ORGS[@]}")
    sed -i "s/  export CHANNEL_ORGS=($OLD_ORGS)/  export CHANNEL_ORGS=($NEW_ORGS) \n  export CHANNEL_ORG${#CHANNEL_ORGS[@]}_NODES=(${NEW_PEERS_STRING})/" "$filename"

    NEW_NUM_CHANNEL_SIZE=$(($CHANNEL_SIZE+1))
    sed -i "s/export CHANNEL_SIZE='$CHANNEL_SIZE'/export CHANNEL_SIZE='$NEW_NUM_CHANNEL_SIZE'/" "$filename"

    IFS=' '
    ARR_NODE=($NEW_PEERS_STRING)
    IFS=$'\n'

    NEW_NUM_MEMBERS=$(($NUM_MEMBERS+${#ARR_NODE[@]}))
    sed -i "s/export NUM_MEMBERS='$NUM_MEMBERS'/export NUM_MEMBERS='$NEW_NUM_MEMBERS'/" "$filename"


    for node in "${!ARR_NODE[@]}"; do
        NODE=${ARR_NODE[node]}
        local INDEX=$(($NUM_MEMBERS+$node+1))
        sed -i "/export NUM_MEMBERS=/i   export CHANNEL_MEMBER${INDEX}_NODE='${NODE}'\n  export CHANNEL_MEMBER${INDEX}_ORG='${ORG}'\n" "$filename"
    done

    echo "GLOBAL PARAMS UPDATED"
}
main