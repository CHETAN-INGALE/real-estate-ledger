
# Copyright IBM Corp. All Rights Reserved.
#
# SPDX-License-Identifier: Apache-2.0
#
    
#!/bin/bash
    
ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"
CC_DIR="$ROOT/../chaincode"
    
# CHANGE TO exportChaincodeParams ONCE WE HANDLE CC PROPERLY
  
exportChaincode1Params () {
  # CC params
  export CC_NAME='fabcar'
  export CC_INDEX='1'
  export CC_VERSION='1.0'
  export CC_SEQUENCE='1'
  export CC_SRC_PATH="$CC_DIR/fabcar"
  export CC_PKG_NAME="$CC_SRC_PATH/$CC_NAME.tar.gz"
  export CC_LANG='node'
  export CC_LABEL="$CC_NAME-$CC_VERSION"
  export INIT_REQUIRED='true'
  export INIT_FUNCTION_NAME='initLedger'
  export CHANNEL_LIST=(channel1)
  CHANNEL_DEPLOYED=()
}
  