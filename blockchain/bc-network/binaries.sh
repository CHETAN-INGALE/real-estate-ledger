function getAll() {
    if ! command -v git &> /dev/null
    then
        echo
        echo "Installing git"
        sudo apt-get install git
        echo
        echo "----------------- Download git finished --------------------------"
        echo
    fi
    if ! command -v curl &> /dev/null
    then
        echo
        echo "Installing curl"
        sudo apt-get install curl
        echo
        echo "----------------- Download curl finished --------------------------"
        echo
    fi
    if ! command -v jq &> /dev/null
    then
        echo
        echo "Installing jq"
        sudo apt-get install jq
        echo
        echo "----------------- Download jq finished --------------------------"
        echo
    fi
}

function installPrerequisites {
    echo
    echo "The script will now install all prerequisites for the network to run"
    echo
    echo "Do you want to install git? WARNING: this will make use of sudo apt-get"
    read -p "Enter y or n to confirm your choice, or enter Y to allow all prerequisites to be installed " -n 1 -r
    echo
    if [ "$REPLY" = "Y" ] || [ "$REPLY" = "y" ]; then
        getAll
    fi
}

function downloadBinaries {
    PWD_OLD=$PWD

    DIR_="$(dirname "$(dirname "$(realpath "$BASH_SOURCE")")")"
    FILE="$DIR_/bin/configtxgen"

    #choose which version of the binaries should be downloaded
    FABRIC_BIN_VERSION=2.2.15
    FABRIC_CA_BIN_VERSION=1.4.7

    if [ ! -f "$FILE" ]; then
        echo
        echo "----------------- Downloading binaries - please wait... --------------------------"
        echo
        source "./binDownload.sh" "$FABRIC_BIN_VERSION" "$FABRIC_CA_BIN_VERSION"
        echo
        echo "----------------- Download binaries finished --------------------------"
        echo
    fi
    cd "$PWD_OLD"
}

function binariesMain {
    installPrerequisites
    downloadBinaries
}