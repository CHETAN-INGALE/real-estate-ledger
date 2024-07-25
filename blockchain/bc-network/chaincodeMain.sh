
#!/bin/bash
#
# Copyright IBM Corp All Rights Reserved
#
# SPDX-License-Identifier: Apache-2.0
#
    
# the absolute path where this file is
export ROOT="$(dirname "$(realpath "$BASH_SOURCE")")"
# prepending $ROOT/../bin to PATH to ensure we are picking up the correct binaries
# this may be commented out to resolve installed version of tools if desired
export PATH="$ROOT/../bin":$PATH
export VERBOSE=false
    
# avoid docker-compose warning about orphan containers
export COMPOSE_IGNORE_ORPHANS=True
    
# contains model-specific configurations and variables
source "$ROOT/globalParams.sh"
exportNetworkParams
    
CLIENT_CA_relpath='tls/ca.crt'
PATH="$ROOT/../bin":$PATH
    
source "$ROOT/globalParams.sh"
source "$ROOT/customChaincodeParams.sh"
source "$ROOT/scripts/customChaincode.sh"
    
export CC_INDEX='1' # default chaincode, can be overwritten with -c flag
    
printHelp() {
    echo "This script manages custom chaincode operations for this network"
    echo
    echo "Usage: chaincodeMain.sh [OPTS] MODE [PARAMS]"
    echo "MODE:"
    echo "  invoke    invoke the specified chaincode (usage: invoke cc_method [params])"
    echo "  query     query the ledger using the specified chaincode (usage: query cc_method [params])"
   echo "OPTS (default values in globalParams.sh or customChaincodeParams.sh:"
    echo "  -h        print this help message"
    echo "  -c <n>    index identifying the chaincode in customChaincodeParams.sh (default: 1)"
    echo "  -l <n>    set verbosity: 1->error,2->warning,3->info,4->debug,5->trace"
    echo "  -p <p>    peer that performs the operation, in ORG.NODE format (default: CC_ORG1_NODE1)"
    echo "  -v        verbose output: same as -l 4"
    echo
}
    
if [[ $# -lt 1 ]] ; then
    printHelp
    exit 0
fi
    
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
    -c) # default 1
    export CC_INDEX="$2"
    shift
    ;;
    -p) # peer performing the operation, defaults to CC_ORG1_NODE1
    # TODO: chech that this node is indeed configured for this chaincode
    IFS=. read -ra DATA <<< "$2"
    [ ${#DATA[@]} -ne 2 ] && echo "peer must be provided in NODE.ORG format" && exit 1
    export NODE="${DATA[0]}"
    export ORG="${DATA[1]}"
    [ $LOG_LEVEL -ge 3 ] && echo "Using $NODE from organization $ORG"
    shift
    ;;
    deploy|query|invoke)
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
    
# TO DO: improve log messages
if [ "$MODE" == "deploy" ]; then
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 2 ] && echo "Deploying chaincode"
    deployCC
elif [ "$MODE" == "invoke" -o "$MODE" == "query" ]; then
    [ $LOG_LEVEL -ge 2 ] && echo
    [ $LOG_LEVEL -ge 2 ] && echo "calling chaincode invoke handler"
    [ $LOG_LEVEL -ge 2 ] && echo
    interactCC
else
    printHelp
    exit 1
fi
