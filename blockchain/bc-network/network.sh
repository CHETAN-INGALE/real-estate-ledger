
#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric network for testing smart contracts
# and applications. The test network consists of two organizations with one
# client each, and a single node Raft ordering service. Users can also use this
# script to create a channel deploy a chaincode on the channel

# the absolute path where this file is
export ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"
# prepending $ROOT/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH="$ROOT/../bin":$PATH
export VERBOSE=false

set -e
# Obtain the OS and Architecture string that will be used to select the correct
# native binaries for your platform, e.g., darwin-amd64 or linux-amd64
OS_ARCH=$(echo "$(uname -s | tr '[:upper:]' '[:lower:]' | sed 's/mingw64_nt.*/windows/')-$(uname -m | sed 's/x86_64/amd64/g')" | awk '{print tolower($0)}')

# avoid docker-compose warning about orphan containers
export COMPOSE_IGNORE_ORPHANS=True

# contains model-specific configurations and variables
source "$ROOT/globalParams.sh"
exportNetworkParams

# Print the usage message
# TODO: print an informative help message
function printHelp() {
    echo "Usage: ./network.sh [OPTS] MODE"
    echo "MODE:"
    echo "                  up    executes the whole network from a clean start, including channels"
    echo "                down    tears down the network as configured"
    echo "               clear    reverts the network to the initial state by removing all the newly added channels and orgs"
    echo "       addNewChannel    adds a new channel to the network"
    echo "             newNode    adds a new node to the network"
    echo "           addNewOrg    adds a new organization to the network"
    echo "          singleJoin    adds a new organization to a channel"
    echo "OPTS (global defaults are defined in globalParams.sh):"
    echo "              -d <n>    retry failed commands every n seconds"
    echo "              -h        print this help message"
    echo "              -l <n>    set verbosity: 1->error, 2->warning, 3->info, 4->debug, 5->trace"
    echo "              -r <n>    retry failed commands n times before giving up"
    echo "              -v        verbose output: same as -l 4"
    echo
}

function checkOrLaunchSetup() {
    # retrieve the 'configParams.sh' script for every node and export its global variables
    IFS=$'\n'
    for PARAMS_FILE in $(listConfigParams); do
        source "$PARAMS_FILE"
        exportGlobalParams
        # check whether the setup was already executed
        # TODO: find a better way to tell whether the setup is complete or not
        if [ ! -r "$BASE_DIR/ca-server/tls-cert.pem" ]; then
            exportOrgParams
            # if [ ! -x "$ORG_SETUP_SCRIPT" ]
            # then
            #   echo "$ORG_SETUP_SCRIPT not executable"
            #   exit 1
            # fi
            # execute the setup script
            "$ORG_SETUP_SCRIPT"
            STATUS=$?
            if [ ! $STATUS -eq 0 ]; then
                [ $LOG_LEVEL -ge 2 ] && echo "setup script failed with exit status $STATUS: $ORG_SETUP_SCRIPT"
                exit 1
            fi
        fi
    done
}

# Generate orderer (system channel) genesis block.
function createGenesisBlock() {
    [ $LOG_LEVEL -ge 3 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Generate Orderer Genesis block"
    [ $LOG_LEVEL -ge 3 ] && echo
    # skip genesis block creation if it already exists
    if [ -f "$ROOT/system-genesis-block/genesis.block" ]; then
      [ $LOG_LEVEL -ge 2 ] && echo "genesis block already exists, skipping creation..."
      return
    fi
    # Note: For some unknown reason (at least for now) the block file can't be
    # named orderer.genesis.block or the orderer will fail to launch!
    [ $LOG_LEVEL -ge 5 ] && set -x
    configtxgen -profile "$GENESIS_PROFILE" -channelID 'syschannel' \
      -outputBlock "$ROOT/system-genesis-block/genesis.block" \
      -configPath "$ROOT/configtx/" &>log.txt
    res=$?
    [ $LOG_LEVEL -ge 5 ] && set +x
    [ $LOG_LEVEL -ge 4 ] && cat log.txt
    if [ $res -ne 0 ]; then
      echo $'\e[1;32m'"Failed to generate orderer genesis block..."$'\e[0m'
      exit 1
    fi
}

# After we create the org crypto material and the system channel genesis block,
# we can now bring up the clients and orderering service. By default, the base
# file for creating the network is "docker-compose-test-net.yaml" in the ``docker``
# folder. This file defines the environment variables and file mounts that
# point the crypto material and genesis block that were created in earlier.

# Bring up the client and orderer nodes using docker compose.
function networkUp {
    checkOrLaunchSetup && createGenesisBlock
}

function orgsUp() {
    if [ "$#" -eq 0 ]; then
        # find all the 'configParams.sh' scripts in the subtree and export their global variables
        IFS=$'\n'
        for PARAMS_FILE in $(listConfigParams); do
            source "$PARAMS_FILE"
            exportOrgParams
            # if [ ! -x "$ORG_UP_SCRIPT" ]
            # then
            #   echo "$ORG_UP_SCRIPT not executable"
            #   exit 1
            # fi
            # bring up the organization
            "$ORG_UP_SCRIPT"
            STATUS=$?
            if [ ! $STATUS -eq 0 ]; then
                [ $LOG_LEVEL -ge 2 ] && echo "orgUp script failed with exit status $STATUS: $ORG_UP_SCRIPT"
                exit 1
            fi
        done
    elif [ "$#" -eq 2 ]; then
        local type="$1"
        local name="$2"
        source "$ROOT/organizations/$type/$name/configParams.sh"
        exportOrgParams
        # if [ ! -x "$ORG_UP_SCRIPT" ]
        # then
        #   echo "$ORG_UP_SCRIPT not executable"
        #   exit 1
        # fi
        # bring up the organization
        "$ORG_UP_SCRIPT"
        STATUS=$?
        if [ ! $STATUS -eq 0 ]; then
            [ $LOG_LEVEL -ge 2 ] && echo "orgUp script failed with exit status $STATUS: $ORG_UP_SCRIPT"
            exit 1
        fi
    fi
}

function matchip() {

    # PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)

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

## call the script to join create the channel and join the clients of org1 and org2
function createChannels() {

    for ((I = 1; I <= "$NUM_CHANNELS"; I++)); do
        # now run the script that creates a channel. This script uses configtxgen once
        # more to create the channel creation transaction and the anchor client updates.
        # configtx.yaml is mounted in the cli container, which allows us to use it to
        # create the channel artifacts
        CHANNEL_INDEX="$I"
        "$ROOT/scripts/createChannel.sh" "$CHANNEL_INDEX" "$VERBOSE"
        if [ $? -ne 0 ]; then
            echo "Error !!! Create channel number $CHANNEL_INDEX failed"
            exit 1
        fi
    done
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

source "$ROOT/binaries.sh"

function up {
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 2 ] && echo '=================== LAUNCH NETWORK ======================'
    binariesMain && networkUp && orgsUp && createChannels && deployDefaultChaincode "1"
    [ $LOG_LEVEL -ge 2 ] && echo '============ NETWORK LAUNCHED SUCCESSFULLY =============='
}

# Delete any images that were generated as a part of this setup
# specifically the following images are often left behind:
# This function is called when you bring the network down
function removeUnwantedImages() {
    DOCKER_IMAGE_IDS=$(docker images | awk '($1 ~ /dev-client.*/) {print $3}')
    if [ -z "$DOCKER_IMAGE_IDS" -o "$DOCKER_IMAGE_IDS" == " " ]; then
        [ $LOG_LEVEL -ge 4 ] && echo "---- No images available for deletion ----"
    else
        docker rmi -f $DOCKER_IMAGE_IDS
    fi
}

# Tear down running network
function networkDown() {
    [ $LOG_LEVEL -ge 2 ] && echo '============ CLEANUP NETWORK =============='
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo 'Stop and delete containers alongside with their volumes'
    set +e
    sed -i "s/CHANNEL_DEPLOYED=.*/CHANNEL_DEPLOYED=()/g" customChaincodeParams.sh
    IFS=$'\n'
    for PARAMS_FILE in $(listConfigParams); do
        source "$PARAMS_FILE"
        exportGlobalParams
        exportCaParams
        exportOrgParams
        [ $LOG_LEVEL -ge 3 ] && echo
        [ $LOG_LEVEL -ge 3 ] && echo "-> stop and delete CA containers: $CA_NAME"
        [ $LOG_LEVEL -ge 3 ] && echo
        [ $LOG_LEVEL -ge 5 ] && set -x
        IMAGE_TAG="$CA_IMAGETAG" docker-compose --log-level ERROR -f "$CA_COMPOSE_FILE" -p "$PROJECT_NAME" \
        exec "$CA_NAME" 'rm -rf /etc/hyperledger/fabric-ca-server/*' 2>log.txt
        IMAGE_TAG="$CA_IMAGETAG" docker-compose --log-level ERROR -f "$CA_COMPOSE_FILE" -p "$PROJECT_NAME" \
        down --volumes 2>>log.txt
        [ $LOG_LEVEL -ge 4 ] && cat log.txt
        rm -f "$CA_COMPOSE_FILE"
        for ((I = 1; I <= NODE_NUM; I++)); do
            exportNode"$I"Params
            [ $LOG_LEVEL -ge 3 ] && echo
            [ $LOG_LEVEL -ge 3 ] && echo "-> stop and delete node containers: $NODE_FULL_NAME"
            [ $LOG_LEVEL -ge 3 ] && echo
            IMAGE_TAG="$NODE_IMAGETAG" docker-compose --log-level ERROR -f "$NODE_COMPOSE_FILE" -p "$PROJECT_NAME" \
                down --volumes 2>log.txt
            [ $LOG_LEVEL -ge 4 ] && cat log.txt
            rm -f "$NODE_COMPOSE_FILE"
            #TODO find cleaner solution: workaround volume not removed
            docker volume rm -f "$NODE_FULL_NAME"
        done

        # ./configtxlator proto_decode --input config_block.pb --type common.Block --output config.json | > jq .data.data[0].payload.data.config >config2.json

        ## remove fabric ca artifacts -- client config files are kept since they are different from defaults
        rm -rf "$BASE_DIR/ca-server" "$BASE_DIR/users" "$BASE_DIR/orderers" "$BASE_DIR/clients" "$BASE_DIR/tlsca"
        [ $LOG_LEVEL -ge 5 ] && set +x
    done
    # Don't remove the generated artifacts -- note, the ledgers are always removed
    removeUnwantedImages
    # remove orderer block and other channel configuration transactions and certs
    rm -rf "$ROOT/system-genesis-block"/*.block

    # remove channel and script artifacts
    rm -rf "$ROOT/channel-artifacts" "$ROOT/log.txt"
    set -e
}

function clear() {
    echo "You are going to remove all the newly added channels and organizations"
    read -p "If you want to continue prees y, else press n" -n 1 -r
    echo
    if [ "$REPLY" = "y" ]; then
  
      [ $LOG_LEVEL -ge 2 ] && echo '============ CLEANUP NEWLY ADDED NETWORK AND ORGANIZATIONS =============='
      [ $LOG_LEVEL -ge 2 ] && echo
      [ $LOG_LEVEL -ge 3 ] && echo 'Stop and delete containers alongside with their volumes'
  
      source "$ROOT/globalParams.sh"
  
      NEWG=$NEW_ORG
      arr=(${NEWG//,/ })
      for ((I = 0; I < ${#arr[@]}; I++)); do
        rm -rf "$ROOT/organizations/client/${arr[$I]}"
        rm -rf "$ROOT/organizations/order/${arr[$I]}"
        sed -i "/- &${arr[$I]}/,/AnchorPeers:/d" "$ROOT"/configtx/configtx.yaml
      done
  
      NEWC=$NEW_CHANNEL
      arr2=(${NEWC//,/ })
      for ((J = 0; J < ${#arr2[@]}; J++)); do
        NUM_CHANNELS_NEW=$((NUM_CHANNELS - $J))
        sed -i "/exportChannel${NUM_CHANNELS_NEW}/,/}/d" globalParams.sh
        sed -i "/${arr2[$J]}/,/ApplicationCapabilities/g" "$ROOT"/configtx/configtx.yaml
      done
      NEW_NUM_CHANNELS=$((NUM_CHANNELS - ${#arr2[@]}))
  
      ORIGINAL_CHANNELS=$(echo "${NETWORK_CHANNELS[@]}" | head -n $NEW_NUM_CHANNELS | cut -d " " -f 1-$NEW_NUM_CHANNELS)
      ORIGINAL_CHANNELS=($ORIGINAL_CHANNELS)
      sed -i "s/export NETWORK_CHANNELS=(${NETWORK_CHANNELS[*]})/export NETWORK_CHANNELS=(${ORIGINAL_CHANNELS[*]})/" globalParams.sh
      sed -i "s/export NUM_CHANNELS='$NUM_CHANNELS'/export NUM_CHANNELS='${NEW_NUM_CHANNELS}'/" globalParams.sh
  
      sed -i "s/export NEW_CHANNEL=.*//" globalParams.sh
      sed -i "s/export NEW_ORG=.*//" globalParams.sh
    else
      exit
    fi
}

function networkReset() {
    networkDown
  
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 2 ] && echo '============ RESET NETWORK =============='
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo 'Remove dynamically introduced nodes from the configParams'
    [ $LOG_LEVEL -ge 3 ] && echo 
  
    set +e
    IFS=$'\n'
    for PARAMS_FILE in $(listConfigParams); do
        source "$PARAMS_FILE"
        exportOrgParams
        NEW_NODE_NUM=$(source $PARAMS_FILE && echo $NODE_NUM)
      
        for ((I = 1; I <= NODE_NUM; I++)); do
            source "$PARAMS_FILE"
            exportNode"$I"Params
            if [ "$RUNTIME" == "true" ]; then
                NEW_NODE_NUM=$((NEW_NODE_NUM - 1))
                sed -i "s/NODE_NUM=\"[0-9]*\"/NODE_NUM=\"$NEW_NODE_NUM\"/" "$PARAMS_FILE"
                START_MARKER="function exportNode"$I"Params {"
                END_MARKER="}"
                sed -i "/$START_MARKER/,/$END_MARKER/d" "$PARAMS_FILE"
            fi
        done
    done
    [ $LOG_LEVEL -ge 2 ] && echo '============ NETWORK RESET SUCCESSFULLY =============='
    [ $LOG_LEVEL -ge 2 ] && echo
}

function deleteNode() {
    local selected_node="$1"
    local params_file="$2"
    local I="$3"
    
    dir_path="$(dirname "$params_file")"
    new_node_value="node_"$I""
    new_docker_file="node_"$I"-compose.yaml"
    dir_path_newNode=$(dirname "$params_file")/clients/$new_node_value
    rm -r "$dir_path_newNode"
    rm $(dirname "$params_file")/docker/$new_docker_file
  
    NEW_NODE_NUM=$((NEW_NODE_NUM - 1))
    sed -i "s/NODE_NUM=\"[0-9]*\"/NODE_NUM=\"$NEW_NODE_NUM\"/" "$params_file"
    
    START_MARKER="function exportNode"$I"Params {"
    END_MARKER="}"
    sed -i "/$START_MARKER/,/$END_MARKER/d" "$params_file"
  
    
    
    NODES_TO_DELETE=($(docker ps -aqf "name=${selected_node}.${MSP_NAME}$"))
    if [ "${#NODES_TO_DELETE[@]}" -gt 0 ]; then
      echo "Stopping and Removing ${selected_node} Docker containers"
      docker stop "${NODES_TO_DELETE[@]}"
      docker rm "${NODES_TO_DELETE[@]}"
    else
      echo "Docker container for ${selected_node}.${MSP_NAME} does not exist"
    fi
}

function clearAll() {
    echo "You are going to remove all the newly added channels, organizations and nodes and all docker containers"
    read -p "If you want to continue press y, else press n" -n 1 -r
    echo
    if [ "$REPLY" = "y" ]; then

        [ $LOG_LEVEL -ge 2 ] && echo '============ CLEANUP NEWLY ADDED NETWORK, ORGANIZATIONS AND NODES =============='
        [ $LOG_LEVEL -ge 2 ] && echo
        [ $LOG_LEVEL -ge 3 ] && echo 'Stop and delete containers alongside with their volumes'

        for PARAMS_FILE in $(listConfigParams); do
            source "$PARAMS_FILE"
            exportOrgParams
            
            for ((I = 1; I <= NODE_NUM; I++)); do
                source "$PARAMS_FILE"
                exportNode"$I"Params
                if [ "$RUNTIME" == "true" ]; then
                    deleteNode "$NODE_NAME" "$PARAMS_FILE" "$I"
                fi
            done
        done

        source "$ROOT/globalParams.sh"

        NEWG=$NEW_ORG
        arr=(${NEWG//,/ })
        for ((I = 0; I < ${#arr[@]}; I++)); do
            rm -rf "$ROOT/organizations/client/${arr[$I]}"
            rm -rf "$ROOT/organizations/order/${arr[$I]}"
            sed -i "/- &${arr[$I]}/,/AnchorPeers:/d" "$ROOT"/configtx/configtx.yaml
        done

        NEWC=$NEW_CHANNEL
        arr2=(${NEWC//,/ })
        for ((J = 0; J < ${#arr2[@]}; J++)); do
            NUM_CHANNELS_NEW=$((NUM_CHANNELS - $J))
            sed -i "/exportChannel${NUM_CHANNELS_NEW}/,/}/d" globalParams.sh
            sed -i "/${arr2[$J]}/,/ApplicationCapabilities/g" "$ROOT"/configtx/configtx.yaml
        done
        NEW_NUM_CHANNELS=$((NUM_CHANNELS - ${#arr2[@]}))

        ORIGINAL_CHANNELS=$(echo "${NETWORK_CHANNELS[@]}" | head -n $NUM_CHANNELS | cut -d " " -f 1-$NUM_CHANNELS)
        ORIGINAL_CHANNELS=($ORIGINAL_CHANNELS)
        sed -i "s/export NETWORK_CHANNELS=(${NETWORK_CHANNELS[*]})/export NETWORK_CHANNELS=(${ORIGINAL_CHANNELS[*]})/" globalParams.sh
        sed -i "s/export NUM_CHANNELS='$NUM_CHANNELS'/export NUM_CHANNELS='${NEW_NUM_CHANNELS}'/" globalParams.sh
        for ((I = 1; I <= $NEW_NUM_CHANNELS; I++)); do
            echo "NEW_NUM_CHANNELS=$NEW_NUM_CHANNELS"
            exportChannel"$I"Params
            for target in "${arr[@]}"; do
                for i in "${!CHANNEL_ORGS[@]}"; do
                    if [[ ${CHANNEL_ORGS[i]} = $target ]]; then
                        export NEW_CHANNEL_ORGS=(${CHANNEL_ORGS[*]})
                        export toDelete="CHANNEL_ORG${i}_NODES"
                        unset 'CHANNEL_ORGS[i]'

                    fi
                done
            done

            sed -i "s/export CHANNEL_ORGS=.*/export CHANNEL_ORGS=(${CHANNEL_ORGS[*]})/" globalParams.sh

            sed -i "s/export $toDelete=.*//" globalParams.sh
        done
        sed -i "s/export NEW_CHANNEL=.*//" globalParams.sh
        sed -i "s/export NEW_ORG=.*//" globalParams.sh
        docker stop $(docker ps -a -q)
        docker rm $(docker ps -a -q)
    else
        exit
    fi
}

# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]]; then
    printHelp
    exit 0
fi

# parse input flags
while [[ $# -ge 1 ]]; do
    key="$1"
    case $key in
    -h)
        printHelp
        exit 0
        ;;
    -r)
        export MAX_RETRY="$2"
        shift
        ;;
    -d)
        export CLI_DELAY="$2"
        shift
        ;;
    -v)
        export LOG_LEVEL='4' # debug
        shift
        ;;
    -l)
        export LOG_LEVEL="$2" # from 1=error to 5=trace
        shift
        ;;
    up | down | clear | addNewChannel | newChannelServer | addNewOrg | newOrgServer | singleJoin | newNode | newNodeServer)
        MODE="$1"
        break
        ;;
    *)
        echo
        echo "Unknown flag: $key"
        echo
        printHelp
        exit 1
        ;;
    esac
    shift
done

# Determine mode of operation and printing out what we asked for
# TODO improve log messages
if [ "$MODE" == "up" ]; then
    echo
    echo "Cleanup and launch the entire network, including the creation and join of channels"
    echo
    networkDown
    up
elif [ "$MODE" == "down" ]; then
    echo
    echo "Stopping network"
    echo
    networkDown
elif [ "$MODE" == "clear" ]; then
    echo
    echo "Removing new added channel and organization"
    echo
    clear
elif [ "$MODE" == "addNewChannel" ]; then
    Number2=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_CHANNEL" | wc -l)
    if [[ "${Number2}" -lt 1 ]]; then
        sed -i "/export NUM_CHANNELS='${NUM_CHANNELS}'/a export NEW_CHANNEL=()" globalParams.sh
    fi
    echo
    echo "Creating new channel"
    echo
    "$ROOT/scripts/addNewChannel.sh"
elif [ "$MODE" == "newChannelServer" ]; then
    Number2=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_CHANNEL" | wc -l)
    if [[ "${Number2}" -lt 1 ]]; then
        sed -i "/export NUM_CHANNELS='${NUM_CHANNELS}'/a export NEW_CHANNEL=()" globalParams.sh
    fi
    echo
    echo "Creating new channel"
    echo
    "$ROOT/scripts/addNewChannelServer.sh"
elif [ "$MODE" == "newNode" ]; then
    echo
    echo "Creating new Node"
    echo
    EXIST_CLIENT=$(ls "$ROOT/organizations/client/" | xargs)

    read -p "Enter org name (options: $EXIST_CLIENT): " orgName
    while [[ ! " ${EXIST_CLIENT[*]} " =~ " ${orgName} " ]]; do
        echo "ERR => Invalid organization name. Please choose from the provided options."
        read -p "Enter org name (options: $EXIST_CLIENT): " orgName
    done

    MAX_INDEX=0
  
    CURRENT_INDEX=$(grep "local NODE_INDEX=" "$ROOT/organizations/client/$orgName/configParams.sh" | awk -F"'" '{print $2}' | sort -n | tail -1)
    if [[ "$CURRENT_INDEX" -gt "$MAX_INDEX" ]]; then
      MAX_INDEX=$CURRENT_INDEX
    fi

    nodeI=$((MAX_INDEX + 1))
    echo "node index: $nodeI"

    read -p "Enter Node name: " nodeName
    while [[ ${#nodeName} -lt 2 ]]; do
        echo "ERR => Node name should have at least 2 characters."
        read -p "Enter Node name again: " nodeName
    done

    declare -a PORT_EXIST=()
    # Populate PORT_EXIST array with existing ports
    for CHECK_INP in $(listConfigParams); do
        source "$CHECK_INP"
        exportCaParams
        PORT_EXIST+=("$CA_PORT")
        exportNode1Params
        PORT_EXIST+=("$NODE_PORT")
        PORT_EXIST+=("$NODE_PORT_CC")
    done

    # Define the array_contains function for checking
    array_contains() {
        local value="$1"
        shift
        for i; do
            [[ "$i" == "$value" ]] && return 0
        done
        return 1
    }

    # Get Node Port from user and check if it's unique
    echo "Existing ports: ${PORT_EXIST[@]}"
    read -p "Enter a unique Node Port: " nodePort
    while array_contains "$nodePort" "${PORT_EXIST[@]}"; do
        echo "Error! The port $nodePort is already in use."
        echo "Existing ports: (${PORT_EXIST[@]})"
        read -p "Enter a unique Node Port: " nodePort
    done
    PORT_EXIST+=("$nodePort")


    echo "Existing ports: ${PORT_EXIST[@]}"
    read -p "Enter a unique ccPort: " ccPort
    while array_contains "$ccPort" "${PORT_EXIST[@]}"; do
        echo "Error! The port $ccPort is already in use."
        echo "Existing ports: (${PORT_EXIST[@]})"
        read -p "Enter a unique Node CCPort: " ccPort
    done
    PORT_EXIST+=("$ccPort")
    source "$ROOT/organizations/client/$orgName/configParams.sh"
  
    echo "function exportNode${nodeI}Params {" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "local NODE_INDEX='${nodeI}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_NAME='${nodeName}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_FULL_NAME="$NODE_NAME.$ORG_NAME"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_HOST='localhost'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_IMAGETAG='2.2.0'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_PORT='${nodePort}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_PORT_CC='${ccPort}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_COMPOSE_FILE="$BASE_DIR/docker/node_$NODE_INDEX-compose.yaml"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_PATH="$BASE_DIR/clients/node_$NODE_INDEX"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export RUNTIME=true' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    sed -i "s/NODE_NUM=\"[0-9]*\"/NODE_NUM=\"${nodeI}\"/" "$ROOT/organizations/client/$orgName/configParams.sh"
    echo '}' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    cd "$ROOT/organizations/client/$orgName"
    echo "$nodeI" | "./addNewNode.sh"
elif [ "$MODE" == "newNodeServer" ]; then
    echo
    echo "Creating new Node"
    echo
    EXIST_CLIENT=$(ls "$ROOT/organizations/client/" | xargs)

    read -p "Enter org name (options: $EXIST_CLIENT): " orgName
    
    MAX_INDEX=0
    
    CURRENT_INDEX=$(grep "local NODE_INDEX=" "$ROOT/organizations/client/$orgName/configParams.sh" | awk -F"'" '{print $2}' | sort -n | tail -1)
    if [[ "$CURRENT_INDEX" -gt "$MAX_INDEX" ]]; then
        MAX_INDEX=$CURRENT_INDEX
    fi

    nodeI=$((MAX_INDEX + 1))
    echo "node index: $nodeI"

    read -p "Enter Node name: " nodeName
    while [[ ${#nodeName} -lt 2 ]]; do
        echo "ERR => Node name should have at least 2 characters."
        read -p "Enter Node name again: " nodeName
    done

    declare -a PORT_EXIST=()
    # Populate PORT_EXIST array with existing ports
    for CHECK_INP in $(listConfigParams); do
        source "$CHECK_INP"
        exportCaParams
        PORT_EXIST+=("$CA_PORT")
        exportNode1Params
        PORT_EXIST+=("$NODE_PORT")
        PORT_EXIST+=("$NODE_PORT_CC")
    done

    # Define the array_contains function for checking
    array_contains() {
        local value="$1"
        shift
        for i; do
            [[ "$i" == "$value" ]] && return 0
        done
        return 1
    }

    # Get Node Port from user and check if it's unique
    echo "Existing ports: ${PORT_EXIST[@]}"
    read -p "Enter a unique Node Port: " nodePort
    while array_contains "$nodePort" "${PORT_EXIST[@]}"; do
        echo "Error! The port $nodePort is already in use."
        echo "Existing ports: (${PORT_EXIST[@]})"
        read -p "Enter a unique Node Port: " nodePort
    done
    PORT_EXIST+=("$nodePort")


    echo "Existing ports: ${PORT_EXIST[@]}"
    read -p "Enter a unique ccPort: " ccPort
    while array_contains "$ccPort" "${PORT_EXIST[@]}"; do
        echo "Error! The port $ccPort is already in use."
        echo "Existing ports: (${PORT_EXIST[@]})"
        read -p "Enter a unique Node CCPort: " ccPort
    done
    PORT_EXIST+=("$ccPort")
    source "$ROOT/organizations/client/$orgName/configParams.sh"
    
    echo "function exportNode${nodeI}Params {" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "local NODE_INDEX='${nodeI}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_NAME='${nodeName}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_FULL_NAME="$NODE_NAME.$ORG_NAME"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_HOST='localhost'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_IMAGETAG='2.2.0'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_PORT='${nodePort}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo "export NODE_PORT_CC='${ccPort}'" >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_COMPOSE_FILE="$BASE_DIR/docker/node_$NODE_INDEX-compose.yaml"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export NODE_PATH="$BASE_DIR/clients/node_$NODE_INDEX"' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    echo 'export RUNTIME=true' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    sed -i "s/NODE_NUM=\"[0-9]*\"/NODE_NUM=\"${nodeI}\"/" "$ROOT/organizations/client/$orgName/configParams.sh"
    echo '}' >>"$ROOT/organizations/client/$orgName/configParams.sh"
    cd "$ROOT/organizations/client/$orgName"
    echo "$nodeI" | "./addNewNode.sh"
elif [ "$MODE" == "addNewOrg" ]; then
    Number=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_ORG" | wc -l)
    if [[ "${Number}" -lt 1 ]]; then
        sed -i "/export NUM_CHANNELS='${NUM_CHANNELS}'/a export NEW_ORG=()" globalParams.sh
    fi
    echo
    echo "Creating new organization"
    echo
    "$ROOT/scripts/addNewOrg.sh"
elif [ "$MODE" == "newOrgServer" ]; then
    Number=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_ORG" | wc -l)
    if [[ "${Number}" -lt 1 ]]; then
        sed -i "/export NUM_CHANNELS='${NUM_CHANNELS}'/a export NEW_ORG=()" globalParams.sh
    fi
    echo
    echo "Creating new organization"
    echo
    "$ROOT/scripts/addNewOrgServer.sh"
elif [ "$MODE" == "singleJoin" ]; then
    echo
    echo ""
    echo
    "$ROOT/scripts/singleJoin.sh"
else
    printHelp
    exit 1
fi
set +e
