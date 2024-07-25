#!/bin/bash

ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"
CC_DIR="$ROOT/../chaincode"


# number of chaincodes to install in this network


exportChaincode1Params () {
  export CC_NAME='default_cc'
  export CC_VERSION='1.0'
  export CC_SEQUENCE='1'
  export CC_SRC_PATH="$CC_DIR/default_cc"
  export CC_PKG_NAME="$CC_SRC_PATH/$CC_NAME.tar.gz"
  export CC_LANG='node'
  export CC_LABEL="$CC_NAME-$CC_VERSION"
  export INIT_REQUIRED='true'
}