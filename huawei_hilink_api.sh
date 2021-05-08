#!/bin/bash
#
# Huawei Hilink API
# =================
# - communication with Hilink devices via HTTP
# - send a standard http request with a xml formatted string to the device (default IP 192.169.8.1)
# - Howto:
#   o "source" this script in your own script from the command line
#   o if host ip/name differs, set "host=192.168.178.1" before calling any function
#   o if the device is locked by a password, set user="admin"; pw="1234secret"
#     _login is called automaticallcall
#     Password types 3 and 4 are supported
#   o if the SIM is requiring a PIN, set "pin=1234"
#   o connect device to network: _switchMobileData ON  ( or 1 )
#   o disconnect device: _switchMobileData OFF  ( or 0 )
#   o get informations about the device: _getDeviceInformation and _getStatus and _getNetProvider
#     all functions return XML formatted data in $response.
#   o Check if device is connected: "if _isConnected; then .... fi"
#   o $response can be parsed by calling _valueFromResponse 
#     e.g "_valueFromResponse msisdn" to get the phone number after a call to _getDeviceInformation
#
#
# Usage of functions 
#     - call the function with parameters (if required)
#     - return code: 0 - success; 1 - failed
#     - $status: status information (OK, ERROR)
#     - $response: xml response to be parsed for the required information
#
#
# required software: curl, base64, sha256sum, sed
#
#
# zbchristian 2021
#

# Initialization procedure
# ========================
#
# host="192.168.8.1"   	# ip address of device
# user="admin"         	# user name if locked (default admin)
# pw="1234Secret"      	# password if locked 
# pin="1234"			# PIN of SIM
# _initHilinkAPI		# initialize the API
#
# Termination
# ===========
# cleanup the API before quitting the shell
# _closeHilinkAPI

# initialize
function _initHilinkAPI() {
	if [ -z "$host" ]; then host="192.168.8.1"; fi
	if ! _hostReachable; then return 1; fi
	_sessToken
	_login
	return $?
}

# Cleanup
function _closeHilinkAPI() {
	if [ -z "$host" ]; then host="192.168.8.1"; fi
	if ! _hostReachable; then return 1; fi
	_logout
	tokenlist=""
	sessID=""
	token=""
	return 0
}

# get status (connection status, DNS, )
# parameter: none
function _getStatus() {
    if _login; then
        if _sendRequest "api/monitoring/status"; then
		if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
	fi
        return $?
    else
        return 1
    fi
}

function _isConnected() {
	conn=$(_getStatus "connectionstatus")
	status="NO"
	if [ ! -z "$conn" ] && [ $conn -eq 901 ]; then
		status="YES"
		return 0
	fi
	return 1
}

# get device information (device name, imei, imsi, msisdn-phone number, MAC, WAN IP ...)
# parameter: none
function _getDeviceInformation() {
    if _login; then 
        if _sendRequest "api/device/information"; then
		if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
	fi
        return $?
    else
        return 1
    fi
}

# get net provider information 
# parameter: none
function _getNetProvider() {
    if _login; then 
        if _sendRequest "api/net/current-plmn"; then
		if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
	fi
        return $?
    else
        return 1
    fi
}

# get signal level
# parameter: none
function _getSignal() {
    if _login; then
        if _sendRequest "api/device/signal"; then
		if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
	fi
        return $?
    else
        return 1
    fi
}

# get status of mobile data connection
# parameter: none
function _getMobileDataStatus() {
    if _login; then
        if _sendRequest "api/dialup/mobile-dataswitch"; then
                status=$(_valueFromResponse "dataswitch")
                if [ $? -eq 0  ] && [ ! -z "$status" ]; then echo "$status"; fi
        fi
        return $?
    else
        return 1
    fi
}


# PIN of SIM can be passed either as $pin, or as parameter
# parameter: PIN number of SIM card
function _enableSIM() {
#SimState:
#255 - no SIM,
#256 - error CPIN,
#257 - ready,
#258 - PIN disabled,
#259 - check PIN,
#260 - PIN required,
#261 - PUK required
    if [ ! -z "$1" ]; then pin="$1"; fi
    if ! _login; then return 1; fi
    if _sendRequest "api/pin/status"; then
        simstate=`echo $response | sed  -rn 's/.*<simstate>([0-9]*)<\/simstate>.*/\1/pi'`
        if [[ $simstate -eq 257  ]]; then status="SIM ready"; return 0; fi
        if [[ $simstate -eq 260  ]]; then 
   		status="PIN required"
     		if [ ! -z "$pin" ]; then _setPIN "$pin"; fi
		return $?
	fi
        if [[ $simstate -eq 255  ]]; then status="NO SIM"; return 1; fi
    fi
    return 1
}

# helper function to parse $response (xml format) for a value 
# call another function first!
# parameter: tag-name
function _valueFromResponse() {
    if [ -z "$response" ] || [ -z "$1" ]; then return 1; fi
    par="$1"
    value=`echo $response | sed  -rn 's/.*<'$par'>(.*)<\/'$par'>.*/\1/pi'`
    if [ -z "$value" ]; then return 1; fi   
    echo "$value"
    return 0
}

# obtain session and verification token - stored in vars $sessID and $token 
# parameter: none
function _sessToken() {
    response=$(curl -s http://$host/api/webserver/SesTokInfo -m 5 2> /dev/null)
    if [ -z "$response" ]; then echo "No access to device at $host"; return 1; fi
    status=$(echo "$response" | sed  -nr 's/.*<code>([0-9]*)<\/code>.*/\1/ip')
    if [ -z "$status" ]; then
        token=`echo $response | sed  -r 's/.*<TokInfo>(.*)<\/TokInfo>.*/\1/'`
        sessID=`echo $response | sed  -r 's/.*<SesInfo>(.*)<\/SesInfo>.*/\1/'`
        if [ ! -z "$sessID" ] &&  [ ! -z "$token" ]; then 
            sessID="SessionID=$sessID"
            return 0
        fi
    fi
    return 1
}

# unlock device (if locked) with user name and password
# requires stored user="admin"; pw="1234secret";host="192.168.8.1" 
# parameter: none
function _login() {
#    _sessToken  # this starts a new session
    if _loginState; then return 0; fi    # login not required, or already done
    _sessToken
    # get password type
    if ! _sendRequest "api/user/state-login"; then return 1; fi
    pwtype=$(echo "$response" | sed  -rn 's/.*<password_type>([0-9])<\/password_type>.*/\1/pi')
    if [ -z "$pwtype" ];then pwtype=4; fi   # fallback is type 4
    if [[ ! -z "$user" ]] && [[ ! -z "$pw" ]]; then
            # password encoding
            # type 3 : base64(pw) encoded
            # type 4 : base64(sha256sum(user + base64(sha256sum(pw)) + token))
            pwtype3=$(echo -n "$pw" | base64 --wrap=0)
            hashedpw=$(echo -n "$pw" | sha256sum -b | sed -nr 's/^([0-9a-z]*).*$/\1/ip' )
            hashedpw=$(echo -n "$hashedpw" | base64 --wrap=0)
            pwtype4=$(echo -n "$user$hashedpw$token" | sha256sum -b | sed -nr 's/^([0-9a-z]*).*$/\1/ip' )
            encpw=$(echo -n "$pwtype4" | base64 --wrap=0)
            if [ $pwtype -ne 4 ]; then encpw=$pwtype3; fi
            xmldata="<?xml version='1.0' encoding='UTF-8'?><request><Username>$user</Username><Password>$encpw</Password><password_type>$pwtype</password_type></request>"
            xtraopts="--dump-header /tmp/hilink_login_hdr.txt"
            rm -f /tmp/hilink_login_hdr.txt
            _sendRequest "api/user/login"
            if [ ! -z "$status" ] && [ "$status" = "OK" ]; then 
		tokenlist=( $(cat /tmp/hilink_login_hdr.txt | sed -rn 's/^__RequestVerificationToken:\s*([0-9a-z#]*).*$/\1/pi' | sed 's/#/ /g') )
		_getToken
                sessID=$(cat /tmp/hilink_login_hdr.txt  | grep -ioP 'SessionID=([a-z0-9]*)')
                if [ ! -z "$sessID" ] &&  [ ! -z "$token" ]; then
                   return 0 
                fi
            fi
    fi
    return 1
}

# logout of hilink device
# parameter: none
function _logout() {
	if _loginState; then 
	        xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><Logout>1</Logout></request>"
	        if _sendRequest "api/user/logout"; then 
			tokenlist=""
			sessID=""
			token=""
		fi
        	return $?
	fi
	return 1
}

# parameter: none
function _loginState() {
   _sendRequest "api/user/hilink_login"
   state=$(echo $response | sed  -rn 's/.*<hilink_login>(.*)<\/hilink_login>.*/\1/pi')
   if [ ! -z "$state" ] && [ $state -eq 0 ]; then       # no login enabled
        return 0
   fi
   _sendRequest "api/user/state-login"
   state=`echo "$response" | sed  -rn 's/.*<state>(.*)<\/state>.*/\1/pi'`
   if [ ! -z "$state" ] && [ $state -eq 0 ]; then       # already logged in
        return 0
   fi
   return 1
}

# switch mobile data on/off  1/0
# if SIM is locked, $pin has to be set
# parameter: state - ON/OFF or 1/0
function _switchMobileData() {
    if [ -z "$1" ]; then return 1; fi
    _login
    mode="${1,,}"
    [ "$mode" = "on" ] && mode=1
    [ "$mode" = "off" ] && mode=0
    if [[ $mode -ge 0 ]]; then
        if _enableSIM "$pin"; then
            xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><dataswitch>$mode</dataswitch></request>"
            _sendRequest "api/dialup/mobile-dataswitch"
            return $?
        fi
    fi
    return 1
}

# parameter: PIN of SIM card
function _setPIN() {
    if [ -z "$1" ]; then return 1; fi
    pin="$1"
    xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><OperateType>0</OperateType><CurrentPin>$pin</CurrentPin><NewPin></NewPin><PukCode></PukCode></request>"
    _sendRequest "api/pin/operate"
    return $?
}

# Send request to host at http://$host/$apiurl
# data in $xmldata and options in $xtraopts
# parameter: apiurl (e.g. "api/user/login")
function _sendRequest() {
    status="ERROR"
    if [ -z "$1" ]; then return 1; fi 
    apiurl="$1"
    ret=1
    if [ -z "$sessID" ] || [ -z "$token" ]; then _sessToken; fi 
    if [ -z "$xmldata" ];then
        response=$(curl -s http://$host/$apiurl -m 10 \
                     -H "Cookie: $sessID")
    else 
        response=$(curl -s -X POST http://$host/$apiurl -m 10 \
                    -H "Content-Type: text/xml"  \
                    -H "Cookie: $sessID" \
                    -H "__RequestVerificationToken: $token" \
                    -d "$xmldata" $xtraopts 2> /dev/null)
	_getToken
    fi
    if [ ! -z "$response" ];then 
        response=$(echo $response | tr -d '\012\015') # delete newline chars 
        status=$(echo "$response" | sed  -nr 's/.*<code>([0-9]*)<\/code>.*/\1/ip') # check for error code
        if [ -z "$status" ]; then
            status="OK"
            response=$(echo "$response" | sed  -nr 's/.*<response>(.*)<\/response>.*/\1/ip')
            [ -z "$response" ] && response="none"
            ret=0
        else
            status="ERROR $status"
        fi
    else
        status="ERROR"
    fi
    xtraopts=""
    xmldata=""
    return $ret
}

# handle the list of tokens available after login
# parameter: none
function _getToken() {
	if [ ! -z "$tokenlist" ] && [ ${#tokenlist[@]} -gt 0 ]; then
		token=${tokenlist[0]}		# get first token in list
		tokenlist=("${tokenlist[@]:1}")	# remove used token from list
		if [ ${#tokenlist[@]} -eq 0 ]; then
			_logout		# use the last token to logout
		fi
	fi
}

function _hostReachable() {
	avail=`timeout 0.5 ping -c 1 $host | sed -rn 's/.*time=.*/1/p'`
	if [ -z "$avail" ]; then return 1; fi
	return 0;
}


host="192.168.8.1"
user="admin"
pw=""
token=""
sessID=""
xmldata=""
xtraopts=""
response=""
status=""
pwtype=-1


