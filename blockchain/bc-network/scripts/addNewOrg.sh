#!/bin/bash
CLIENT_CA_relpath='tls/ca.crt'
ROOT="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"

source "$ROOT/globalParams.sh"
exportChannel1Params

function setSkeleton() {
  NEW_ORG_TYPE="$1"
  NEW_ORG_NAME="$2"
  NEW_CA_PORT="$3"

  cd "$ROOT/organizations/$NEW_ORG_TYPE"
  mkdir "$NEW_ORG_NAME"
  cd "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME"
  mkdir "ca-server"
  mkdir "docker"

  if [[ $NEW_ORG_TYPE == "client" ]]; then
    COPY_FROM="$CHANNEL_CREATOR"
    source "$ROOT/organizations/client/$COPY_FROM/configParams.sh"
    exportCaParams
    search_string="url: https:\/\/localhost:$CA_PORT"

    cp "$ROOT/organizations/client/$COPY_FROM/clientsUp.sh" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/client/$COPY_FROM/setupClientOrg.sh" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/client/$COPY_FROM/fabric-ca-client-config.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/client/$COPY_FROM/ca-server/fabric-ca-server-config.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/ca-server/"
    cp "$ROOT/organizations/client/$COPY_FROM/docker/ca-compose.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/"
    cp "$ROOT/organizations/client/$COPY_FROM/docker/client-compose.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/"
    touch "$ROOT/organizations/client/$NEW_ORG_NAME/configParams.sh"
    chmod +x "$ROOT/organizations/client/$NEW_ORG_NAME/configParams.sh"
    # filename="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/fabric-ca-client-config.yaml"
    # sed -i "s/$search_string/url: https:\/\/localhost:$NEW_CA_PORT/" "$filename"
  fi
  if [[ $NEW_ORG_TYPE == "order" ]]; then

    echo "ORDERER"
    echo "$CHANNEL_CREATOR"

    export COPY_FROM="$CHANNEL_ORDERER_ORG"
    source "$ROOT/organizations/order/$COPY_FROM/configParams.sh"
    exportCaParams
    search_string="url: https:\/\/localhost:$CA_PORT"

    cp "$ROOT/organizations/order/$COPY_FROM/orderersUp.sh" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/order/$COPY_FROM/setupOrdererOrg.sh" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/order/$COPY_FROM/fabric-ca-client-config.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/"
    cp "$ROOT/organizations/order/$COPY_FROM/ca-server/fabric-ca-server-config.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/ca-server/"
    cp "$ROOT/organizations/order/$COPY_FROM/docker/ca-compose.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/"
    cp "$ROOT/organizations/order/$COPY_FROM/docker/orderer-compose.yaml" "$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/"
    touch "$ROOT/organizations/order/$NEW_ORG_NAME/configParams.sh"
    chmod +x "$ROOT/organizations/client/$NEW_ORG_NAME/configParams.sh"

    filename="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/orderer-compose.yaml"
    search_string2="        - ../../../../system-genesis-block/genesis.block:/var/hyperledger/orderer/orderer.genesis.block"
    replaceString= "        - ../../../../channel-artifacts/config_block.block:/var/hyperledger/orderer/orderer.genesis.block"
    sed -i "s/$search_string/$replaceString/" "$filename"
  fi

  filename="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/fabric-ca-client-config.yaml"
  sed -i "s/$search_string/url: https:\/\/localhost:$NEW_CA_PORT/" "$filename"

}

function readInputs() {
  CER_EXIST=()
  PORT_EXIST=()

  OLD_IFS=$IFS # OLD_IFS is " \t\n"
  IFS=$'\n'
  for CHECK_INP in $(listConfigParams); do
    source "$CHECK_INP"
    exportCaParams
    CER_EXIST+=$CA_NAME
    CER_EXIST+=" "

    PORT_EXIST+=" "
    PORT_EXIST+=$CA_PORT
    PORT_EXIST+=" "
    exportNode1Params
    PORT_EXIST+=" "
    PORT_EXIST+=$NODE_PORT
    PORT_EXIST+=" "
    PORT_EXIST+=$NODE_PORT_CC
  done

  PORT_EXIST=$(echo "${PORT_EXIST[@]}" | tr ' ' '\n' | sort -u | tr '\n' ' ')

  EXIST_CLIENT=$(ls $ROOT/organizations/client/ | xargs)
  EXIST_ORDER=$(ls $ROOT/organizations/order/ | xargs)
  NUM1=$(ls $ROOT/organizations/client/ | wc -l)
  NUM2=$(ls $ROOT/organizations/order/ | wc -l)

  ################################################################
  read -p "Enter ORGANIZATION TYPE (client or order) : " NEW_ORG_TYPE
  while ! [[ "$NEW_ORG_TYPE" == "client" || "$NEW_ORG_TYPE" == "order" ]]; do
    echo "ERR => The ORGANIZATION TYPE is wrong, please"
    read -p "Enter ORGANIZATION TYPE (client or orderer) : " NEW_ORG_TYPE
  done
  ################################################################
  if [[ "$NEW_ORG_TYPE" = "client" ]]; then
    read -p "Enter ORGANIZATION NAME (existing $EXIST_CLIENT) : " NEW_ORG_NAME
    while [[ " ${EXIST_CLIENT[*]} " == *" ${NEW_ORG_NAME} "* ]]; do
      echo "ERR => The name is already used. please choose a new different name for the client organization:"
      read -p "Enter ORGANIZATION NAME : " NEW_ORG_NAME
    done
  fi
  if [[ "$NEW_ORG_TYPE" = "order" ]]; then
    read -p "Enter ORGANIZATION NAME (existing $EXIST_ORDER) : " NEW_ORG_NAME
    while [[ " ${EXIST_ORDER[*]} " == *" ${NEW_ORG_NAME} "* ]]; do
      echo "ERR => The name is already used. please choose a new different name for the order organization:"
      read -p "Enter ORGANIZATION NAME : " NEW_ORG_NAME
    done
  fi
  source "$ROOT/globalParams.sh"
  exportNetworkParams
  FINAL_ORG=(${NEW_ORG[*]})
  FINAL_ORG+=($NEW_ORG_NAME)

  Number=$(find "$ROOT"/globalParams.sh | sed 's/ /\\ /g' | xargs grep -i "export NEW_ORG=()" | wc -l)
  if [[ "${Number}" -gt 0 ]]; then
    sed -i "s/export NEW_ORG=()/export NEW_ORG=(${NEW_ORG_NAME})/" "$ROOT/globalParams.sh"
  else
    sed -i "s/export NEW_ORG=(${NEW_ORG[*]})/export NEW_ORG=(${FINAL_ORG[*]})/" "$ROOT/globalParams.sh"
  fi



  ################################################################
  
  read -p "Enter y if you want to use CouchDb, otherwise press n " -n 1 -r USE_COUCHDB
  echo 
  while [[ "${USE_COUCHDB}" != "y" ]] && [[ "${USE_COUCHDB}" != "n" ]]; do
    echo "ERR => The parameter must be either 'y' or 'n'"
    read -p "Enter y if you want to use CouchDb, otherwise press n " -n 1 -r USE_COUCHDB
    echo 
  done

  if [[ "$USE_COUCHDB" = "y" ]]; then
    read -p "Enter COUCHDB PORT : " COUCHDB_PORT
  fi
  ################################################################

  read -p "Enter CA_NAME (Existing: $CER_EXIST): " NEW_CA_NAME
  while [[ " $CER_EXIST " == *"$NEW_CA_NAME"* ]]; do
    echo "ERR => The name is already used. please choose a new different name for the Certificate Authority:"
    read -p "Enter CA_NAME : " NEW_CA_NAME
  done

  read -p "Enter CA_PORT (Existing: $PORT_EXIST): " NEW_CA_PORT
  while [[ " $PORT_EXIST " == *"$NEW_CA_PORT"* ]]; do
    echo "ERR => The port number is already used. please choose a new different port number for the Certificate Authority:"
    read -p "Enter CA_PORT : " NEW_CA_PORT
  done
  PORT_EXIST+=" "
  PORT_EXIST+=$NEW_CA_PORT
  ################################################################

  IFS=$OLD_IFS
  read -p "Enter NODE NAMES separated by space (e.g., Peer1 Peer2) : " NEW_MEMBERS_STR

  NEW_MEMBERS=(${NEW_MEMBERS_STR})

  for ((j = 1; j <= ${#NEW_MEMBERS[@]}; j++)); do
    k=$((j - 1))
    CMD="NEW_MEMBERS[${k}]"
    NEW_NODE=${!CMD}

    read -p "Enter ${NEW_NODE} PORT (Existing: $PORT_EXIST): " NEW_MEMBERS_PORTS[k]
    while [[ " $PORT_EXIST " == *"${NEW_MEMBERS_PORTS[$k]}"* ]]; do
      echo "ERR => The port number is already used. please choose a new different port number for the NODE NAMES:"
      read -p "Enter ${NEW_NODE} PORT : " NEW_MEMBERS_PORTS[k]
    done
    PORT_EXIST+=" "
    PORT_EXIST+=${NEW_MEMBERS_PORTS[*]}

    read -p "Enter ${NEW_NODE} CHAINCODE PORT (Existing: $PORT_EXIST): " NEW_MEMBERS_CC_PORTS[k]
    while [[ " $PORT_EXIST " == *"${NEW_MEMBERS_CC_PORTS[$k]}"* ]]; do
      echo "ERR => The port number is already used. please choose a new different port number for the CHAINCODE:"
      read -p "Enter ${NEW_NODE} CHAINCODE PORT : " NEW_MEMBERS_CC_PORTS[k]
    done
    PORT_EXIST+=" "
    PORT_EXIST+=${NEW_MEMBERS_CC_PORTS[*]}

  done

  setSkeleton "$NEW_ORG_TYPE" "$NEW_ORG_NAME" "$NEW_CA_PORT"

  if [[ $NEW_ORG_TYPE == "client" ]]; then
    filename="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/client-compose.yaml"
    SETUP_SCRIPT='$BASE_DIR/setupClientOrg.sh'
    UP_SCRIPT='$BASE_DIR/clientsUp.sh'
  else
    filename="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/docker/orderer-compose.yaml"
    SETUP_SCRIPT='$BASE_DIR/setupOrdererOrg.sh'
    UP_SCRIPT='$BASE_DIR/orderersUp.sh'
  fi

  if [[ "$USE_COUCHDB" = "y" ]]; then
    sed -i "s/  couchdb5/  couchdb$NEW_ORG_NAME/" "$filename"
    sed -i "s/    container_name: couchdb5/    container_name: couchdb$NEW_ORG_NAME/" "$filename"

    sed -i "s/      - \"3984:5984\"/      - \"$COUCHDB_PORT:5984\"/" "$filename"

    sed -i "s/      - couchdb5/      - couchdb$NEW_ORG_NAME/" "$filename"
  fi

  configFile="$ROOT/organizations/$NEW_ORG_TYPE/$NEW_ORG_NAME/configParams.sh"
  echo 'BASE_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"' >>"$configFile"
  echo "ORG_NAME=$NEW_ORG_NAME" >>"$configFile"
  #echo "MEMBERS=('' ${NEW_MEMBERS_STR})" >>"$configFile"
  echo -n "MEMBERS=(''" >> "$configFile"
  for member in "${NEW_MEMBERS[@]}"; do
    echo -n " '$member'" >> "$configFile"
  done
  echo ")" >> "$configFile"

  echo "export FABRIC_LOGS=('' 'critical' 'error' 'warning' 'info' 'debug')" >>"$configFile"
  echo "export COMPOSE_LOGS=('' 'CRITICAL' 'ERROR' 'WARNING' 'INFO' 'DEBUG')" >>"$configFile"
  echo 'function getNodeIndex {
  NAME=$1
  for i in "${!MEMBERS[@]}"
  do
    if [[ "${MEMBERS[$i]}" = "$NAME" ]]; then
              echo "$i";
      exit
    fi
  done
  echo "Node not found: $NAME"
  exit 1
  }

 function exportGlobalParams {

  export PROJECT_NAME="test"
  export BASE_DIR="$BASE_DIR"

  }' >>"$configFile"
  h=$((j - 1))
  echo "
 function exportOrgParams {

  export NODE_NUM="$h"" >>"$configFile"
  echo " export MSP_NAME="$NEW_ORG_NAME"" >>"$configFile"
  echo " export ORG_SETUP_SCRIPT="$SETUP_SCRIPT"" >>"$configFile"
  echo " export ORG_UP_SCRIPT="$UP_SCRIPT"" >>"$configFile"
  echo '
 }' >>"$configFile"

  echo "function exportCaParams {

  export CA_NAME="$NEW_CA_NAME"
  export CA_HOST=""localhost""
  export CA_PORT="$NEW_CA_PORT"
  export CA_IMAGETAG=""1.4.7" "" >>"$configFile"
  echo ' export CA_COMPOSE_FILE="$BASE_DIR/docker/$CA_NAME-compose.yaml"

 }' >>"$configFile"

  for ((j = 1; j <= ${#NEW_MEMBERS[@]}; j++)); do
    k=$((j - 1))
    CMD_PORT=NEW_MEMBERS_PORTS[$k]
    CMD_CC_PORT=NEW_MEMBERS_CC_PORTS[$k]
    NEW_NODE_PORT=${!CMD_PORT}
    NEW_CC_PORT=${!CMD_CC_PORT}
    echo "function exportNode${j}Params {

  local NODE_INDEX='$j'" >>"$configFile"

    echo ' export NODE_NAME="${MEMBERS[NODE_INDEX]}"
    export NODE_FULL_NAME="$NODE_NAME.$ORG_NAME"
    export NODE_HOST="localhost"
    export NODE_IMAGETAG="2.2.0"' >>"$configFile"
    echo "
    export NODE_PORT="$NEW_NODE_PORT"
    export NODE_PORT_CC="$NEW_CC_PORT" " >>"$configFile"
    echo 'export NODE_COMPOSE_FILE="$BASE_DIR/docker/node_$NODE_INDEX-compose.yaml"' >>"$configFile"
    if [[ $NEW_ORG_TYPE == "client" ]]; then
      echo 'export NODE_PATH="$BASE_DIR/clients/node_$NODE_INDEX"
   }' >>"$configFile"

    else

      echo 'export NODE_PATH="$BASE_DIR/orderers/node_$NODE_INDEX"
   }' >>"$configFile"

    fi

  done

}

function checkOrLaunchSetup() {
  # retrieve the 'configParams.sh' script for every node and export its global variables
  IFS=$'\n'
  local type="$1"
  local name="$2"
  source "$ROOT/organizations/$type/$name/configParams.sh"
  exportGlobalParams
  # check whether the setup was already executed
  # TODO: find a better way to tell whether the setup is complete or not
  if [ ! -r "$BASE_DIR/ca-server/tls-cert.pem" ]; then
    exportOrgParams
    source "$ORG_SETUP_SCRIPT"
    STATUS=$?
    if [ ! $STATUS -eq 0 ]; then
      [ $LOG_LEVEL -ge 2 ] && echo "setup script failed with exit status $STATUS: $ORG_SETUP_SCRIPT"
      exit 1
    fi
  fi

}

function createConfigtx() {
  config="$ROOT/configtx/configtx.yaml"
  newFile="$ROOT/tmp.txt"
  touch "$newFile"

  if [[ $NEW_ORG_TYPE == "client" ]]; then
    echo "
    - &$NEW_ORG_NAME
      Name: $NEW_ORG_NAME

      # ID to load the MSP definition as
      ID: $NEW_ORG_NAME

      # MSPDir is the filesystem path which contains the MSP configuration
      MSPDir: ../organizations/client/$NEW_ORG_NAME/ca-server/msp

      # Policies defines the set of policies at this level of the config tree
      # For organization policies, their canonical path is usually
      #   /Channel/<Application|Orderer>/<OrgName>/<PolicyName>
      Policies:
        Readers:
          Type: Signature
          Rule: OR('$NEW_ORG_NAME.admin', '$NEW_ORG_NAME.peer', '$NEW_ORG_NAME.client')
        Writers:
          Type: Signature
          Rule: OR('$NEW_ORG_NAME.admin', '$NEW_ORG_NAME.client')
        Admins:
          Type: Signature
          Rule: OR('$NEW_ORG_NAME.admin')
        Endorsement:
          Type: Signature
          Rule: OR('$NEW_ORG_NAME.peer')

      AnchorPeers:
              # AnchorPeers defines the location of peers which can be used
              # for cross org gossip communication.  Note, this value is only
              # encoded in the genesis block in the Application section context" >>"$newFile"
  else
    newFile2="$ROOT/tmp2.txt"
    touch "$newFile2"
    newFile3="$ROOT/tmp3.txt"
    touch "$newFile3"
    newFile4="$ROOT/tmp4.txt"
    touch "$newFile4"

    PORT=${NEW_MEMBERS_PORTS}
    echo "
    - &$NEW_ORG_NAME
        Name: $NEW_ORG_NAME

        # ID to load the MSP definition as
        ID: $NEW_ORG_NAME

        # MSPDir is the filesystem path which contains the MSP configuration
        MSPDir: ../organizations/order/$NEW_ORG_NAME/ca-server/msp

        # Policies defines the set of policies at this level of the config tree
        # For organization policies, their canonical path is usually
        #   /Channel/<Application|Orderer>/<OrgName>/<PolicyName>
        Policies:
            Readers:
                Type: Signature
                Rule: OR('$NEW_ORG_NAME.member')
            Writers:
                Type: Signature
                Rule: OR('$NEW_ORG_NAME.member')
            Admins:
                Type: Signature
                Rule: OR('$NEW_ORG_NAME.admin')
        
        OrdererEndpoints:
            - $NEW_MEMBERS_STR.$NEW_ORG_NAME:$PORT   " >>"$newFile"

    echo "
        - Host: $NEW_MEMBERS_STR.$NEW_ORG_NAME
          Port: $PORT
          ClientTLSCert: ../organizations/order/$NEW_MEMBERS_STR/orderers/node_1/tls/server.crt
          ServerTLSCert: ../organizations/order/$NEW_MEMBERS_STR/orderers/node_1/tls/server.crt
" >>$newFile2

    nLine=$(cat "$config" | grep -n '        Consenters:' | tail -n1 | cut -d: -f1)
    sed -i "$nLine r $newFile2" "$config"
    rm "$newFile2"

    echo "                - *$NEW_ORG_NAME
" >>$newFile3

    echo "        - *$NEW_ORG_NAME" >>$newFile4
    nLine=$(cat "$config" | grep -n "$COPY_FROM" | tail -n1 | cut -d: -f1)
    sed -i "$nLine r $newFile3" "$config"
    rm "$newFile3"

    nLine=$(cat "$config" | grep -n "# For Orderer policies, their canonical path is" | tail -n1 | cut -d: -f1)
    nLine=$((nLine - 2))
    sed -i "$nLine r $newFile4" "$config"
    rm "$newFile4"
  fi

  nLine=$(cat "$config" | grep -n '      # encoded in the genesis block in the Application section context' | tail -n1 | cut -d: -f1)
  sed -i "$nLine r $newFile" "$config"
  rm "$newFile"
}

readInputs
createConfigtx
checkOrLaunchSetup $NEW_ORG_TYPE $NEW_ORG_NAME

source "$ROOT/scripts/createConfigBlock.sh"

main $NEW_ORG_NAME "$NEW_MEMBERS_STR" $NEW_ORG_TYPE

echo 
echo "New organization $NEW_ORG_NAME added to the network"
echo 

