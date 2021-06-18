# Bash script based API for Huawei Hilink Mobile Data Devices
A lot of USB data devices (e.g. E3372H-320) from Huawei contain a router and a web interface (Hilink device). These devices 
include a DHCP server and show up as an ethernet port (e.g. eth1).
The communication utilizes HTTP as the communication protocol.

The API allows to 
* Log into the device
* unlock the SIM card
* connect/disconnect to the network
* retrieve informations about the device and network connection (e.g. signal strength)

The default parameters of these devices are:
* IP-Address: `192.168.8.1`
* user name: `admin`
* no password for the access is set

# Example script
The example `example_huawei_hilink.sh` has to be called with a single parameter `on` or `off`. The script opens the API, connects or disconnects to/from the network and, in case of a connection, prints an information about the device and the connection. The API is terminated at the end of the script.

## The Protocol
Since HTTP is used for the communication, each API call correspond to a specific URL.

Example: A `GET` request to `http://192.168.8.1/api/webserver/SesTokInfo` will return a `SessionID` and an access token.
These are required for the communication with the API. To retrieve informations only the `SessionID` is required. To send values  (a request) to the device, or trigger an action, in addition the access token is required.

All parameters and return values to and from the device are passed as XML data.
* Requests have the following form: `<?xml version='1.0' encoding='UTF-8'?><request> ... </request>`   
* Response by the device: `<?xml version='1.0' encoding='UTF-8'?><response> ... </response>`

If a login is required, the communication is more complex, since the device returns after a succesful login a list with 30 access tokens. Each of these tokens can only be used once.   

# The Bash API
The bash script `huawei_hilink_api.sh` contains all required functions to communicate with a Hilink device. Login, logout, enabling the SIM card and managing the access tokens. All this is hidden from the user. For example a call to the function `_switchMobileData on` in your script will automatically perform the authentification in the background. For this to work, an initialization of the API is required:
```
$ source huawei_hilink_api.sh
$ hilink_host="192.168.8.1"
$ hilink_password="1234Secret"
$ hilink_pin="1234"
$ if ! _initHilinkAPI; then 
$    echo "Failed - return code $status"
$    exit
$ fi
```

The first line imports all functions of the API into the running shell. If the default ip-address is correct, the variable `hilink_host` is not necessary. If the web GUI of the device is not locked, no password is required. In case the SIM card is not locked with a PIN, no PIN is required.

After the initialization, all functions of the API can be called.
Examples:

```
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
```
All function return a value of 0, if the call was successful or 1, if it failed. The status is available in `$status` and the return value in `$response`.

To retrieve a value from the returned XML data (stored in `$response`), a call to `_valueFromResponse` can be used. Example: 
after `_getSignal` a call to `_valueFromResponse "rssi"` will return the value of the signal level. If only a single parameter is needed, the name can be passed to the function: `_getSignal "rssi"`.

After the communcation has been done, the API should be terminated by 
```
$ _closeHilinkAPI
```
This ensures, that the session is closed and access tokens are cleared. The option `save` allows to save the session data to a file and resume with the next call to `_initHilinkAPI`. This only works for the next minute. 
This is recommended, if multiple calls within a short time are foreseen.

Be aware, that each shell script runs in a separate environment. You need to close the API before leaving the script. Otherwise the communication might still be open and a new access is blocked for a while!

## Available functions

* `_initHilinkAPI` - initialize the API 
* `_closeHilinkAPI` - cleanup and logout
* `_switchMobileData` - login in, connect to the network and enable/disable mobile data (parameter `on` or `off`) 
* `_getMobileDataStatus` - status of the mobile data connection 
* `_isConnected` - return 0 if connected, 1 if not
* `_getStatus` - get device status informations
* `_getDeviceInformation` - get device informations (name ...)
* `_getNetProvider` - information about the current network provider
* `_getSignal` - get signal information (rssi and more)
* `_getAllInformations` - get device, provider and signal informations and output key/values as text
* `_enableSIM` - enable the SIM. Will call `_setPIN`, if locked
* `_loginState` - returns 0, if session is logged in, or no login required. Otherwise 1 is returned
* `_setPIN` - set the PIN of the SIM card. Parameter is the PIN number
* `_sendRequest` - send a request to the device (ip-address in `$host`). Parameter is the path of the request (e.g. `_sendRequest "api/monitoring/status"`)
* `_login` - unlock the API, if a password is set
* `_logout` - log out of the API
* `_sessToken` - get a session id and request token
* `_getToken` - get the next token in the list. Is called by `_sendRequest` in order to get the next request token
* `_valueFromResponse` - parse the xml formatted response (`$response`) for a certain key and extract the value
* `_keysFromResponse` - retrieve the list of keys of the last response 
* `_keyValuePairs` - retrieve list of key=value pairs (e.g. `DeviceName="E3372h-320" ...` after a call to `_getDeviceInformation`) from the last response
* `_hostReachable` - check if the currently defined host is reachable


## Direct communication with the device
The function `_sendRequest` allows to call directly the Hilink device. The parameter is the URL path of the corresponding function. Example `_sendRequest "api/monitoring/status"`. The return value is 0 if successful and 1 if it failed. To send a request, the corresponding XML data are required in `$hilink_xmldata`. The response is retuned in `$response` and the status of the call in `$status`.

