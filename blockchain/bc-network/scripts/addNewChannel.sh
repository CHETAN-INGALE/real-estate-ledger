#!/bin/bash

CLIENT_CA_relpath='tls/ca.crt'
ROOT="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"

printHelp() {
    echo "This script creates a new channel"
    echo
    echo
    echo
    echo
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
                AVIABLE_CHOICES_PEERS+=("$NODE_NAME")
                AVIABLE_CHOICES_ORGS+=("$org")
                AVIABLE_CHOICES_TYPES+=("$type")

            else
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

function addNewChannelParams() {
    source "$ROOT/globalParams.sh"

    exportNetworkParams

    CHANNEL_ORGS=()
    ORDERER_ORGS=""
    ORDERER_NODES=""
    CLIENT_ORGS=""
    CLIENT_NODES=""

    matchip 'client'
    for i in "${!AVIABLE_CHOICES_PEERS[@]}"; do

        CLIENT_ORGS+="${AVIABLE_CHOICES_ORGS[i]} "
        CLIENT_NODES+="${AVIABLE_CHOICES_PEERS[i]} "

    done

    matchip 'order'
    for i in "${!AVIABLE_CHOICES_PEERS[@]}"; do

        ORDERER_ORGS+="${AVIABLE_CHOICES_ORGS[i]} "
        ORDERER_NODES+="${AVIABLE_CHOICES_PEERS[i]} "

    done

    echo
    echo
    echo
    echo "SET THE NEW CHANNEL PARAMS"
    echo
    echo
    echo

    # Extract all Consortium names from the configtx.yaml file
    EXISTING_CONSORTIUMS=$(grep -oP 'Consortium:\s+\K\w+' "$ROOT/configtx/configtx.yaml" | awk '!seen[$0]++ {printf "%s ", $0}')

    # Prompt the user to enter one of the existing consortium names
    read -p "Enter CONSORTIUM NAME in which the channel should be added (e.g., $EXISTING_CONSORTIUMS): " CONSORTIUM_NAME

    read -p "Enter CHANNEL NAME : " NEW_CHANNEL_NAME

    if [ $NEW_CHANNEL_NAME != ${NEW_CHANNEL_NAME,,} ]; then

        read -p "Fabric does not allow a channel's name to have capital letters, would you like to change the name in ${NEW_CHANNEL_NAME,,}? Enter y to continue or n to abort. " -n 1 -r
        echo
        NEW_CHANNEL_NAME=${NEW_CHANNEL_NAME,,}
        if [ "$REPLY" = "n" ]; then
            exit 1
        fi
    fi

    read -p "Enter CHANNEL CREATOR (AVAILABLE CLIENT ORGS = $CLIENT_ORGS): " NEW_CHANNEL_CREATOR

    while ! [[ " ${CLIENT_ORGS[*]} " == *" ${NEW_CHANNEL_CREATOR} "* ]]; do

        echo "ERR => Please choose one of the following options:"
        read -p "Enter CHANNEL CREATOR (AVAILABLE CLIENT ORGS = $CLIENT_ORGS): " NEW_CHANNEL_CREATOR
    done
    checkExistance $CLIENT_ORGS $NEW_CHANNEL_CREATOR

    read -p "Enter CHANNEL_ORDERER_ORG (AVAILABLE ORDERER ORGS = $ORDERER_ORGS): " NEW_CHANNEL_ORDERER_ORG
    while ! [[ " ${ORDERER_ORGS[*]} " == *" ${NEW_CHANNEL_ORDERER_ORG} "* ]]; do
        echo "ERR => Please choose one of the following options:"
        read -p "Enter CHANNEL_ORDERER_ORG (AVAILABLE ORDERER ORGS = $ORDERER_ORGS): " NEW_CHANNEL_ORDERER_ORG
    done
    checkExistance $ORDERER_ORGS $NEW_CHANNEL_ORDERER_ORG

    source "$(listConfigParams 'order' $NEW_CHANNEL_ORDERER_ORG)"
    exportNode1Params
    CHANNEL_ORD_HOST=$NODE_HOST
    CHANNEL_ORD_PORT=$NODE_PORT

    read -p "Enter CHANNEL_ORDERER_NODE (AVAILABLE ORDERER NODES = ${MEMBERS[*]}): " NEW_CHANNEL_ORDERER_NODE
    while ! [[ " ${MEMBERS[*]} " == *" ${NEW_CHANNEL_ORDERER_NODE} "* ]]; do
        echo "ERR => Please choose one of the following options:"
        read -p "Enter CHANNEL_ORDERER_ORG (AVAILABLE ORDERER NODES = ${MEMBERS[*]}): " NEW_CHANNEL_ORDERER_NODE
    done

    STR=$(echo ${MEMBERS[*]})
    checkExistance $STR $NEW_CHANNEL_ORDERER_NODE

    read -p "Enter CHANNEL MEMBERS number : " NEW_NUM_MEMBERS
    removedpeers=()
    for ((i = 1; i <= $NEW_NUM_MEMBERS; i++)); do
        read -p "Enter CHANNEL MEMBER$i ORG (AVAILABLE CLIENT ORGS = $CLIENT_ORGS) : " SELECTED_ORG
        while ! [[ " ${CLIENT_ORGS[*]} " == *" ${SELECTED_ORG} "* ]]; do
            echo "ERR => Please choose one of the following options:"
            read -p "Enter CHANNEL MEMBER$i ORG (AVAILABLE CLIENT ORGS = $CLIENT_ORGS) : " SELECTED_ORG
        done
        CHANNEL_ORGS+=("$SELECTED_ORG")

        UNIQUE_CHANNEL_ORGS=$(printf '%s\n' "${CHANNEL_ORGS[*]}" | awk -v RS='[[:space:]]+' '!a[$0]++{printf "%s%s", $0, RT}')
        UNIQUE_CHANNEL_ORGS=($UNIQUE_CHANNEL_ORGS)

        #add comand to check the element posisition 1
        for h in "${!UNIQUE_CHANNEL_ORGS[@]}"; do
            if [[ "${UNIQUE_CHANNEL_ORGS[$h]}" = "${SELECTED_ORG}" ]]; then
                index=$h
                break
            fi
        done
        checkExistance $CLIENT_ORGS $SELECTED_ORG
        source "$(listConfigParams 'client' $SELECTED_ORG)"

        for target in "${removedpeers[@]}"; do
            for f in "${!MEMBERS[@]}"; do
                if [[ ${MEMBERS[f]} = $target ]]; then
                    unset 'MEMBERS[f]'
                fi
            done
        done
        
        read -p "Enter CHANNEL MEMEBER$i NODE (AVAILABLE CLIENT PEERS = ${MEMBERS[*]}) : " SELECTED_NODE
        while ! [[ " ${MEMBERS[@]} " == *" ${SELECTED_NODE} "* ]]; do
            echo "ERR => Please choose one of the following options:"
            read -p "Enter CHANNEL MEMBER$i NODE (AVAILABLE CLIENT PEERS = ${MEMBERS[@]}) : " SELECTED_NODE
        done
        removedpeers+=("$SELECTED_NODE")
        cmd3="CHANNEL_ORG${index}_NODES+=("$SELECTED_NODE")"

        eval $cmd3

        STR=$(echo ${MEMBERS[*]})
        checkExistance $STR $SELECTED_NODE

    done

    export NUM_CHANNELS_NEW=$((NUM_CHANNELS + 1))
    echo "exportChannel${NUM_CHANNELS_NEW}Params () {" >>globalParams.sh
    echo "export CHANNEL_NAME='$NEW_CHANNEL_NAME' " >>globalParams.sh
    echo "export CHANNEL_PROFILE='${NEW_CHANNEL_NAME}Profile'" >>globalParams.sh
    echo "export CHANNEL_CREATOR='$NEW_CHANNEL_CREATOR'" >>globalParams.sh
    echo "local CHANNEL_ORDERER_ORG='$NEW_CHANNEL_ORDERER_ORG'" >>globalParams.sh
    echo "local CHANNEL_ORDERER_NAME='$NEW_CHANNEL_ORDERER_NODE'" >>globalParams.sh
    echo "export ORDERER_HOST='$CHANNEL_ORD_HOST'" >>globalParams.sh
    echo "export ORDERER_PORT='$CHANNEL_ORD_PORT'" >>globalParams.sh
    echo 'source "$(listConfigParams "order" "$CHANNEL_ORDERER_ORG")" ' >>globalParams.sh
    echo 'local ORD_INDEX=$(getNodeIndex "$CHANNEL_ORDERER_NAME")' >>globalParams.sh
    echo 'exportNode"$ORD_INDEX"Params' >>globalParams.sh
    echo 'export ORDERER_CA="$NODE_PATH/msp/tlscacerts/tlsca.'${NEW_CHANNEL_ORDERER_ORG}'-cert.pem"' >>globalParams.sh
    echo 'export CHANNEL_ORDERER="$CHANNEL_ORDERER_NAME.$CHANNEL_ORDERER_ORG"' >>globalParams.sh
    echo "export NUM_MEMBERS='$NEW_NUM_MEMBERS'" >>globalParams.sh
    echo "export CHANNEL_ORGS=(${UNIQUE_CHANNEL_ORGS[*]})" >>globalParams.sh
    for ((j = 1; j <= ${#UNIQUE_CHANNEL_ORGS[@]}; j++)); do
        k=$((j - 1))
        varname2="CHANNEL_ORG${k}_NODES[*]"
        NODE_NAMES_TEMP=${!varname2}

        echo "export CHANNEL_ORG${k}_NODES=(${NODE_NAMES_TEMP[*]})" >>globalParams.sh

    done
    echo "}" >>globalParams.sh

    sed -i "s/export NUM_CHANNELS='${NUM_CHANNELS}'/export NUM_CHANNELS='${NUM_CHANNELS_NEW}'/" globalParams.sh
    NEW_NETWORK_CHANNELS=(${NETWORK_CHANNELS[*]})
    NEW_NETWORK_CHANNELS+=($NEW_CHANNEL_NAME)
    sed -i "s/export NETWORK_CHANNELS=(${NETWORK_CHANNELS[*]})/export NETWORK_CHANNELS=(${NEW_NETWORK_CHANNELS[*]})/" globalParams.sh
    FINAL_CHANNEL+=($NEW_CHANNEL_NAME)

    Number=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_CHANNEL=()" | wc -l)
    if [[ "${Number}" -gt 0 ]]; then
        sed -i "s/export NEW_CHANNEL=()/export NEW_CHANNEL=(${NEW_CHANNEL_NAME})/" globalParams.sh
    else
        sed -i "s/export NEW_CHANNEL=(/export NEW_CHANNEL=(${FINAL_CHANNEL[*]}","/" globalParams.sh
    fi
    echo "    ${NEW_CHANNEL_NAME}Profile:" >>"$ROOT/configtx/configtx.yaml"
    echo "        Consortium: $CONSORTIUM_NAME" >>"$ROOT/configtx/configtx.yaml"
    echo "        <<: *ChannelDefaults" >>"$ROOT/configtx/configtx.yaml"
    echo "        Application:" >>"$ROOT/configtx/configtx.yaml"
    echo "            <<: *ApplicationDefaults" >>"$ROOT/configtx/configtx.yaml"
    echo "            Organizations:" >>"$ROOT/configtx/configtx.yaml"

    for orgs in "${!UNIQUE_CHANNEL_ORGS[@]}"; do
        echo "                - *${UNIQUE_CHANNEL_ORGS[orgs]}" >>"$ROOT/configtx/configtx.yaml"
    done

    echo "            Capabilities:" >>"$ROOT/configtx/configtx.yaml"
    echo "                <<: *ApplicationCapabilities" >>"$ROOT/configtx/configtx.yaml"

}

function addNewChannelRunTime() {

    local CHANNEL_INDEX="$1"

    # now run the script that creates a channel. This script uses configtxgen once
    # more to create the channel creation transaction and the anchor client updates.
    # configtx.yaml is mounted in the cli container, which allows us to use it to
    # create the channel artifacts

    "$ROOT/scripts/createChannel.sh" "$CHANNEL_INDEX" "$VERBOSE"
    if [ $? -ne 0 ]; then
        echo "Error !!! Create channel number $CHANNEL_INDEX failed"
        exit 1
    fi
}

function deployDefaultChaincode {
    local INDEX="$1"
    source "$ROOT/chaincodeParams.sh"
    if [ $NUM_CHAINCODES -lt 1 ]; then
        echo "Warning ! test chaincode not defined"
    else
        "$ROOT/scripts/chaincode.sh" 'e2e' "$INDEX"
        if [ $? -ne 0 ]; then
            echo "Error !!! Test chaincode deployment failed"
            exit 1
        fi
    fi
}
function checkExistance() {

    local array="$*"

    local newstring="${array% *}"
    local var="${array##* }"

    if [[ $newstring != *"$var"* ]]; then

        echo "ERR => The name $var does not match one of the available options { $newstring }"
        exit 1

    fi

}

addNewChannelParams
addNewChannelRunTime $NUM_CHANNELS_NEW

read -p "Do you want to perform the end to end test to the new channel? Enter y to continue or n to abort" -n 1 -r

NEW_CHANNEL_NAME=${NEW_CHANNEL_NAME,,}
if [ "$REPLY" = "y" ]; then
    deployDefaultChaincode $NUM_CHANNELS_NEW
else
    exit 1
fi
