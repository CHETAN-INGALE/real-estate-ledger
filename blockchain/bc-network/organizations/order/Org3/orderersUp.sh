BASE_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"
. "$BASE_DIR/configParams.sh"

function orderersUp {

  exportGlobalParams
  exportOrgParams

  export PATH="$BASE_DIR/../../../../bin":$PATH

  I=1
  while [ $I -le $NODE_NUM ]
  do
    exportNode"$I"Params

    [ $LOG_LEVEL -ge 3 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Start docker container for $NODE_FULL_NAME"
    [ $LOG_LEVEL -ge 3 ] && echo

    cp "$BASE_DIR/docker/orderer-compose.yaml" "$NODE_COMPOSE_FILE"
    sed -i "s/"'$SERVICE_NAME'"/$NODE_FULL_NAME-service/g" "$NODE_COMPOSE_FILE"

    [ $LOG_LEVEL -ge 4 ] && set -x
    # TODO: check if container is already up so next command can be skipped
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

}

orderersUp