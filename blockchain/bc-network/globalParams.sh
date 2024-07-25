
#!/bin/bash

### CONFIGURABLE OPTIONS ###
# the following options are default values that can be overwritten via network.sh cli options
# number of retries on an unsuccessful command
export MAX_RETRY='10'
# delay between command retries, in seconds
export CLI_DELAY='2'
# level of logs verbosity, represented by an integer
export LOG_LEVEL="${LOG_LEVEL:-4}" # 1->error, 2->warning, 3->info, 4->debug, 5->trace
############################
# map of our log levels (1-5) against the ones for fabric and docker-compose
export FABRIC_LOGS=('' 'critical' 'error' 'warning' 'info' 'debug')
export COMPOSE_LOGS=('' 'CRITICAL' 'ERROR' 'WARNING' 'INFO' 'DEBUG')

ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"

listConfigParams () {
  local all='false'
  if [ "$#" -eq 2 ]; then
    local type="$1"
    local name="$2"
    echo "$ROOT/organizations/$type/$name/configParams.sh"
  elif [ "$#" -eq 1 ]; then
    # list all organizations of the given type if no name is specified
    local type="$1"
    for org in $(ls "$ROOT/organizations/$type"); do
      echo "$ROOT/organizations/$type/$org/configParams.sh"
    done
  elif [ "$#" -eq 0 ]; then
    # list all organizations if none is specified
    for type in 'client' 'order'; do
      listConfigParams $type
    done
  else
    echo "expected usage: listConfigParams [ <client|order> [ORG_NAME] ]"
    exit 1
  fi
}

exportNetworkParams () {
  # genesis profile
  export GENESIS_PROFILE="TwoOrgsOrdererGenesis"
  # default image tag
  export IMAGETAG="2.2.0"
  # default ca image tag
  export CA_IMAGETAG="1.4.7"
  # default database
  export DATABASE="CouchDB"
  # number of channels in this network
  export NUM_CHANNELS='1'  
  export NEW_CHANNEL=()
	export NEW_ORG=()

  export NETWORK_CHANNELS=(channel1)
}

exportChannel1Params () {
  export CHANNEL_NAME='channel1'
  export CHANNEL_PROFILE='channel1Profile'
  export CHANNEL_CREATOR='Org1'
  export CHANNEL_ORDERER_ORG='Org3'
  export CHANNEL_ORDERER_NAME='Node3'
  source "$(listConfigParams 'order' "$CHANNEL_ORDERER_ORG")"
  export ORD_INDEX=$(getNodeIndex "$CHANNEL_ORDERER_NAME")
  exportNode"$ORD_INDEX"Params
  export ORDERER_CA="$NODE_PATH/msp/tlscacerts/tlsca.Org3-cert.pem"
  export CHANNEL_ORDERER="$CHANNEL_ORDERER_NAME.$CHANNEL_ORDERER_ORG"
  export ORDERER_HOST='localhost'
  export ORDERER_PORT='108'
  export CHANNEL_MEMBER1_NODE='Node1'
  export CHANNEL_MEMBER1_ORG='Org1'
  
  export CHANNEL_MEMBER1_NODE='Node2'
  export CHANNEL_MEMBER1_ORG='Org2'
  
  export NUM_MEMBERS='2'
  export NUM_ANCHORS='0'
  export CHANNEL_SIZE='2'
  export CHANNEL_ORGS=(Org1 Org2)
  
  export CHANNEL_ORG0_NODES=(Node1)
  
  export CHANNEL_ORG1_NODES=(Node2)
  
}
