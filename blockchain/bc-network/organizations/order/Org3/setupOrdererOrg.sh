BASE_DIR="$(dirname "$(realpath "$BASH_SOURCE")")"
. "$BASE_DIR/configParams.sh"

function setupOrdererOrg {

  exportGlobalParams
  exportOrgParams
  exportCaParams

  export PATH="$BASE_DIR/../../../../bin":$PATH

  export FABRIC_CA_CLIENT_HOME="$BASE_DIR"
  export FABRIC_CA_SERVER_HOME="$BASE_DIR/ca-server"

  [ $LOG_LEVEL -ge 3 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "Start CA docker container"
  [ $LOG_LEVEL -ge 4 ] && echo
  IFS=$'\n'
  for dir in "keystore" "cacerts" "signcerts"
  do
      if [ ! -d "$FABRIC_CA_SERVER_HOME/msp/$dir" ]
      then
          mkdir -p "$FABRIC_CA_SERVER_HOME/msp/$dir"
      fi
  done

  cp "$BASE_DIR/docker/ca-compose.yaml" "$CA_COMPOSE_FILE"
  sed -i "s/"'$SERVICE_NAME'"/$CA_NAME-service/g" "$CA_COMPOSE_FILE"

  IMAGE_TAG="$CA_IMAGETAG" CA_NAME="$CA_NAME" CA_PORT="$CA_PORT" docker-compose \
      -f "$CA_COMPOSE_FILE" -p "$PROJECT_NAME" up -d
  if [ ! $? -eq 0 ];
  then
      [ $LOG_LEVEL -ge 2 ] && echo "docker-compose up failed: certificate authority $CA_NAME could not be launched"
      exit 1
  fi

  SRV_UP='false'
  for (( ATTEMPT=0; ATTEMPT<MAX_RETRY; ATTEMPT++ ))
  do
      [ $LOG_LEVEL -ge 4 ] && echo "-> $ATTEMPT"
      if [ -r "$FABRIC_CA_SERVER_HOME/tls-cert.pem" ]
      then
          SRV_UP='true'
          break
      else
          sleep $CLI_DELAY
      fi
  done
  if [ "$SRV_UP" == 'false' ]
  then
      echo "--------- server is not done after $ATTEMPT attempts -------"
      exit 1
  fi

  if [ ! -w "$FABRIC_CA_SERVER_HOME/msp" ]
  then
      echo "--------- no write permission on the msp folder -------"
      exit 1
  fi

  echo "NodeOUs:
  Enable: true
  ClientOUIdentifier:
    Certificate: cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem
    OrganizationalUnitIdentifier: client
  PeerOUIdentifier:
    Certificate: cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem
    OrganizationalUnitIdentifier: peer
  AdminOUIdentifier:
    Certificate: cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem
    OrganizationalUnitIdentifier: admin
  OrdererOUIdentifier:
    Certificate: cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem
    OrganizationalUnitIdentifier: orderer" > $FABRIC_CA_SERVER_HOME/msp/config.yaml

  [ $LOG_LEVEL -ge 4 ] && set -x
  fabric-ca-client getcainfo -u "https://caAdmin:caAdminpw@$CA_HOST:$CA_PORT" --caname "$CA_NAME"\
    --tls.certfiles "$FABRIC_CA_SERVER_HOME/tls-cert.pem" --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
  if [ ! $? -eq 0 ];
  then
      echo "fabric-ca-client cainfo failed, error response from server"
      exit 1
  fi
  [ $LOG_LEVEL -ge 4 ] && set +x

  [ $LOG_LEVEL -ge 4 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "Enroll CA admin"
  [ $LOG_LEVEL -ge 4 ] && echo

  [ $LOG_LEVEL -ge 4 ] && set -x
  fabric-ca-client enroll -u "https://caAdmin:caAdminpw@$CA_HOST:$CA_PORT" --caname "$CA_NAME"\
    --tls.certfiles "$FABRIC_CA_SERVER_HOME/tls-cert.pem" --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
  [ $LOG_LEVEL -ge 4 ] && set +x

  #TODO workaround bug: ca certifications are stored under a wrong name; should be fixed in a cleaner way
  if [ $CA_NAME == '*.*' ]; then
	mv "$FABRIC_CA_SERVER_HOME/msp/cacerts/$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
      "$FABRIC_CA_SERVER_HOME/msp/cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem"
  fi

  #Node loop
  I=1
  while [ $I -le $NODE_NUM ]
  do
    exportNode"$I"Params

    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Register orderer $I"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client register --caname "$CA_NAME" --id.name "orderer$I" --id.secret orderer"$I"pw\
        --id.type orderer --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 3 ] && set +x
    mkdir -p $NODE_PATH

    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Generate orderer $I MSP"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client enroll -u "https://orderer$I:orderer${I}pw@$CA_HOST:$CA_PORT" --caname "$CA_NAME"\
      -M "$NODE_PATH/msp" --csr.hosts "$NODE_FULL_NAME" --csr.hosts "$NODE_HOST"\
      --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && set +x

    cp "$FABRIC_CA_SERVER_HOME/msp/config.yaml" "$NODE_PATH/msp/config.yaml"

    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 3 ] && echo "Generate orderer $I TLS certificates"
    [ $LOG_LEVEL -ge 4 ] && echo
    [ $LOG_LEVEL -ge 4 ] && set -x
    fabric-ca-client enroll -u "https://orderer$I:orderer${I}pw@$CA_HOST:$CA_PORT"\
        --caname "$CA_NAME" -M "$NODE_PATH/tls" --enrollment.profile tls --csr.hosts "$NODE_FULL_NAME"\
        --csr.hosts "$NODE_HOST" --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem\
        --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
    [ $LOG_LEVEL -ge 4 ] && set +x

    # TODO: check that source folders only contain one file, otherwise these will fail
    cp "$NODE_PATH/tls/tlscacerts/"* "$NODE_PATH/tls/ca.crt"
    cp "$NODE_PATH/tls/signcerts/"* "$NODE_PATH/tls/server.crt"
    cp "$NODE_PATH/tls/keystore/"* "$NODE_PATH/tls/server.key"

    mkdir -p $NODE_PATH/msp/tlscacerts
    cp "$NODE_PATH/tls/tlscacerts/"* "$NODE_PATH/msp/tlscacerts/tlsca.$ORG_NAME-cert.pem"

    #TODO workaround bug: ca certifications are stored under a wrong name; should be fixed in a cleaner way
    if [ $CA_NAME == '*.*' ]; then
      mv "$NODE_PATH/msp/cacerts/$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
        "$NODE_PATH/msp/cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem"
      mv "$NODE_PATH/tls/tlscacerts/tls-$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
        "$NODE_PATH/tls/tlscacerts/tls-$CA_HOST-$CA_PORT-$CA_NAME.pem"
    fi

    ((I++))
  done

  echo
  echo "Register org admin"
  echo
  [ $LOG_LEVEL -ge 4 ] && set -x
  fabric-ca-client register --caname "$CA_NAME" --id.name orgAdmin --id.secret orgAdminpw --id.type admin\
      --tls.certfiles $FABRIC_CA_SERVER_HOME/tls-cert.pem --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
  [ $LOG_LEVEL -ge 4 ] && set +x

  mkdir -p $FABRIC_CA_SERVER_HOME/msp/tlscacerts
  cp "$NODE_PATH/tls/tlscacerts/"* "$FABRIC_CA_SERVER_HOME/msp/tlscacerts/tlsca.$ORG_NAME-cert.pem"

  mkdir -p "$BASE_DIR/users/Admin@$ORG_NAME"

  [ $LOG_LEVEL -ge 4 ] && echo
  [ $LOG_LEVEL -ge 3 ] && echo "Generate org admin MSP"
  [ $LOG_LEVEL -ge 4 ] && echo
  [ $LOG_LEVEL -ge 4 ] && set -x
  fabric-ca-client enroll -u "https://orgAdmin:orgAdminpw@$CA_HOST:$CA_PORT" --caname "$CA_NAME"\
      -M "$BASE_DIR/users/Admin@$ORG_NAME/msp" --tls.certfiles "$FABRIC_CA_SERVER_HOME/tls-cert.pem"\
      --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
  [ $LOG_LEVEL -ge 4 ] && set +x

  cp "$FABRIC_CA_SERVER_HOME/msp/config.yaml" "$BASE_DIR/users/Admin@$ORG_NAME/msp/config.yaml"

  #TODO workaround bug: ca certifications are stored under a wrong name; should be fixed in a cleaner way
  if [ $CA_NAME == '*.*' ]; then
    mv "$BASE_DIR/users/Admin@$ORG_NAME/msp/cacerts/$CA_HOST-$CA_PORT-${CA_NAME//[.]/-}.pem" \
      "$BASE_DIR/users/Admin@$ORG_NAME/msp/cacerts/$CA_HOST-$CA_PORT-$CA_NAME.pem"
  fi
}

function renew (){
  exportGlobalParams
  exportOrgParams
  exportCaParams
  export FABRIC_CA_SERVER_HOME="$BASE_DIR/ca-server"

  I=1
  while [ $I -le $NODE_NUM ]; do
  exportNode"$I"Params
# ORG_NAME=${CHANNEL_ORGS[r]}
[ $LOG_LEVEL -ge 4 ] && echo
[ $LOG_LEVEL -ge 3 ] && echo "Renew order Certificates$I"
[ $LOG_LEVEL -ge 4 ] && echo
[ $LOG_LEVEL -ge 4 ] && set -x
  fabric-ca-client reenroll -u "https://orderer$I:orderer${I}pw@$CA_HOST:$CA_PORT"\
            --caname "$CA_NAME" -M "$NODE_PATH/msp" --tls.certfiles "$FABRIC_CA_SERVER_HOME/tls-cert.pem" \
            --loglevel "${FABRIC_LOGS[$LOG_LEVEL]}"
[ $LOG_LEVEL -ge 4 ] && set +x
((I++))
done
}
setupOrdererOrg