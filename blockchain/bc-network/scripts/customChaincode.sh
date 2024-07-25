#!/bin/bash

# Set environment variables for the client org
CLIENT_CA_relpath='tls/ca.crt'
ROOT="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"
PATH="$ROOT/../bin":$PATH

source "$ROOT/globalParams.sh"
source "$ROOT/customChaincodeParams.sh"
# exportChannel1Params

setGlobals() {
  if [ "$#" -eq 2 ]; then
    local ORG="$1"
    local NODE="$2"

    CONFIG_PARAMS=$(listConfigParams 'client' "$ORG")
    source "$CONFIG_PARAMS"

    exportGlobalParams
    exportOrgParams
    local NODE_INDEX="$(getNodeIndex $NODE)"
  else
    echo "expected usage: setGlobals ORG_NAME NODE_NAME"
    exit 1
  fi
  [ $LOG_LEVEL -ge 5 ] && echo "Export global params for $NODE.$ORG"

  exportNode"$NODE_INDEX"Params
  export CORE_PEER_TLS_ROOTCERT_FILE="$NODE_PATH/$CLIENT_CA_relpath"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_ADDRESS="$NODE_HOST:$NODE_PORT"
  export CORE_PEER_LOCALMSPID="$MSP_NAME"
  export CORE_PEER_MSPCONFIGPATH="$BASE_DIR/users/Admin@$ORG_NAME/msp"
  export FABRIC_LOGGING_SPEC="${FABRIC_LOGS[$LOG_LEVEL]}"
  export FABRIC_CFG_PATH="$ROOT/../config/"
  [ $LOG_LEVEL -ge 5 ] && env | grep CORE
}

packageChaincode() {
  # this could be done by a single orgainization if they are able/willing to share the generated package
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer chaincode package"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 4 ] && set -x
  if [ ! -f "$CC_PKG_NAME" ]; then
    peer lifecycle chaincode package "$CC_PKG_NAME" --path "$CC_SRC_PATH" --lang "$CC_LANG" \
      --label "$CC_LABEL"
  fi
  if [ $? != 0 ]; then
    echo "chaincode packaging failed"
    cat log.txt
    exit 1
  fi

  if [ -d "$CC_SRC_PATH/node_modules" ]; then
    # Create a temporary working directory
    WORKDIR=$(mktemp -d)
    echo "Using temporary directory $WORKDIR for repackaging"

    # Unpack the original chaincode package
    tar -xzf "$CC_PKG_NAME" -C "$WORKDIR"

    # Navigate into the working directory
    cd "$WORKDIR"

    # The chaincode package contains a code.tar.gz, unpack this next
    tar -xzf code.tar.gz

    # Copy the node_modules directory from the chaincode source directory to the src folder
    cp -r "$CC_SRC_PATH/node_modules" src/

    # Repackage the src directory into code.tar.gz. Make sure you're still in the WORKDIR directory
    tar -czf code.tar.gz src/

    # Now, repackage everything including the modified code.tar.gz and the original metadata.json into a new chaincode package
    tar -czf "$CC_PKG_NAME" code.tar.gz metadata.json

    # Clean up: Go back to the original directory and remove the temporary working directory
    cd "$ROOT"
    rm -rf "$WORKDIR"

    echo "Chaincode package $CC_PKG_NAME has been repackaged with node_modules included."
  else
    echo "The node_modules directory does not exist in $CC_SRC_PATH. Please ensure that npm install has been run in the chaincode source directory."
  fi

  [ $LOG_LEVEL -ge 4 ] && set +x
}

# takes orgName nodeName as inputs, correct value for CC_PKG_NAME must be defined beforehand
installChaincode() {
  local _ORG="$1"
  local _NODE="$2"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer lifecycle chaincode install on $_NODE.$_ORG"
  [ $LOG_LEVEL -ge 3 ] && echo

  # echo "installChaincode - setGlobals"
  setGlobals "$_ORG" "$_NODE"

  # add $NODE_HOST:$NODE_PORT to ARRAY_NODE_ADDRESSES
  ARRAY_NODE_ADDRESSES+=("$CORE_PEER_ADDRESS")
  # add CORE_PEER_TLS_ROOTCERT_FILE to ARRAY_TLS_ROOTCERTS
  ARRAY_TLS_ROOTCERTS+=("$CORE_PEER_TLS_ROOTCERT_FILE")

  [ $LOG_LEVEL -ge 4 ] && set -x
  if [ -f "$CC_PKG_NAME" ]; then
    peer lifecycle chaincode install "$CC_PKG_NAME"
    if [ $? != 0 ]; then
      echo "chaincode installation failed"
      cat log.txt
      exit 1
    fi
  else
    echo "ERROR: chaincode package not found"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && set +x
}

approveChaincode() {
  echo "CC_SEQUENCE = $CC_SEQUENCE"
  set -x
  peer lifecycle chaincode approveformyorg --orderer "$ORDERER_HOST:$ORDERER_PORT" --tls --cafile "$ORDERER_CA" \
    --sequence "$CC_SEQUENCE" --channelID "$CHANNEL_NAME" --name "$CC_NAME" --version "$CC_VERSION" \
    --package-id "$PACKAGE_ID" $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &>log.txt
  if [ $? != 0 ]; then
    echo "chaincode org approval failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  set +x
  cat log.txt
}

checkCommitReadiness() {
  echo "CC_SEQUENCE = $CC_SEQUENCE"
  echo
  echo "peer lifecycle chaincode checkcommitreadiness"
  echo
  peer lifecycle chaincode checkcommitreadiness --orderer "$ORDERER_HOST:$ORDERER_PORT" --channelID "$CHANNEL_NAME" --tls \
    --cafile "$ORDERER_CA" --name "$CC_NAME" --version "$CC_VERSION" --sequence "$CC_SEQUENCE" \
    $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &>log.txt
  if [ $? != 0 ]; then
    echo "chaincode check commit readiness failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

commitChaincode() {
  echo "CC_SEQUENCE = $CC_SEQUENCE"
  # shenanigans to handle commit command properly for MAJORITY endorsement
  # TO DO: check whether this is actually needed
  COMMIT_CMD="peer lifecycle chaincode commit --orderer $ORDERER_HOST:$ORDERER_PORT --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQUENCE --cafile '$ORDERER_CA' --tls"
  for x in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    COMMIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[x]}"
  done
  for y in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    COMMIT_CMD+=" --tlsRootCertFiles '${ARRAY_TLS_ROOTCERTS[y]}'"
  done
  if [ "$INIT_REQUIRED" == 'true' ]; then
    COMMIT_CMD+=" --init-required"
  fi

  echo
  echo "peer lifecycle chaincode commit"
  echo

  [ $LOG_LEVEL -ge 4 ] && echo "$COMMIT_CMD"
  eval "$COMMIT_CMD"
  if [ $? != 0 ]; then
    echo "chaincode commit failed"
    exit 1
  fi
}

initChaincode() {
  # shenanigans to handle init command properly for MAJORITY endorsement
  # TO DO: check whether this is actually needed
  INIT_CMD="peer chaincode invoke --orderer $ORDERER_HOST:$ORDERER_PORT --tls --cafile '$ORDERER_CA' -C $CHANNEL_NAME --name $CC_NAME --isInit"
  for i in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    INIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[i]}"
  done
  for i in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    INIT_CMD+=" --tlsRootCertFiles '${ARRAY_TLS_ROOTCERTS[i]}'"
  done
  if [ "$INIT_REQUIRED" == 'true' ]; then
    INIT_CMD+=" -c '{"\""function"\"":"\"""
    INIT_CMD+=$INIT_FUNCTION_NAME
    INIT_CMD+=""\"","\""Args"\"":[]}'"
  fi

  echo
  echo "chaincode initialization"
  echo

  [ $LOG_LEVEL -ge 4 ] && echo "$INIT_CMD"
  eval "$INIT_CMD"
  if [ $? != 0 ]; then
    echo "chaincode initialization failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
  cat log.txt
}

# chaincode deploy operations are briefly described in:
# https://medium.com/geekculture/how-to-deploy-chaincode-smart-contract-45c20650786a
deployCC() {

  # get chaincodeParams
  exportChaincode1Params

  # construct cc label from chaincodeParams
  CC_LABEL="$CC_NAME-$CC_VERSION"

  # loop channels to install cc on every peer
  # TO DO: have array in chaincodeParams with all channels where CC needs to be deployed
  # OR get channel as input and handle each channel separately

  exportNetworkParams

  DELETE=(${CHANNEL_DEPLOYED[@]})

  for del in ${DELETE[@]}; do
    CHANNEL_LIST=("${CHANNEL_LIST[@]/$del/}") #Quotes when working with strings
  done

  local CHANNEL_LIST_STRING="${CHANNEL_LIST[*]}"
  readChannelName
  exportChannel"$i"Params

  local DEPLOYING="$CHOSEN_CHANNEL"

  sed -i "/^CHANNEL_DEPLOYED=/ s/$/ $CHOSEN_CHANNEL) \n}/" customChaincodeParams.sh

  # for i in "${!CHANNEL_LIST[@]}"; do
  DELETE+=("$CHOSEN_CHANNEL")

  # done
  # (re)instantiate helper arrays
  ARRAY_NODE_ADDRESSES=()
  ARRAY_TLS_ROOTCERTS=()

  # shenanigans to get right export name for this channel
  # local CHANNEL_NAME="${CHANNEL_LIST[i]}"
  # local GREP_ARGS="CHANNEL_NAME='$CHOSEN_CHANNEL'"
  # local LINE_NUM=$(grep -n "$GREP_ARGS" $ROOT/globalParams.sh)
  # local LINE_NUM=$(cut -d ":" -f1 <<<$LINE_NUM)
  # local LINE_NUM=$(($LINE_NUM - 1))
  # local EXPORT_CMD=$(sed "${LINE_NUM}q;d" $ROOT/globalParams.sh)
  # local EXPORT_CMD=$(cut -d " " -f1 <<<$EXPORT_CMD)
  # eval "$EXPORT_CMD"

  # loop channel orgs and install cc on relevant peers
  for org in "${!CHANNEL_ORGS[@]}"; do

    ORG="${CHANNEL_ORGS[org]}"

    # we need this for chaincode package
    export FABRIC_CFG_PATH="$ROOT/../config/"

    # steps for lifecycle: package, install, approve, commit
    # do package only once per org
    # cd ../bin

    packageChaincode

    cmd='CHANNEL_ORG'"$org"'_NODES[*]'
    nodeArray="${!cmd}"
    nodeArray=($nodeArray)

    ## loop through all org peers for installation
    for node in "${!nodeArray[@]}"; do

      NODE="${nodeArray[node]}"
      # TO DO: check whether CC needs to be installed on this peer
      installChaincode "$ORG" "$NODE"

      # Check installation and get package ID
      for cc in $(peer lifecycle chaincode queryinstalled --output json | jq -c '.installed_chaincodes[]'); do
        if [ $(echo "$cc" | jq '.label' | tr -d '"') == "$CC_LABEL" ]; then
          PACKAGE_ID=$(echo "$cc" | jq '.package_id' | tr -d '"')
          break
        fi
      done
    done

    # remove CC package
    rm "$CC_PKG_NAME"

    # approve CC for this ORG
    approveChaincode

    # If last org we can wrap up
    if [ $((org + 1)) -eq "${#CHANNEL_ORGS[@]}" ]; then
      # check commit readiness
      checkCommitReadiness
      # commit
      commitChaincode
      # initialize if needed
      # if [ "$INIT_REQUIRED" == 'true' ]; then

      initChaincode
      # fi
    fi
  done

  # done
}

readChannelName() {

  echo
  echo "Choose on which channel to ${MODE} the $CC_NAME chaincode"
  echo
  echo "Available choices: ${NETWORK_CHANNELS[*]} "
  echo
  read -p "Enter channel name: " CH_NAME
  echo

  for channel in "${!NETWORK_CHANNELS[@]}"; do
    if [[ ${NETWORK_CHANNELS[channel]} == *"$CH_NAME"* ]]; then
      export i=$((channel + 1))
      export CHOSEN_CHANNEL="$CH_NAME"
    fi
  done
}

readPeerName() {

  TOTAL_NODE_ARRAY=""
  for orgInedx in "${!CHANNEL_ORGS[@]}"; do
    cmd='CHANNEL_ORG'"$orgInedx"'_NODES[*]'
    nodeArray="${!cmd}"
    TOTAL_NODE_ARRAY+=" "
    TOTAL_NODE_ARRAY+="$nodeArray"
  done

  TOTAL_NODE_ARRAY=($TOTAL_NODE_ARRAY)

  PEER_LIST_STRING="${TOTAL_NODE_ARRAY[*]}"

  echo
  echo "Choose on which peer to invoke the $CC_NAME chaincode"
  echo
  echo "Available choices: $PEER_LIST_STRING"
  echo
  read -p "Enter peer name: " PEER_NAME
  if [[ ! $PEER_LIST_STRING == *"$PEER_NAME"* ]]; then
    echo "Peer name invalid, please provide a valid name"
    echo
    readPeerName
  fi
  NODE="$PEER_NAME"
  exportChaincode${CC_INDEX}Params
  PEER_LIST_ARRAY=($PEER_LIST_STRING)

  for orgInedx in "${!CHANNEL_ORGS[@]}"; do
    cmd='CHANNEL_ORG'"$orgInedx"'_NODES[*]'
    nodeArray="${!cmd}"
    nodeArray=($nodeArray)
    if [[ " ${nodeArray[*]} " == *" ${PEER_NAME} "* ]]; then
      ORG=${CHANNEL_ORGS[orgInedx]}
    fi
  done
}

readEndorsers() {
  # get channel index

  TOTAL_NODE_ARRAY=""
  for orgInedx in "${!CHANNEL_ORGS[@]}"; do
    cmd='CHANNEL_ORG'"$orgInedx"'_NODES[*]'
    nodeArray="${!cmd}"
    TOTAL_NODE_ARRAY+=" "
    TOTAL_NODE_ARRAY+="$nodeArray"
  done

  TOTAL_NODE_ARRAY=($TOTAL_NODE_ARRAY)

  ENDORSERS_LIST_STRING="${TOTAL_NODE_ARRAY[*]}"

  echo
  echo "Choose which additional peers should endorse the transaction (by default the peer that invokes it already endorses it)"
  echo
  echo "Available choices: $ENDORSERS_LIST_STRING"
  echo
  read -p "Enter endorser(s) name(s), separated by a space: " ENDORSERS

  ENDORSERS=($ENDORSERS)
  if [ -n "${ENDORSERS[*]}" ]; then
    for endorserInedx in "${!ENDORSERS[@]}"; do
      for orgInedx in "${!CHANNEL_ORGS[@]}"; do
        cmd='CHANNEL_ORG'"$orgInedx"'_NODES[*]'
        nodeArray="${!cmd}"
        nodeArray=($nodeArray)
        if [[ " ${nodeArray[*]} " == *" ${ENDORSERS[endorserInedx]} "* ]]; then
          ENDORSER_ORG=${CHANNEL_ORGS[orgInedx]}
          ENDORSER_NODE=${ENDORSERS[endorserInedx]}
        fi
      done
    done

    setGlobals "$ENDORSER_ORG" "$ENDORSER_NODE"
    ENDORSERS_ADDRESSES+=" --peerAddresses $CORE_PEER_ADDRESS"
    ENDORSERS_CA_CERTS+=" --tlsRootCertFiles '$CORE_PEER_TLS_ROOTCERT_FILE'"
  fi
}

readFunctionName() {
  echo
  echo "Choose which function to invoke for the $CC_NAME chaincode"
  echo
  read -p "Enter function name: " FUNCTION_NAME
  echo
  echo "Entered function name: $FUNCTION_NAME"
  echo
  read -p "Confirm function name? Enter y to confirm " CONFIRMATION
  if [[ ! $CONFIRMATION == "y" ]]; then
    echo
    echo "Function name unconfirmed, enter again"
    readFunctionName
  fi
}

readArguments() {
  echo
  echo "Choose the arguments to provide for the selected $FUNCTION_NAME function"
  echo
  read -p "Enter all of the function's arguments, separated by a space: " ARGUMENTS
  IFS=' ' read -r -a ARGS_ARRAY <<<"$ARGUMENTS"
  echo
  echo "Entered arguments: ${ARGS_ARRAY[*]}"
  echo
  read -p "Confirm arguments? Enter y to confirm " CONFIRMATION
  if [[ ! $CONFIRMATION == "y" ]]; then
    echo
    echo "Arguments unconfirmed, enter again"
    readArguments
  fi
}

interactCC() {
  source "$ROOT/customChaincodeParams.sh"
  exportChaincode${CC_INDEX}Params
  local CHANNEL_LIST_STRING="${CHANNEL_LIST[*]}"
  readChannelName
  exportChannel"$i"Params
  # shenanigans to get right export name for this channel
  # local GREP_ARGS="CHANNEL_NAME='$CHANNEL_NAME'"
  # local LINE_NUM=$(grep -n "$GREP_ARGS" $ROOT/globalParams.sh)
  # local LINE_NUM=$(cut -d ":" -f1 <<<$LINE_NUM)
  # local LINE_NUM=$(($LINE_NUM - 1))
  # local EXPORT_CMD=$(sed "${LINE_NUM}q;d" $ROOT/globalParams.sh)
  # local EXPORT_CMD=$(cut -d " " -f1 <<<$EXPORT_CMD)
  # eval "$EXPORT_CMD"
  readPeerName
  if [[ ! $MODE == "query" ]]; then
    readEndorsers
  fi

  # echo "interactCC - setGlobals"
  # echo "ORG = $ORG"
  setGlobals "$ORG" "$NODE"

  if [ -n "$ENDORSERS_ADDRESSES" ]; then
    ENDORSERS_ADDRESSES+=" --peerAddresses $CORE_PEER_ADDRESS"
    ENDORSERS_CA_CERTS+=" --tlsRootCertFiles '$CORE_PEER_TLS_ROOTCERT_FILE'"
  fi
  readFunctionName
  readArguments
  # Form -c properly
  local INVOKE_CMD='{"Args":['
  for a in "${!ARGS_ARRAY[@]}"; do
    INVOKE_CMD+='"'
    local TEMP_STR="${ARGS_ARRAY[a]}"
    INVOKE_CMD+=$TEMP_STR
    INVOKE_CMD+='"'
    if [ ! $((a + 1)) -eq "${#ARGS_ARRAY[@]}" ]; then
      INVOKE_CMD+=','
    fi
  done
  INVOKE_CMD+='],"Function":"'
  INVOKE_CMD+=$FUNCTION_NAME
  INVOKE_CMD+='"}'
  # fire invoke/query
  local CMD="peer chaincode $MODE --orderer $ORDERER_HOST:$ORDERER_PORT --tls --cafile '$ORDERER_CA' -C $CHANNEL_NAME --name $CC_NAME -c '$INVOKE_CMD'"
  if [ -n "$ENDORSERS_ADDRESSES" ]; then
    CMD+="$ENDORSERS_ADDRESSES"
    CMD+="$ENDORSERS_CA_CERTS"
  fi
  [ $LOG_LEVEL -ge 3 ] && echo "$CMD"
  eval "$CMD"
  if [ $? != 0 ]; then
    echo "chaincode $MODE failed for function '$FUNCTION_NAME' with args '${ARGS_ARRAY[*]}'"
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}