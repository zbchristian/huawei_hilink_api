# Bash script based API for Huawei Hilink Mobile Data Devices
A lot of USB data devices (e.g. E3372H-320) from Huawei contain a router and an web interface (Hilink device). These devices 
include a DHCP server and show up as an ethernet port (e.g. eth1).
The communication utilizes HTTP as the protocol.

The API allows to 
* Log into the device
* unlock the SIM card
* connect/disconnect to the network
* retrieve informations about the device and network connection (e.g. signal strength)

The default parameters of these devices are:
* IP-Address: ´192.168.8.1´
* user name: ´admin´
* no password for the access is set

## The Protocol
Since HTTP is used for the communication, each API call correspond to an HTTP address.

Example: A ´GET´ request to ´http://192.168.8.1/api/webserver/SesTokInfo´ will return a ´SessionID´ and an access token.
These are required for the communication with the API. To retrieve informations only the ´SessionID´ is required. To send values  (a request) to the device, or trigger an action, in addition the access token is required.

All parameters and return values to and from the device are passed as XML data.
* Requests have the following form: ´<?xml version='1.0' encoding='UTF-8'?><request> ... </request>´   
* Response by the device: ´<?xml version='1.0' encoding='UTF-8'?><response> ... </response>´

If a login is required, the communication is more complex, since the device returns after a succesful login a list with 30 access tokens. Each of these tokens can only be used once.   

# The Bash API
The bash script ´huawei_hilink_API.sh´ contains all required functions to communicate with a Hilink device. Login, logout, enabling the SIM card and managing the access tokens is hidden from the user. Just call the function ´_switchMobileData on´ in your script and the rest happens in the background. For this to work, an initialization of the API is required:
´´´
$ source huawei_hilink_API.sh
$ host="192.168.8.1"
$ pw="1234Secret"
$ pin="1234"
$ if ! _initHilinkAPI; then 
$    echo "Failed - return code $status"
$    exit
$ fi
´´´

The first line imports all functions of the API into the running shell. If the default ip-address is correct, the variable ´host´ is not necessary. If the web GUI of the device is not locked, no password is required. In case the SIM card is not locked with a PIN, no PIN is required.

After the initialization, all functions of the API can be called.
Examples:

´´´
$ _switchMobileData on
$ sleep 3
$ if _isConnected; then
	echo "Device is connected"
$ fi
$ _getDeviceInformation
$ echo $response
$ _getSignal
$ echo $response
$ _getNetProvider "fullname"
´´´
All function return a value of 0, if the call was successful or 1, if it failed. The status is available in ´$status´ and the return value in ´$response´.

After the communcation has been done, the API should be terminated by 
´´´
$ _closeHilinkAPI
´´´
This ensures, that the session is closed and access tokens are cleared.

Be aware, that each shell script runs in a separate shell environment. You need to close the API before leaving the script. Otherwise the communication might still be open and a new access is blocked for a while!

## Available functions

## Direct communication with the device
The function ´_sendRequest´ allows to call directly the Hilink device. the parameter is the path of the corresponding function. Example ´_sendRequest "api/monitoring/status´. The return value is 0 if successful and 1 if it failed. To send a request, the corresponding XML data are required in ´$xmldata´. The response is retuned in ´$response´ and the status of the call in ´$status´.

# Example script
The example ´example_huawei_hilink.sh´ has to be called with a single parameter ´on´ or ´off´. The script opens the API, connects or disconnects to/from the network and, in case of a connection, prints an information about the device and the connection. The API is terminated at the end of the script.

