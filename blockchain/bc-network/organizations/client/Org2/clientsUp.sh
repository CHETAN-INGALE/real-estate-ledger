BASE_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"
. "$BASE_DIR/configParams.sh"

function clientsUp {

  export PATH="$BASE_DIR/../../../../bin":$PATH

  exportGlobalParams
  exportOrgParams

  exportNode1Params
  GOSSIP_NODE=$NODE_FULL_NAME:$NODE_PORT
  sed -i 's/CORE_PEER_GOSSIP_BOOTSTRAP=$NODE_FULL_NAME:$NODE_PORT/CORE_PEER_GOSSIP_BOOTSTRAP='"$GOSSIP_NODE"'/g' "$BASE_DIR/docker/client-compose.yaml"

  I=1
  while [ $I -le $NODE_NUM ]
  do
    exportNode"$I"Params

    [ $LOG_LEVEL -ge 3 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Start docker container for $NODE_FULL_NAME"
    [ $LOG_LEVEL -ge 3 ] && echo

    cp "$BASE_DIR/docker/client-compose.yaml" "$NODE_COMPOSE_FILE"
    sed -i "s/"'$SERVICE_NAME'"/$NODE_FULL_NAME-service/g" "$NODE_COMPOSE_FILE"

    exportNode"$I"Params

    [ $LOG_LEVEL -ge 4 ] && set -x
    IMAGE_TAG="$NODE_IMAGETAG" NODE_FULL_NAME="$NODE_FULL_NAME" NODE_PORT="$NODE_PORT" NODE_PATH="$NODE_PATH" \
        docker-compose -f "$NODE_COMPOSE_FILE" -p "$PROJECT_NAME" up -d
    if [ ! $? -eq 0 ];
    then
        [ $LOG_LEVEL -ge 2 ] && echo "docker-compose up failed: client node $NODE_FULL_NAME could not be launched"
        exit 1
    fi
	[ $LOG_LEVEL -ge 4 ] && set +x

    ((I++))
  done

  sleep 5

  exportNode1Params
  GOSSIP_NODE=$NODE_FULL_NAME:$NODE_PORT
  sed -i 's/CORE_PEER_GOSSIP_BOOTSTRAP='"$GOSSIP_NODE"'/CORE_PEER_GOSSIP_BOOTSTRAP=$NODE_FULL_NAME:$NODE_PORT/g' "$BASE_DIR/docker/client-compose.yaml"

}

clientsUp