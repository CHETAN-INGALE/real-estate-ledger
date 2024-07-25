#!/bin/bash
BASE_DIR="$(pwd)"
. "$BASE_DIR/configParams.sh"

function clientsUp {

    exportGlobalParams
    exportOrgParams
    exportNode1Params
    GOSSIP_NODE=$NODE_FULL_NAME:$NODE_PORT
    sed -i 's/CORE_PEER_GOSSIP_BOOTSTRAP=$NODE_FULL_NAME:$NODE_PORT/CORE_PEER_GOSSIP_BOOTSTRAP='"$GOSSIP_NODE"'/g' "$BASE_DIR/docker/client-compose.yaml"

    local I="$1" # Accept "I" parameter as input

    export PATH="$BASE_DIR/../../../../bin":$PATH
    setCerts "$I"
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
    if [ ! $? -eq 0 ]; then
        [ $LOG_LEVEL -ge 2 ] && echo "docker-compose up failed: client node $NODE_FULL_NAME could not be launched"
        exit 1
    fi
    [ $LOG_LEVEL -ge 4 ] && set +x

    sleep 5

    exportNode1Params
    GOSSIP_NODE=$NODE_FULL_NAME:$NODE_PORT
    sed -i 's/CORE_PEER_GOSSIP_BOOTSTRAP='"$GOSSIP_NODE"'/CORE_PEER_GOSSIP_BOOTSTRAP=$NODE_FULL_NAME:$NODE_PORT/g' "$BASE_DIR/docker/client-compose.yaml"

}

function setCerts() {
    local I="$1" # Accept "I" parameter as input
    export FABRIC_CA_SERVER_HOME="$BASE_DIR/ca-server"
    export FABRIC_CA_CLIENT_HOME="$BASE_DIR"
    export PATH="$BASE_DIR/../../../../bin":$PATH
    exportCaParams
    exportNode"$I"Params

    fabric-ca-client getcainfo -u "https://caAdmin:caAdminpw@$CA_HOST:$CA_PORT" \
        --caname "$CA_NAME" --tls.certfiles "$FABRIC_CA_SERVER_HOME/tls-cert.pem" --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"

    fabric-ca-client enroll -u https://caAdmin:caAdminpw@$CA_HOST:$CA_PORT --caname $CA_NAME --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Register client $I"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client register --caname "$CA_NAME" --id.name "client$I" --id.secret client"$I"pw --id.type client --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && set +x
    mkdir -p $NODE_PATH

    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Generate client $I MSP"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client enroll -u "https://client$I:client${I}pw@$CA_HOST:$CA_PORT" \
        --caname "$CA_NAME" -M "$NODE_PATH/msp" --csr.hosts "$NODE_FULL_NAME" --csr.hosts "$NODE_HOST" \
        --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && set +x

    cp "$FABRIC_CA_SERVER_HOME/msp/config.yaml" "$NODE_PATH/msp/config.yaml"

    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Generate client $I TLS certificates"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client enroll -u "https://client$I:client${I}pw@$CA_HOST:$CA_PORT" \
        --caname "$CA_NAME" -M "$NODE_PATH/tls" --enrollment.profile tls --csr.hosts "$NODE_FULL_NAME" \
        --csr.hosts "$NODE_HOST" --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && set +x

    # TODO: check that source folders only contain one file, otherwise these will fail
    cp "$NODE_PATH/tls/tlscacerts/"* "$NODE_PATH/tls/ca.crt"
    cp "$NODE_PATH/tls/signcerts/"* "$NODE_PATH/tls/server.crt"
    cp "$NODE_PATH/tls/keystore/"* "$NODE_PATH/tls/server.key"

    mkdir -p $NODE_PATH/msp/tlscacerts
    cp "$NODE_PATH/tls/tlscacerts/"* "$NODE_PATH/msp/tlscacerts/tlsca.$ORG_NAME-cert.pem"

    #perch� tlsca e tlscacerts hanno stesso contenuto?
    mkdir -p $NODE_PATH/msp/tlsca
    cp "$NODE_PATH/tls/tlscacerts/"* "$NODE_PATH/msp/tlsca/tlsca.$ORG_NAME-cert.pem"

    #rinominare cartella?
    mkdir -p $NODE_PATH/msp/ca
    cp "$NODE_PATH/msp/cacerts/"* "$FABRIC_CA_SERVER_HOME/ca.$ORG_NAME-cert.pem"

    #TODO workaround bug: ca certifications are stored und0er a wrong name; should be fixed in a cleaner way
    if [ $CA_NAME == '*.*' ]; then
        mv "$NODE_PATH/msp/cacerts/$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
            "$NODE_PATH/msp/cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem"
        mv "$NODE_PATH/tls/tlscacerts/tls-$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
            "$NODE_PATH/tls/tlscacerts/tls-$CA_HOST-$CA_PORT-$CA_NAME.pem"
    fi

}
read -p "Enter node index: " I
# Call the function and pass the "I" parameter
clientsUp "$I"