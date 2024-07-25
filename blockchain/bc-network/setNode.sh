#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#

# This script brings up a Hyperledger Fabric setNode for testing smart contracts
# and applications. The test setNode consists of two organizations with one
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
export global AVIABLE_CHOICES_ORGS=()
export global AVIABLE_CHOICES_TYPES=()
export global AVIABLE_CHOICES_PEERS=()
source "$ROOT/globalParams.sh"
exportNetworkParams

function printHelp() {
  echo "Usage: ./setNode.sh [OPTS] MODE"
  echo "MODE:"
  echo "    up      executes the whole Node from a clean start, including channels"
  echo "    down    tears down the Node as configured"
  echo "OPTS (global defaults are defined in globalParams.sh:"
  echo "  -d <n>    retry failed commands every n seconds"
  echo "  -h        print this help message"
  echo "  -l <n>    set verbosity: 1->error,2->warning,3->info,4->debug,5->trace"
  echo "  -r <n>    retry failed commands n times before giving up"
  echo "  -v        verbose output: same as -l 4"
  echo
}
matchip () {
 
  PUBLIC_IP=$(dig +short myip.opendns.com @resolver1.opendns.com)
  ip4=$(/sbin/ip -o -4 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
  ip6=$(/sbin/ip -o -6 addr list eth0 | awk '{print $4}' | cut -d/ -f1)
  local all='false'
  if [ "$#" -eq 2 ]; then
    local type="$1"
    local name="$2"
    echo "$ROOT/organizations/$type/$name/configParams.sh"
  elif [ "$#" -eq 1 ]; then
    # list all organizations of the given type if no name is specified
    local type="$1"
    for org in $(ls "$ROOT/organizations/$type"); do
      # echo "$ROOT/organizations/$type/$org/configParams.sh"
      source "$ROOT/organizations/$type/$org/configParams.sh"
      exportNode1Params
      echo $PUBLIC_IP
      echo $NODE_HOST
      if [ "$NODE_HOST" = "$PUBLIC_IP" ]; then
      echo "ip are equal"
        AVIABLE_CHOICES_PEERS+=("$NODE_NAME")
        AVIABLE_CHOICES_ORGS+=("$org")
        AVIABLE_CHOICES_TYPES+=("$type")
            #  echo "${AVIABLE_CHOICES_PEERS[*]}"
            #  echo "${AVIABLE_CHOICES_ORGS[*]}"
            #  echo "${AVIABLE_CHOICES_TYPES[*]}"
      else 
      echo "ip are not equal"
      fi
    done
  elif [ "$#" -eq 0 ]; then
    # list all organizations if none is specified
    for type in 'client' 'order'; do
      matchip $type
    done
  else
    echo "expected usage: listConfigParams [ <client|order> [ORG_NAME] ]"
    exit 1
  fi
}
readAvailableChoice () {
  
  echo 
  echo
  echo 
  echo "AVAILABLE CHOICES:"
  echo 
    for i in "${!AVIABLE_CHOICES_PEERS[@]}"; do
  echo 
  echo "TYPE: ${AVIABLE_CHOICES_TYPES[i]} ORG: ${AVIABLE_CHOICES_ORGS[i]} NODE: ${AVIABLE_CHOICES_PEERS[i]} "
  echo
 
  done

  read -p "Enter TYPE name: " SELECTED_TYPE
  read -p "Enter ORG name: " SELECTED_ORG
  read -p "Enter NODE name: " SELECTED_NODE

  echo $SELECTED_NODE
  echo $SELECTED_ORG
  echo $SELECTED_TYPE

}
function setGlobals() {
  if [ "$#" -eq 2 ]
  then
    local ORG="$1"
  elif [ "$#" -eq 0 ]
  then
    local ORG="$CHANNEL_CREATOR"
  fi
  CONFIG_PARAMS=$(listConfigParams 'client' "$ORG")
  source "$CONFIG_PARAMS"
  exportGlobalParams
  exportOrgParams
  if [ "$#" -eq 2 ]
  then
    local ORG="$1"
    local NODE="$2"
    local NODE_INDEX="$(getNodeIndex $NODE)"
  elif [ "$#" -eq 0 ]
  then
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


function setNode (){
 local type="$1"
 local name="$2"

source "$ROOT/organizations/$type/$name/configParams.sh"
    exportGlobalParams

    exportOrgParams 

 "$ORG_UP_SCRIPT"
#  "$ORG_SETUP_SCRIPT"
}


function joinChannel() {
  ORG="$1"
  NODE="$2"
  setGlobals "$ORG" "$NODE"
	local rc=1
	local COUNTER=0
	## Sometimes Join takes time, hence retry
	while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ] ; do
    sleep $CLI_DELAY
    [ $LOG_LEVEL -ge 4 ] && set -x
    peer channel join -b "$ROOT/channel-artifacts/$CHANNEL_NAME.block" >&log.txt
    rc=$?
    [ $LOG_LEVEL -ge 4 ] && set +x
    ((COUNTER++))
	done
	cat log.txt
	echo
	verifyResult $rc "After $MAX_RETRY attempts, $NODE.$ORG has failed to join channel '$CHANNEL_NAME' "
}
verifyResult() {
  if [ $1 -ne 0 ]; then
    echo $'\e[1;31m'!!!!!!!!!!!!!!! $2 !!!!!!!!!!!!!!!!$'\e[0m'
    echo
    exit 1
  fi
}
function singleJoin() {
  local ORG="$1"
  local NODE="$2"

export FABRIC_CFG_PATH="$ROOT/../config/"
export CORE_PEER_TLS_ENABLED=true
export CLIENT_CA_relpath='tls/ca.crt'
export global CHANNEL_INDEX="1"
export CHANNEL_NAME="channel1"
  [ $LOG_LEVEL -ge 3 ] && echo "Join $NODE.$ORG to $CHANNEL_NAME..."
  [ $LOG_LEVEL -ge 3 ] && echo
  joinChannel "$ORG" "$NODE"

}

function up {
  [ $LOG_LEVEL -ge 2 ] && echo
  [ $LOG_LEVEL -ge 4 ] && echo '=================== LAUNCH NODE ======================'

if [ ! -d "/$ROOT/channel-artifacts" ]; then
echo
echo
echo "ERR: Directory /$ROOT/channel-artifacts DOES NOT exists. "
echo
echo
exit 1
else 
echo
echo
echo 'Loading Channel artifacts'
echo
echo
fi
matchip
readAvailableChoice
setNode "$SELECTED_TYPE" "$SELECTED_ORG"
singleJoin "$SELECTED_ORG" "$SELECTED_NODE"

  [ $LOG_LEVEL -ge 4 ] && echo '============ NODE LAUNCHED SUCCESSFULLY =============='
}
# Parse commandline args

## Parse mode
if [[ $# -lt 1 ]] ; then
  printHelp
  exit 0
fi
function nodeDown () {
  ORG="$1"
  NODE="$2"
docker stop $NODE.$ORG
docker rm $NODE.$ORG
}
function createChannels() {

  for ((I = 1; I <= "$NUM_CHANNELS"; I++))
  do
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
function createGenesisBlock() {
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "Generate Orderer Genesis block"
  [ $LOG_LEVEL -ge 3 ] && echo
  # skip genesis block creation if it already exists
  if [ -f "$ROOT/system-genesis-block/genesis.block" ]
  then
    [ $LOG_LEVEL -ge 2 ] && echo "genesis block already exists, skipping creation..."
    return
  fi
  # Note: For some unknown reason (at least for now) the block file can't be
  # named orderer.genesis.block or the orderer will fail to launch!
  [ $LOG_LEVEL -ge 5 ] && set -x
  configtxgen -profile "$GENESIS_PROFILE" -channelID 'syschannel'\
    -outputBlock "$ROOT/system-genesis-block/genesis.block"\
    -configPath "$ROOT/configtx/" &> log.txt
  res=$?
  [ $LOG_LEVEL -ge 5 ] && set +x
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  if [ $res -ne 0 ]; then
    echo $'\e[1;32m'"Failed to generate orderer genesis block..."$'\e[0m'
    exit 1
  fi
}
function checkOrLaunchSetup () {
  # retrieve the 'configParams.sh' script for every node and export its global variables
  IFS=$'\n'
  for PARAMS_FILE in $(listConfigParams)
  do
    source "$PARAMS_FILE"
    exportGlobalParams
    # check whether the setup was already executed
    # TODO: find a better way to tell whether the setup is complete or not
    if [ ! -r "$BASE_DIR/ca-server/tls-cert.pem" ]
    then
      exportOrgParams
      # if [ ! -x "$ORG_SETUP_SCRIPT" ]
      # then
      #   echo "$ORG_SETUP_SCRIPT not executable"
      #   exit 1
      # fi
      # execute the setup script
      "$ORG_SETUP_SCRIPT"
      STATUS=$?
      if [ ! $STATUS -eq 0 ];
        then
        [ $LOG_LEVEL -ge 2 ] && echo "setup script failed with exit status $STATUS: $ORG_SETUP_SCRIPT"
        exit 1
      fi
    fi
  done
}
  



function adminup {

 checkOrLaunchSetup && createGenesisBlock && orderUp && clientUp && createChannels


}

function orderUp {
matchip order
readAvailableChoice
setNode "$SELECTED_TYPE" "$SELECTED_ORG"

}
function clientUp {
matchip client
readAvailableChoice
setNode "$SELECTED_TYPE" "$SELECTED_ORG"

}
# parse input flags
while [[ $# -ge 1 ]] ; do
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
  up|down|admin)
    MODE="$1"
    break
    ;;
  * )
    echo
    echo "Unknown flag: $key"
    echo
    printHelp
    exit 1
    ;;
  esac
  shift
done

if [ "$MODE" == "up" ]; then
  echo
  echo "Launch the node and join of channels"

up
elif [ "$MODE" == "down" ]; then
  echo
  echo "=================== STOPPING NODE ======================"
  echo
  nodeDown "Client" "peer1" 
  echo
  echo "=================== NODE STOPPED SUCCESSFULLY ======================"
  echo
elif [ "$MODE" == "admin" ]; then
  echo
  echo "Starting network"
  echo
  adminup
else
  printHelp
  exit 1
fi
set +e