#!/bin/bash
#
# Example to utilize github.com/zbchristian/huawei_hilink_api
# ===========================================================
# - switch on/off the device and enable mobile data
# - display the device name and connection mode
#
# Parameter: on 
#            off
#
# zbchristian 2021
#

# import the API functions
source huawei_hilink_api.sh

# initialialize required variables
host="192.168.8.1"  # ip-address of the device (default 192.168.8.1)
user="admin"        # user name in case of a locked device (default admin)
pw="1234Secret"     # password in case of a locked device
pin="1234"          # PIN of the SIM

# initialize the API
if ! _initHilinkAPI; then echo "Init failed - return status: $status"; exit; fi

shopt -s nocasematch
if [ -z "$1" ] || [[ $1 =~ ^on$ ]]; then
    if _isConnected; then 
        echo "Device is already connected"
    else
        echo "Connect the device"
        _switchMobileData ON
        sleep 3 # wait a bit for the device to connect
    fi
    if _getDeviceInformation; then  # extract device informations
        # echo $response # display all available informations (XML format)
        name=$(_valueFromResponse "devicename")
        mode=$(_valueFromResponse "workmode")
    fi
    operator=$(_getNetProvider "fullname")  # get the name of the network provider
    # _keyValuePairs # display all available informations as key value pairs (from $response)

    echo "Device $name connected to $operator in $mode mode"
else 
    if _isConnected; then
        echo "Disconnect the device"
        _switchMobileData OFF
    else
        echo "Device is not connected"
    fi
fi

# cleanup the API before quitting the shell
_closeHilinkAPI

echo "Thats it ... exit"


