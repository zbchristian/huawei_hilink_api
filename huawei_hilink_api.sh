#!/bin/bash
#
# Huawei Hilink API
# =================
# - communication with Hilink devices via HTTP
# - send a standard http request with a xml formatted string to the device (default IP 192.169.8.1)
# - Howto:
#   o "source" this script in your own script from the command line
#   o if host ip/name differs, set "host=192.168.178.1" before calling any function
#   o if the device is locked by a password, set user="admin"; password"1234secret"
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
# host=192.168.8.1      # ip address of device
# user="admin"          # user name if locked (default admin)
# password"1234Secret"       # password if locked 
# pin="1234"            # PIN of SIM
# _initHilinkAPI        # initialize the API
#
# Termination
# ===========
# cleanup the API before quitting the shell 
# _closeHilinkAPI  (optional: add parameter "save" to save the session/token data for subsequent calls. Valid for a few minutes.)
#
# BE AWARE, THAT THE API USES SOME GLOBAL VARIABLES : host, user, password, pin, response, status
# USE THESE ONLY TO COMMUNICATE WITH THE API.
# DO NOT USE THE VARIABLE PRE_FIX "hilink_" FOR YOUR OWN VARIABLES
#

hilink_host_default="192.168.8.1"
hilink_save_file="/tmp/hilink_api_saved.dat"
hilink_save_age=60
hilink_header_file="/tmp/hilink_login_hdr.txt"

# initialize
function _initHilinkAPI() {
    if [ -z "$host" ]; then host=$hilink_host_default; fi
    if ! _hostReachable; then return 1; fi
    if [ -f $hilink_save_file ]; then # found file with saved data
        _getSavedData
        local age=$(( $(date +%s) - $(stat $hilink_save_file  -c %Y) ))
        if [[ $age -gt $hilink_save_age ]]; then 
            rm -f $hilink_save_file
            _logout
            _sessToken
        fi
    fi
    if [ -z "$hilink_sessID" ] || [ -z "$hilink_token" ]; then _sessToken; fi
    _login
    return $?
}

function _getSavedData() {
    if [ -f $hilink_save_file ]; then  # restore saved session data
        local dat=$(cat $hilink_save_file)
        hilink_sessID=$(echo "$dat" | sed -nr 's/sessionid: ([a-z0-9]*)/\1/ip')
        hilink_token=$(echo "$dat" | sed -nr 's/token: ([a-z0-9]*)/\1/ip')
        hilink_tokenlist=( $(echo "$dat" | sed -nr 's/tokenlist: ([a-z0-9 ]*)/\1/ip') )
    fi
}

# Cleanup
# parameter: "save" - will store sessionid and tokens in file
function _closeHilinkAPI() {
    if [ -z "$host" ]; then host=$hilink_host_default; fi
    if ! _hostReachable; then return 1; fi
    rm -f $hilink_save_file
    [ ! -z "$1" ] && local opt="${1,,}"
    if [ ! -z "$opt" ] && [ "$opt" = "save" ]; then
        echo "sessionid: $hilink_sessID" > $hilink_save_file
        echo "token: $hilink_token" >> $hilink_save_file
        echo "tokenlist: ${hilink_tokenlist[@]}" >> $hilink_save_file
    fi
    _logout
    hilink_tokenlist=""
    hilink_sessID=""
    hilink_token=""
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
    fi
    return 1
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
# parameter: name of parameter to return
function _getDeviceInformation() {
    if _login; then 
        if _sendRequest "api/device/information"; then
            if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
        fi
        return $?
    fi
    return 1
}

# get net provider information 
# parameter: name of parameter to return 
function _getNetProvider() {
    if _login; then 
        if _sendRequest "api/net/current-plmn"; then
            if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
        fi
        return $?
    fi
    return 1
}

# get signal level
# parameter: name of parameter to return
function _getSignal() {
    if _login; then
        if _sendRequest "api/device/signal"; then
            if [ ! -z "$1" ]; then _valueFromResponse "$1"; fi
        fi
        return $?
    fi
    return 1
}

function _getAllInformations() {
    if _getDeviceInformation; then _keyValuePairs; fi
    if _getSignal; then _keyValuePairs; fi
    if _getNetProvider; then _keyValuePairs; fi
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
    fi
    return 1
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
        local simstate=`echo $response | sed  -rn 's/.*<simstate>([0-9]*)<\/simstate>.*/\1/pi'`
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

# obtain session and verification token - stored in vars $hilink_sessID and $token 
# parameter: none
function _sessToken() {
    hilink_tokenlist=""
    hilink_token=""
    hilink_sessID=""
    response=$(curl -s http://$host/api/webserver/SesTokInfo -m 5 2> /dev/null)
    if [ -z "$response" ]; then echo "No access to device at $host"; return 1; fi
    status=$(echo "$response" | sed  -nr 's/.*<code>([0-9]*)<\/code>.*/\1/ip')
    if [ -z "$status" ]; then
        hilink_token=`echo $response | sed  -r 's/.*<TokInfo>(.*)<\/TokInfo>.*/\1/'`
        hilink_sessID=`echo $response | sed  -r 's/.*<SesInfo>(.*)<\/SesInfo>.*/\1/'`
        if [ ! -z "$hilink_sessID" ] &&  [ ! -z "$hilink_token" ]; then 
            hilink_sessID="SessionID=$hilink_sessID"
            return 0
        fi
    fi
    return 1
}

# unlock device (if locked) with user name and password
# requires stored user="admin"; password"1234secret";host=$hilink_host_default 
# parameter: none
function _login() {
    if _loginState; then return 0; fi    # login not required, or already done
    _sessToken
    # get password type
    if ! _sendRequest "api/user/state-login"; then return 1; fi
    local pwtype=$(echo "$response" | sed  -rn 's/.*<password_type>([0-9])<\/password_type>.*/\1/pi')
    if [ -z "$pwtype" ];then local pwtype=4; fi   # fallback is type 4
	local ret=1
    if [[ ! -z "$user" ]] && [[ ! -z "$password" ]]; then
        # password encoding
        # type 3 : base64(pw) encoded
        # type 4 : base64(sha256sum(user + base64(sha256sum(pw)) + token))
        local pwtype3=$(echo -n "$password" | base64 --wrap=0)
        local hashedpw=$(echo -n "$password" | sha256sum -b | sed -nr 's/^([0-9a-z]*).*$/\1/ip' )
        local hashedpw=$(echo -n "$hashedpw" | base64 --wrap=0)
        local pwtype4=$(echo -n "$user$hashedpw$hilink_token" | sha256sum -b | sed -nr 's/^([0-9a-z]*).*$/\1/ip' )
        local encpw=$(echo -n "$pwtype4" | base64 --wrap=0)
        if [ $pwtype -ne 4 ]; then local encpw=$pwtype3; fi
        hilink_xmldata="<?xml version='1.0' encoding='UTF-8'?><request><Username>$user</Username><Password>$encpw</Password><password_type>$pwtype</password_type></request>"
        hilink_xtraopts="--dump-header $hilink_header_file"
        rm -f $hilink_header_file
        _sendRequest "api/user/login"
        if [ ! -z "$status" ] && [ "$status" = "OK" ]; then 
            # store the list of 30 tokens. Each token is valid for a single request
            hilink_tokenlist=( $(cat $hilink_header_file | sed -rn 's/^__RequestVerificationToken:\s*([0-9a-z#]*).*$/\1/pi' | sed 's/#/ /g') )
            _getToken
            hilink_sessID=$(cat $hilink_header_file  | grep -ioP 'SessionID=([a-z0-9]*)')
            if [ ! -z "$hilink_sessID" ] &&  [ ! -z "$hilink_token" ]; then local ret=0; fi
        fi
        rm -f $hilink_header_file
    fi
    return $ret
}

# logout of hilink device
# parameter: none
function _logout() {
    if _loginState; then 
        hilink_xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><Logout>1</Logout></request>"
        if _sendRequest "api/user/logout"; then 
            hilink_tokenlist=""
            hilink_sessID=""
            hilink_token=""
			login_enabled=""
        fi
        return $?
    fi
    return 1
}

# parameter: none
function _loginState() {
	status="OK"
	if [ -z "$login_enabled" ]; then _checkLoginEnabled; fi
	if [ $login_enabled -eq 1 ]; then return 0; fi # login is disabled
	_sendRequest "api/user/state-login"
	state=`echo "$response" | sed  -rn 's/.*<state>(.*)<\/state>.*/\1/pi'`
	if [ ! -z "$state" ] && [ $state -eq 0 ]; then       # already logged in
		return 0
	fi
	return 1
}

function _checkLoginEnabled() {
    if _sendRequest "api/user/hilink_login"; then
		login_enabled=0
		local state=$(echo $response | sed  -rn 's/.*<hilink_login>(.*)<\/hilink_login>.*/\1/pi')
		if [ ! -z "$state" ] && [ $state -eq 0 ]; then       # no login enabled
			login_enabled=1
		fi
	else
		login_enabled=""
	fi
}

# switch mobile data on/off  1/0
# if SIM is locked, $pin has to be set
# parameter: state - ON/OFF or 1/0
function _switchMobileData() {
    if [ -z "$1" ]; then return 1; fi
    _login
    local mode="${1,,}"
    [ "$mode" = "on" ] && local mode=1
    [ "$mode" = "off" ] && local mode=0
    if [[ $mode -ge 0 ]]; then
        if _enableSIM "$pin"; then
            hilink_xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><dataswitch>$mode</dataswitch></request>"
            _sendRequest "api/dialup/mobile-dataswitch"
            return $?
        fi
    fi
    return 1
}

# parameter: PIN of SIM card
function _setPIN() {
    if [ -z "$1" ]; then return 1; fi
    local pin="$1"
    hilink_xmldata="<?xml version: '1.0' encoding='UTF-8'?><request><OperateType>0</OperateType><CurrentPin>$pin</CurrentPin><NewPin></NewPin><PukCode></PukCode></request>"
    _sendRequest "api/pin/operate"
    return $?
}

# Send request to host at http://$host/$apiurl
# data in $hilink_xmldata and options in $hilink_xtraopts
# parameter: apiurl (e.g. "api/user/login")
function _sendRequest() {
    status="ERROR"
    if [ -z "$1" ]; then return 1; fi 
    local apiurl="$1"
    local ret=1
    if [ -z "$hilink_sessID" ] || [ -z "$hilink_token" ]; then _sessToken; fi 
    if [ -z "$hilink_xmldata" ];then
        response=$(curl -s http://$host/$apiurl -m 10 \
                     -H "Cookie: $hilink_sessID")
    else 
        response=$(curl -s -X POST http://$host/$apiurl -m 10 \
                    -H "Content-Type: text/xml"  \
                    -H "Cookie: $hilink_sessID" \
                    -H "__RequestVerificationToken: $hilink_token" \
                    -d "$hilink_xmldata" $hilink_xtraopts 2> /dev/null)
        _getToken
    fi
    if [ ! -z "$response" ];then 
        response=$(echo $response | tr -d '\012\015') # delete newline chars 
        status=$(echo "$response" | sed  -nr 's/.*<code>([0-9]*)<\/code>.*/\1/ip') # check for error code
        if [ -z "$status" ]; then
            status="OK"
            response=$(echo "$response" | sed  -nr 's/.*<response>(.*)<\/response>.*/\1/ip')
            [ -z "$response" ] && response="none"
            local ret=0
        else
            status="ERROR $status"
        fi
    else
        status="ERROR"
    fi
    if [[ "$status" =~ ERROR ]]; then _handleError; fi
    hilink_xtraopts=""
    hilink_xmldata=""
    return $ret
}

# handle the list of tokens available after login
# parameter: none
function _getToken() {
    if [ ! -z "$hilink_tokenlist" ] && [ ${#hilink_tokenlist[@]} -gt 0 ]; then
        hilink_token=${hilink_tokenlist[0]}       # get first token in list
        hilink_tokenlist=("${hilink_tokenlist[@]:1}") # remove used token from list
        if [ ${#hilink_tokenlist[@]} -eq 0 ]; then
            _logout     # use the last token to logout
        fi
	else
		_sessToken		# old token has been used - need new session
    fi
}

# Analyse $status for error code
# return error text in $status
function _handleError() {
    local txt=$(_getErrorText)
    if [ -z "$code" ]; then return 1; fi
    local ret=0
    case "$code" in
        101|108003|108007)
            local ret=1
            status="$txt"
            ;;
        108001|108002|108006)
            local ret=1
            status="$txt"
            ;;
        125001|125002|125003)
            _sessToken
            local ret=0
            ;;
        *)
            ;;
    esac
    return "$ret"
}

declare -A hilink_err_api
hilink_err_api[101]="Unable to get session ID/token"
hilink_err_api[108001]="Invalid username/password"
hilink_err_api[108002]=${hilink_err_api[108001]}
hilink_err_api[108006]=${hilink_err_api[108001]}
hilink_err_api[108003]="User already logged in - need to wait a bit"
hilink_err_api[108007]="Too many login attempts - need to wait a bit"
hilink_err_api[125001]="Invalid session/request token"
hilink_err_api[125002]=${hilink_err_api[125001]}
hilink_err_api[125003]=${hilink_err_api[125001]}

# check error and return error text
# status passsed in $status, or $1
function _getErrorText() {
    local err="$status"
    local code="0"
    if [ ! -z "$1" ]; then local err="$1"; fi
    if [ -z "$err" ]; then return 1; fi
    errortext="$err"
    if [[  "$err" =~ ERROR\ *([0-9]*) ]] && [ ! -z "${BASH_REMATCH[1]}" ]; then
        local code=${BASH_REMATCH[1]}
        if [ ! -z "$code" ] && [ ! -z "${hilink_err_api[$code]}" ]; then 
            errortext="${hilink_err_api[$code]}"
        fi
    fi
    echo $errortext
    return 0
}

function _hostReachable() {
    local avail=$( timeout 0.5 ping -c 1 $host | sed -rn 's/.*time=.*/1/p' )
    if [ -z "$avail" ]; then return 1; fi
    return 0;
}

# helper function to parse $response (xml format) for a value 
# call another function first!
# parameter: tag-name
function _valueFromResponse() {
    if [ -z "$response" ] || [ -z "$1" ]; then return 1; fi
    local par="$1"
    local value=$(echo $response | sed  -rn 's/.*<'$par'>(.*)<\/'$par'>.*/\1/pi')
    if [ -z "$value" ]; then return 1; fi   
    echo "$value"
    return 0
}

# list all keys of the current xml response
function _keysFromResponse() {
    if [ -z "$response" ]; then return 1; fi
    echo $response | grep -oiP "(?<=<)[a-z_-]*(?=>)"
    return 0
}

# return all key=value pairs of the current xml response
function _keyValuePairs() {
    if [ -z "$response" ]; then return 1; fi
    echo $response | sed -n 's/<\([^>]*\)>\(.*\)<\/\1>[^<]*/\1=\"\2\"\n/gpi'
    return 0
}

hilink_token=""
hilink_tokenlist=""
hilink_sessID=""
hilink_xmldata=""
hilink_xtraopts=""
host=$hilink_host_default
user="admin"
password=""
pin=""
response=""
status=""
 
