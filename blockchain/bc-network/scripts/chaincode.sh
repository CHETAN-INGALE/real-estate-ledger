#!/bin/bash

CLIENT_CA_relpath='tls/ca.crt'
ROOT="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"
PATH="$ROOT/../bin":$PATH

source "$ROOT/globalParams.sh"
source "$ROOT/chaincodeParams.sh"

printHelp() {
  echo "This script manages the test chaincode for end to end testing of the new network"
  echo
  echo "Usage: chaincode.sh [OPTS] MODE [PARAMS]"
  echo "MODE:"
  echo "  e2e       deploy test chaincode and perform end to end test on a channel"
  echo "  -l <n>    set verbosity: 1->error,2->warning,3->info,4->debug,5->trace"
  echo "  -v        verbose output: same as -l 4"
  echo
}

# Set environment variables for the client org
setGlobals() {
  if [ "$#" -eq 2 ]
  then
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
  [ $LOG_LEVEL -ge 3 ] && echo "Export global params for $NODE.$ORG"
  exportNode"$NODE_INDEX"Params
  export CORE_PEER_TLS_ROOTCERT_FILE="$NODE_PATH/$CLIENT_CA_relpath"
  export CORE_PEER_TLS_ENABLED=true
  export CORE_PEER_ADDRESS="$NODE_HOST:$NODE_PORT"
  export CORE_PEER_LOCALMSPID="$MSP_NAME"
  export CORE_PEER_MSPCONFIGPATH="$BASE_DIR/users/Admin@$ORG_NAME/msp"
  export FABRIC_LOGGING_SPEC="${FABRIC_LOGS[$LOG_LEVEL]}"
  export FABRIC_CFG_PATH="$ROOT/../config/"
  [ $LOG_LEVEL -ge 4 ] && env | grep CORE
}

packageChaincode() {
  # this could be done by a single orgainization if they are able/willing to share the generated package
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer chaincode package"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 4 ] && set -x
  if [ ! -f "$CC_PKG_NAME" ]; then
    peer lifecycle chaincode package "$CC_PKG_NAME" --path "$CC_SRC_PATH" --lang "$CC_LANG"\
    --label "$CC_LABEL"
  fi
  if [ $? != 0 ]; then
    echo "chaincode packaging failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && set +x
}

# takes orgName nodeName as inputs, correct value for CC_PKG_NAME must be defined beforehand
installChaincode() {
  local _ORG="$1"
  local _NODE="$2"
  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "peer chaincode install on $_NODE.$_ORG"
  [ $LOG_LEVEL -ge 3 ] && echo

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
  peer lifecycle chaincode approveformyorg --orderer "$ORDERER_HOST:$ORDERER_PORT" --tls  --cafile "$ORDERER_CA"\
      --sequence "$CC_SEQUENCE" --channelID "$CHANNEL_NAME" --name "$CC_NAME" --version "$CC_VERSION" \
      --package-id "$PACKAGE_ID" $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &> log.txt
  if [ $? != 0 ]; then
    echo "chaincode org approval failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

checkCommitReadiness() {
  echo
  echo "peer lifecycle chaincode checkcommitreadiness"
  echo
  peer lifecycle chaincode checkcommitreadiness --orderer "$ORDERER_HOST:$ORDERER_PORT" --channelID "$CHANNEL_NAME" --tls \
    --cafile "$ORDERER_CA" --name "$CC_NAME" --version "$CC_VERSION" --sequence "$CC_SEQUENCE" \
    $([ "$INIT_REQUIRED" == 'true' ] && echo '--init-required') &> log.txt
  if [ $? != 0 ]; then
    echo "chaincode check commit readiness failed"
    cat log.txt
    exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && cat log.txt
}

commitChaincode() {
  # shenanigans to handle commit command properly for MAJORITY endorsement
  # TO DO: check whether this is actually needed
  COMMIT_CMD="peer lifecycle chaincode commit --orderer $ORDERER_HOST:$ORDERER_PORT --channelID $CHANNEL_NAME --name $CC_NAME --version $CC_VERSION --sequence $CC_SEQUENCE --cafile "
  COMMIT_CMD+="'$ORDERER_CA' "
  COMMIT_CMD+="--tls"
  for x in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    COMMIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[x]}"
  done
  IFS=$'\n'
  for y in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    COMMIT_CMD+=" --tlsRootCertFiles"
    COMMIT_CMD+=" '${ARRAY_TLS_ROOTCERTS[y]}'"
  done
  IFS=$' '
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
  INIT_CMD="peer chaincode invoke --orderer $ORDERER_HOST:$ORDERER_PORT --tls" 
  INIT_CMD+=" --cafile"
  INIT_CMD+=" '$ORDERER_CA'"
  INIT_CMD+=" -C $CHANNEL_NAME --name $CC_NAME --isInit"
  for i in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    INIT_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[i]}"
  done
  IFS=$'\n'
  for i in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    INIT_CMD+=" --tlsRootCertFiles"
    INIT_CMD+=" '${ARRAY_TLS_ROOTCERTS[i]}'"
  done
  IFS=$' '
  if [ "$INIT_REQUIRED" == 'true' ]; then
    INIT_CMD+=" -c '{"\""function"\"":"\""Init"\"","\""Args"\"":[]}'"
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
}

# chaincode deploy operations are briefly described in:
# https://medium.com/geekculture/how-to-deploy-chaincode-smart-contract-45c20650786a
deployCCTest() {

  # get test chaincode params
  # TO DO: input for which chaincode params to get
  exportChaincode1Params
  
  # construct cc label from chaincodeParams
  CC_LABEL="$CC_NAME-$CC_VERSION"

  # get number of channels in network
  exportNetworkParams

  # loop channels to install cc on every peer
  # TO DO: have array in chaincodeParams with all channels where CC needs to be deployed
  for ((I=1; I <= "$NUM_CHANNELS"; I++)); do

    # shenanigans to prevent shared peers from breaking everything
    CC_NAME=$CC_NAME${I}
    CC_LABEL="$CC_NAME-$CC_VERSION"
    CC_PKG_NAME="$CC_SRC_PATH/$CC_NAME.tar.gz"

    # (re)instantiate helper arrays
    ARRAY_NODE_ADDRESSES=()
    ARRAY_TLS_ROOTCERTS=()

    # TO DO: change to accomodate the above TO DO
    EXPORT_CMD="exportChannel${I}Params"
    eval "$EXPORT_CMD"
   
    # loop channel orgs and install cc on every peer
    for j in "${!CHANNEL_ORGS[@]}"; do

      # TO DO: check whether org has any peer where CC needs to be installed
      local ORG="${CHANNEL_ORGS[j]}"

      # we need this for chaincode package
      export FABRIC_CFG_PATH="$ROOT/../config/"

      # steps for lifecycle: package, install, approve, commit
      # do package only once per org
      packageChaincode
      
      # shenanigans to get org nodes array
      local ARRAY_STR=$(grep CHANNEL_ORG"${j}"_NODES "$ROOT/globalParams.sh")
      local ARRAY_STR=$(sed "${I}q;d" <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d "=" -f2 <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d "(" -f2 <<< $ARRAY_STR)
      local ARRAY_STR=$(cut -d ")" -f1 <<< $ARRAY_STR)
      local HELPER_ARRAY=($ARRAY_STR)
      
      ## loop through all org peers for installation
      for k in "${!HELPER_ARRAY[@]}"; do
        local NODE="${HELPER_ARRAY[k]}"
        # TO DO: check whether CC needs to be installed on this peer
        installChaincode $ORG $NODE
        # Check installation and get package ID
        for cc in $(peer lifecycle chaincode queryinstalled --output json | jq -c '.installed_chaincodes[]')
        do
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
      if [ $((j+1)) -eq "${#CHANNEL_ORGS[@]}" ]; then
        # check commit readiness
        checkCommitReadiness
        # commit
        commitChaincode
        # initialize if needed
        if [ "$INIT_REQUIRED" == 'true' ]; then
          initChaincode
        fi
        # if test chaincode perform end to end test for this channel
        end2endTest
      fi
    done
  done
}

end2endTest() {

  echo
  echo "Waiting for chaincode to be ready for invoke..."
  # needs some time before init is complete, otherwise transaction throws error
  sleep 5
  
  echo
  echo "begin end to end test on channel $CHANNEL_NAME"
  echo

  # shenanigans to handle invoke command properly for MAJORITY endorsement
  E2E_CMD="peer chaincode invoke --orderer $ORDERER_HOST:$ORDERER_PORT --tls"
  E2E_CMD+=" --cafile"
  E2E_CMD+=" '$ORDERER_CA'"
  E2E_CMD+=" -C $CHANNEL_NAME --name $CC_NAME"
  for x in "${!ARRAY_NODE_ADDRESSES[@]}"; do
    E2E_CMD+=" --peerAddresses ${ARRAY_NODE_ADDRESSES[x]}"
  done
  IFS=$'\n'
  for y in "${!ARRAY_TLS_ROOTCERTS[@]}"; do
    E2E_CMD+=" --tlsRootCertFiles"
    E2E_CMD+=" '${ARRAY_TLS_ROOTCERTS[y]}'"
  done
  IFS=$' '
  E2E_CMD+=" -c '{"\""Args"\"":["\""1"\"","\""Blockchain"\"","\""10"\""],"\""Function"\"":"\""addMark"\""}'"

  echo "write test transaction on ledger, endorsed by all peers"
  echo

  [ $LOG_LEVEL -ge 4 ] && echo "$E2E_CMD"
  eval "$E2E_CMD"
  if [ $? != 0 ]; then
    echo "end to end test failed - unable to write test transaction"
    exit 1
  fi

  # needs some time before queries can be executed correctly
  sleep 5

  # loop through all peers and check whether query result matches expected value# loop channel orgs and install cc on every peer
  for q in "${!CHANNEL_ORGS[@]}"; do

    local ORG="${CHANNEL_ORGS[q]}"

    # shenanigans to get org nodes array
    local ARRAY_STR=$(grep CHANNEL_ORG"${q}"_NODES "$ROOT/globalParams.sh")
    local ARRAY_STR=$(sed "${I}q;d" <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d "=" -f2 <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d "(" -f2 <<< $ARRAY_STR)
    local ARRAY_STR=$(cut -d ")" -f1 <<< $ARRAY_STR)
    local HELPER_ARRAY=($ARRAY_STR)

    ## loop through all org peers for query
    for z in "${!HELPER_ARRAY[@]}"; do

      local NODE="${HELPER_ARRAY[z]}"
      
      echo
      echo "query sample transaction and check results for $NODE.$ORG"
      echo
      
      setGlobals "$ORG" "$NODE"

      # query
      [ $LOG_LEVEL -ge 4 ] && set -x
      peer chaincode query --orderer $ORDERER_HOST:$ORDERER_PORT --tls --cafile "$ORDERER_CA" -C $CHANNEL_NAME --name $CC_NAME -c '{"Args":["1"],"Function":"getAllMarks"}' >&log.txt
      [ $LOG_LEVEL -ge 4 ] && set +x

      # check whether value is as expected
      EXPECTED_VALUE="Blockchain:[10]"
      sed -i 's/\\//g' log.txt && sed -i 's/"//g' log.txt
      VALUE=$(grep Blockchain log.txt)
      VALUE=$(cut -d "{" -f2 <<< $VALUE)
      VALUE=$(cut -d "}" -f1 <<< $VALUE)
      
      if [ $VALUE != $EXPECTED_VALUE ]; then
        echo
        echo "end to end test failed - query result differs from expected result for $NODE.$ORG"
        echo
        exit 1
      else
        echo
        echo "query result is equal to expected value for $NODE.$ORG"
      fi
    done
  done

  echo
  echo "end to end test performed successfully on channel '$CHANNEL_NAME'"
  echo
}

# parse input flags
while [[ $# -ge 1 ]] ; do
  key="$1"
  case $key in
  -h)
    printHelp
    exit 0
    ;;
  -v) # debug
    export LOG_LEVEL='4'
    ;;
  -l) # from 1=error to 5=trace
    export LOG_LEVEL="$2"
    shift
    ;;
  e2e)
    MODE="$1"
    shift
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

if [ "$MODE" == "e2e" ]; then
  [ $LOG_LEVEL -ge 2 ] && echo
  [ $LOG_LEVEL -ge 2 ] && echo "Deploying test chaincode for end to end network testing"
  deployCCTest
else
  printHelp
  exit 1
fi