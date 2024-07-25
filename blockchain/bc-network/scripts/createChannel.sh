#!/bin/bash

CHANNEL_INDEX="$1"

export CORE_PEER_TLS_ENABLED=true
CLIENT_CA_relpath='tls/ca.crt'

source "$ROOT/globalParams.sh"

exportChannel"$CHANNEL_INDEX"Params

# Set environment variables for the client org
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

  # CONFIG_PARAMS=$(listConfigParams 'client' "$ORG")
  # source "$CONFIG_PARAMS"
  # exportGlobalParams
  # exportOrgParams

  exportNode"$NODE_INDEX"Params
  export CORE_PEER_TLS_ROOTCERT_FILE="$NODE_PATH/$CLIENT_CA_relpath"
  export CORE_PEER_ADDRESS="$NODE_HOST:$NODE_PORT"
  export CORE_PEER_LOCALMSPID="$MSP_NAME"
  export CORE_PEER_MSPCONFIGPATH="$BASE_DIR/users/Admin@$ORG_NAME/msp"
  export FABRIC_LOGGING_SPEC="${FABRIC_LOGS[$LOG_LEVEL]}"

  [ $LOG_LEVEL -ge 4 ] && env | grep CORE
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    echo $'\e[1;31m'!!!!!!!!!!!!!!! $2 !!!!!!!!!!!!!!!!$'\e[0m'
    echo
    exit 1
  fi
}

if [ ! -d "channel-artifacts" ]; then
  mkdir channel-artifacts
fi

createChannelTx() {

  [ $LOG_LEVEL -ge 5 ] && set -x
  configtxgen -profile "$CHANNEL_PROFILE" -outputCreateChannelTx "$ROOT/channel-artifacts/$CHANNEL_NAME.tx" \
    -channelID "$CHANNEL_NAME" -configPath "$ROOT/configtx/" &>log.txt
  res=$?
  [ $LOG_LEVEL -ge 5 ] && set +x
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  if [ $res -ne 0 ]; then
    echo "Failed to generate channel configuration transaction..."
    exit 1
  fi
  echo

}

createAnchorPeerTx() {
  setGlobals
  [ $LOG_LEVEL -ge 3 ] && echo "#######    Generating anchor peer update transaction for $MSP_NAME  ##########"
  [ $LOG_LEVEL -ge 5 ] && set -x
  configtxgen -profile "$CHANNEL_PROFILE" -outputAnchorPeersUpdate "$ROOT/channel-artifacts/${MSP_NAME}anchors.tx" \
    -channelID "$CHANNEL_NAME" -asOrg "$MSP_NAME" -configPath "$ROOT/configtx/" &>log.txt
  res=$?
  [ $LOG_LEVEL -ge 5 ] && set +x
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  if [ $res -ne 0 ]; then
    echo "Failed to generate anchor peer update transaction for $MSP_NAME..."
    exit 1
  fi
  echo
}

createChannel() {
  setGlobals
  # Poll in case the raft leader is not set yet
  local rc=1
  local COUNTER=0
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $CLI_DELAY
    [ $LOG_LEVEL -ge 5 ] && set -x
    peer channel create -o "$ORDERER_HOST:$ORDERER_PORT" -c "$CHANNEL_NAME" --ordererTLSHostnameOverride "$CHANNEL_ORDERER" \
      -f "$ROOT/channel-artifacts/$CHANNEL_NAME.tx" --outputBlock "$ROOT/channel-artifacts/$CHANNEL_NAME.block" --tls --cafile "$ORDERER_CA" &>log.txt
    rc=$?
    [ $LOG_LEVEL -ge 5 ] && set +x
    ((COUNTER++))
  done
  cat log.txt
  verifyResult $rc "Channel creation failed"
  echo
  echo "Channel '$CHANNEL_NAME' created"
  echo
}

# queryCommitted ORG
joinChannel() {
  ORG="$1"
  NODE="$2"
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
  echo
  verifyResult $rc "After $MAX_RETRY attempts, $NODE.$ORG has failed to join channel '$CHANNEL_NAME' "
  echo "Creating CONFIG BLOCK"
  echo "Creating CONFIG BLOCK"
  peer channel fetch config config_block.pb -o "$ORDERER_HOST:$ORDERER_PORT" -c $CHANNEL_NAME --tls --cafile $ORDERER_CA
  echo "Creating CONFIG BLOCK"
  echo "Creating CONFIG BLOCK"

}

updateAnchorPeers() {
  ORG="$1"
  NODE="$2"
  setGlobals "$ORG" "$NODE"
  local rc=1
  local COUNTER=0
  ## Sometimes Join takes time, hence retry
  while [ $rc -ne 0 -a $COUNTER -lt $MAX_RETRY ]; do
    sleep $CLI_DELAY
    [ $LOG_LEVEL -ge 4 ] && set -x
    peer channel update -o "$ORDERER_HOST:$ORDERER_PORT" --ordererTLSHostnameOverride "$CHANNEL_ORDERER" -c "$CHANNEL_NAME" \
      -f "$ROOT/channel-artifacts/${CORE_PEER_LOCALMSPID}anchors.tx" --tls --cafile "$ORDERER_CA" >&log.txt
    rc=$?
    set +x
    ((COUNTER++))
  done
  cat log.txt
  verifyResult $rc "Anchor peer update failed"
  [ $LOG_LEVEL -ge 3 ] && echo "===================== Anchor peers updated for org '$CORE_PEER_LOCALMSPID' on channel '$CHANNEL_NAME' ===================== "
  sleep $CLI_DELAY
  echo
}

verifyResult() {
  if [ $1 -ne 0 ]; then
    echo "!!!!!!!!!!!!!!! "$2" !!!!!!!!!!!!!!!!"
    echo
    exit 1
  fi
}

export FABRIC_CFG_PATH="$ROOT/configtx"

## Create channeltx
echo
echo "Generate channel create transaction $CHANNEL_NAME.tx"
echo
createChannelTx

## DEPRECATED, need to handle it with configtxlator, TODO for next release!
## Create anchorpeertx, only if the channel creator organization has at least one anchor peer
# for ((I = 1; I <= "$NUM_ANCHORS"; I++)); do
#   ORG='CHANNEL_ANCHOR'"$I"'_ORG'
#   ORG="${!ORG}"
#   if [ "$ORG" == "$CHANNEL_CREATOR" ]; then
#     [ $LOG_LEVEL -ge 3 ] && echo "### Generating anchor peer update transactions ###"
#     createAnchorPeerTx
#     break
#   fi
# done

export FABRIC_CFG_PATH="$ROOT/../config/"

## Create channel
echo "Create channel "$CHANNEL_NAME
echo
createChannel

for orgs in "${!CHANNEL_ORGS[@]}"; do
  ORG=${CHANNEL_ORGS[orgs]}
  cmd='CHANNEL_ORG'"$orgs"'_NODES[*]'

  nodeArray="${!cmd}"
  nodeArray=($nodeArray)
  for node in "${!nodeArray[@]}"; do

    NODE=${nodeArray[node]}

    [ $LOG_LEVEL -ge 3 ] && echo "Join $NODE.$ORG to $CHANNEL_NAME..."
    [ $LOG_LEVEL -ge 3 ] && echo
    joinChannel "$ORG" "$NODE"
  done

done

## DEPRECATED, need to handle it with configtxlator, TODO for next release!
## Set the anchor peers for each org in the channel
# for ((I = 1; I <= "$NUM_ANCHORS"; I++)); do
#   NODE='CHANNEL_ANCHOR'"$I"'_NODE'
#   NODE="${!NODE}"
#   ORG='CHANNEL_ANCHOR'"$I"'_ORG'
#   ORG="${!ORG}"
#   [ $LOG_LEVEL -ge 3 ] && echo "Update anchor peer $NODE.$ORG to $CHANNEL_NAME..."
#   updateAnchorPeers "$ORG" "$NODE"
# done

echo "Channel joining complete"
