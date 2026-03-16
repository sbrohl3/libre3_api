#!/bin/bash 

# (BGM) Bash Glucose Monitor
#####################################
# Using your LibreLinkUp Credentials
# this script uses the LibreLinkUp API
# to display your Libre 3 CGM data
# in your Bash terminal
#
# An 8-bit graph representing your 
# CGM graph will appear in your terminal.
# Additionally you will see your current
# BG value from your CGM highlighted in
# either the color red, green, or yellow
# which indicate place in range.

VERSION=1.5
# 03/16/2026
# Pink 2026

# Constant pointing to the current script execution dir 
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Constant pointing to a config file containing 
# LibreLinkUp Credentials and API configuration parameters
CONFIG_FILE="${SCRIPT_DIR}/config.json"

# Constants containing API config
# Fetched from config.json - DO NOT EDIT
#######################################
LIBRE_USER=""
LIBRE_PASS=""
API_VERSION=""
BASE_URL=""
SHOW_INFO=""
OBFUSCATE=""
#######################################

# Color codes for text - DO NOT EDIT
#######################################
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color / reset
#######################################

# Default Values
#######################################
# Fallback API URL in case config is empty
DEFAULT_URL="https://api.libreview.io"

# Fallback API version in case config is empty
DEFAULT_VERSION="4.16.0"

# How many times to retry on failed plot
RETRY_BEFORE_FAIL=5

# Time delay between reading measurements (in seconds)
TIME_BETWEEN_MEASUREMENTS=60
#######################################

function clean_up() {
    # This function safely exits the script on early exit by the user
    echo -e "ATTENTION: User has pressed Ctrl+C! Exiting script!"
    exit 0
}

function fetch_account_id() {
    # This function fetches the user_id and converts it to a SHA256 checksum to act as the Account ID for the Libre API
    local account_id=$(printf '%s' "${user_id}" | sha256sum | awk '{print $1}')
    
    if [[ -n "${account_id}" ]]; then
        echo $account_id
        return 0
    else
        return 1
    fi

}

function fetch_connection() {
    # This function creates a connection session to the Libre API
    local connection_data=$(curl -sS -X GET \
        --url ${BASE_URL}/llu/connections \
        --header "Accept: application/json, application/xml, multipart/form-data" \
        --header "Authorization: Bearer ${token}" \
        --header "product: llu.android" \
        --header "version: ${API_VERSION}" \
        --header "Account-Id: ${account_id}")

    if [[ $? -eq 1 || -z "$connection_data" ]]; then
        echo -e "ERROR: Cannot complete connection request as formed!" 
        return 1
    fi

    if [[ -n "$connection_data" ]]; then
        status_code=$(echo "$connection_data" | jq -r '.status')
        if [[ $status_code != 0 ]]; then
            echo -e "ERROR: Connection request responded with - ${status_code}!"
            return 1
        fi 
    fi
        
    echo $connection_data
    return 0

}

function fetch_graph() {
    # This function fetches the latest graph data from the Libre API
    local graph_data=$(curl -sS --request GET \
        --url "${BASE_URL}/llu/connections/${patient_id}/graph" \
        --header "Accept: application/json" \
        --header "Authorization: Bearer ${token}" \
        --header "product: llu.android" \
        --header "version: ${API_VERSION}" \
        --header "Account-Id: ${account_id}")

        if [[ $? -eq 1 || -z "$graph_data" ]]; then
            echo -e "ERROR: Cannot complete graph request as formed!" 
            return 1
        fi

        if [[ -n "$graph_data" ]]; then
            status_code=$(echo "$graph_data" | jq -r '.status')
            if [[ $status_code != 0 ]]; then
                echo -e "ERROR: Graph request responded with - ${status_code}!"
                return 1
            fi 
        fi

    echo $graph_data
    return 0

}

function fetch_patient_id() {
    # This function fetches the patient ID from the connection information data
    local patient_id=$(jq -r '.data[].patientId' <<<"$connection")
   
    if [[ -n "${patient_id}" ]]; then
        echo $patient_id
        return 0
    else
        return 1
    fi

}

function fetch_token() {
    # This function fetches the Oauth token for authenticating the user to the Libre API endpoint
    local token=$(echo ${user_info} | jq -r .data.authTicket.token)

    if [[ -n "${token}" ]]; then
        echo $token
        return 0
    else
        return 1
    fi

}

function fetch_user_id() {
    # This function fetches the user UUID from the Json response payload
    local user_id=$(jq -r '.data.user.id' <<<"$user_info")
   
    if [[ -n "${user_id}" ]]; then
        echo $user_id
        return 0
    else
        return 1
    fi

}

function login_user() { 
    # This function logs the user into the Libre API so a token and then session can be created
    if [[ -z "${LIBRE_USER}" || -z "${LIBRE_PASS}" ]]; then
        echo -e "ERROR: Missing credentials! Please check email or password in config.json, and retry!" 
        return 1
    else 
        email="${LIBRE_USER}"
        password="${LIBRE_PASS}"
    fi

    if [ -f "current_session.json" ]; then
        login_info=$(<current_session.json)
        
        if [[ -n "$login_info" ]]; then
            status_code=$(echo "$login_info" | jq -r '.status')
            if [[ $status_code != 0 ]]; then
                echo -e "ERROR: Current session status is invalid - ${status_code}!"
                # If the current session is empty or invalid, delete it
                rm current_session.json
                return 1
            fi 
        fi

    else
        local login_info=$(curl -sS -X POST \
        --url ${BASE_URL}/llu/auth/login \
        --header "Accept: application/json" \
        --header "Content-Type: application/json" \
        --header "product: llu.android" \
        --header "version: ${API_VERSION}" \
        --data "{ 
        \"email\": \"${email}\",
        \"password\": \"${password}\"
        }")

        if [[ $? -eq 1 || -z "$login_info" ]]; then
            echo -e "ERROR: Cannot complete login request as formed!" 
            return 1
        fi

        if [[ -n "$login_info" ]]; then
            status_code=$(echo "$login_info" | jq -r '.status')
            if [[ $status_code != 0 ]]; then
                echo -e "ERROR: Login request responded with - ${status_code}!"
                return 1
            fi 
        fi
            
        echo $login_info > current_session.json

    fi

    echo $login_info
    return 0

}

function main() {
    # This is the main entry to execute the script

    # Display script splashscreen
    splash

    # Define a trap to catch user input for ctrl+c / early exit
    trap clean_up SIGINT SIGTERM

    # Run the script's execution flow
    run
    res=$?
    if [ $res -eq 1 ]; then
        echo "ERROR: Exiting program - ${res}"
        exit $res
    fi

}

function open_config() {
    # This function opens the Json config file containing the LibreLinkUp API Username and Password
    local creds_file="$1"

    if [[ ! -f "$CONFIG_FILE" ]]; then
        echo "ERROR: Config file containing LibreLinkUp Credentials not found: $CONFIG_FILE!" >&2
        return 1 
    fi

    LIBRE_USER=$(jq -r '.libre_user' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Could not load \"libre_user\" from json config!"
        return 1
    fi 

    LIBRE_PASS=$(jq -r '.libre_pass' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Could not load \"libre_user\" from json config!"
        return 1
    fi 

    BASE_URL=$(jq -r '.api_url' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Could not load \"api_url\" from json config!"
        BASE_URL=$DEFAULT_URL
        echo -e "Setting default API BASE URL - ${BASE_URL}" 
    fi 

    API_VERSION=$(jq -r '.api_version' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Could not load \"api_version\" from json config!"
        API_VERSION=$DEFAULT_VERSION
        echo -e "Setting default API Version - ${API_VERSION}" 
    fi 

    SHOW_INFO=$(jq -r '.show_user_info' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        SHOW_INFO=false
    fi 

    OBFUSCATE=$(jq -r '.obfuscate_info' "$CONFIG_FILE")
    if [ $? -eq 1 ]; then
        OBFUSCATE=true
    fi 

    echo -e "\nSUCCESS: Credentials successfully loaded for user: $LIBRE_USER"
    return 0
}

function plot_graph() {
    # This function plots the graph data to the terminal 

    # Read the graph data into an array
    mapfile -t values < <(echo "$graph_data" | jq -r '.data.graphData[].Value')

    # Query current column width 
    cols=$(tput cols)

    # If columns can't be calculated, set a default
    if [[ -z "$cols" ]]; then 
        cols=80
    fi
    
    # Get length of values array
    n=${#values[@]}

    # Column padding to leave for label area
    ypad=7

    # Set the terminal column width (horizontally) 
    target=$(( cols - ypad ))

    # If calculated target size is <10, set a default
    if (( target < 10 )); then
        target=10
    fi 

    # Set step size for downsampling
    # n = total data points
    # taget = how many points you want after downsampling
    # step = how far to jump each iteration
    step=$(( (n + target - 1) / target ))

    # If the calculated step size is <1, set a default
    if (( step < 1 )); then 
        step=1
    fi

    # Init an empty array to hold downsampled values
    ds=()

    # Increment by $step and append values[i] to ds
    for ((i=0; i<n; i+=step)); do
        ds+=("${values[i]}")
    done

    # Fetch min/max values in the downsampled array
    max_value=0
    min_value=999999
    for v in "${ds[@]}"; do
        if (( v > max_value )); then 
            max_value=$v
        fi 

        if (( v < min_value )); then
            min_value=$v
        fi

    done

    # Scale ceiling - tallest a bar can be in terminal rows
    graph_height=20

    # Init an empty array to hold ceiling values
    heights=()

    # Normalize graph ceiling so larger values are distinguisable
    for v in "${ds[@]}"; do
        heights+=( $(( v * graph_height / max_value )) )
    done

    # Draw graph to scale
    for ((row=graph_height; row>=1; row--)); do
        # Get the current value to print as y-axis label
        label=$(( (row * max_value + graph_height - 1) / graph_height ))

        # Print tick labels every 5 rows
        if (( row == graph_height || row == 1 || row % 5 == 0 )); then
            printf "%3d | " "$label"
        else
            printf "    | "
        fi

        # Render the graph one row at a time from top to bottom
        for h in "${heights[@]}"; do
            # if the bar height reaches the current row then print a bar
            if (( h >= row )); then 
                printf "█"
            else 
                printf " "
            fi
        done
        printf "\n"
    done

    # Print boundary line for x-axis
    # Prints "-" for the total length of the x-axis
    printf "    + "
    printf "%*s\n" "${#heights[@]}" "" | tr ' ' '-'

    # Print graph min/max values
    printf "\tmin=%d max=%d\n" "$min_value" "$max_value"

}

function read_measurement() {
    # Main loop for reading measurements from Libre API and plotting data to terminal

    local num_retries=0
    local retry_count=$RETRY_BEFORE_FAIL

    while true; do
        redraw_screen
        
        # Get latest graph data
        graph_data=$(fetch_graph)

        if [ $? -eq 1 ]; then
            
            # On the retry_count iteration if still an error, exit plotting loop
            if [[ num_retries -ge retry_count ]]; then
                echo -e "ERROR: Failed to plot graph ${retry_count} times!"
                return 1
            fi

            # Increment retries on failure
            ((num_retries++))
            
            continue

        fi

        echo -e "Welcome $(jq -r .data.user.firstName <<< $user_info),\n"

        local bg_value=$(echo $graph_data | jq .data.connection.glucoseMeasurement.Value)
        local is_high=$(echo $graph_data | jq .data.connection.glucoseMeasurement.isHigh)
        local is_low=$(echo $graph_data | jq .data.connection.glucoseMeasurement.isLow)

        if [[ "$is_high" == "true" ]]; then
            color=$YELLOW
        elif [[ "$is_low" == "true" ||  "${bg_value}" == "null" ]]; then 
            color=$RED
        else
            color=$GREEN
        fi

        echo -e "\t\tYour current blood glucose measurement is: ${color}${bg_value}${NC}\t\t\t\t\t\t\t\t$(date)\n" 

        # Plot latest graph data to terminal
        local gd=$(echo $graph_data | jq .data.graphData)

        plot_graph $gd   

        # Wait before next plot
        sleep "$TIME_BETWEEN_MEASUREMENTS"

    done

}

function redraw_screen() {
    # Clears the screen for next iteration
    printf '\e[H\e[J'
}

function run() {
    # This is the main function which executes the flow for the script

    open_config "$CONFIG_FILE"
    if [ $? -eq 1 ]; then
        return 1
    fi

    user_info=$(login_user)
    if [ $? -eq 1 ]; then
        echo -e "$user_info"
        return 1
    fi

    # Get Oauth Token to make API calls
    token=$(fetch_token)
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Token could not be retrieved!"
        return 1
    fi

    # Get Libre User account UUID
    user_id=$(fetch_user_id)
    if [ $? -eq 1 ]; then
        echo -e "ERROR: User UUID could not be retrieved!"
        return 1
    fi

    # Get the sha256 sum of the UUID to authenticate to each API call
    account_id=$(fetch_account_id)
    if [ $? -eq 1 ]; then
        echo -e "ERROR: User UUID Sha256sum could not be retrieved!"
        return 1
    fi

    # Grab the current user connection (Must connect Libre App to LibreLinkUp app and open at least once to see data with this API call)
    connection=$(fetch_connection)
    if [ $? -eq 1 ]; then
        echo -e "$connection"
        return 1
    fi

    # Get the unique patient ID for the User UUID
    patient_id=$(fetch_patient_id)
    if [ $? -eq 1 ]; then
        echo -e "ERROR: Patient ID could not be retrieved!"
        return 1
    fi

    # Hold token/patientID in temp vars for obfuscation
    temp_token=$token
    temp_patientId=$patient_id

    # Hide patient info at startup
    if [[ $SHOW_INFO == true ]]; then
        # Obfuscate patient info - replacing confidential strings with ******
        if [[ ${OBFUSCATE} == true ]]; then

            # Obfuscate the token for printing to terminal
            local token_length=$(echo $token | tr -d '\n' | wc -c)
            local obfuscated_token=$(printf '%*s' "$token_length" '' | tr ' ' '*')

            # Obfuscate the patientId for printing to terminal
            local patientId_length=$(echo $patient_id | tr -d '\n' | wc -c)
            local obfuscated_patientId=$(printf '%*s' "$patientId_length" '' | tr ' ' '*')

            temp_token=$obfuscated_token
            temp_patientId=$obfuscated_patientId
            
        fi
        
        echo -e "Token:\n${temp_token}\n\nPatientId: ${temp_patientId}\n"
    fi

    # Wait before entering plotting loop
    sleep 1

    # Go into measurement loop
    read_measurement
    local res=$?
    if [ $res -eq 1 ]; then
        return 1
    fi

}

function splash() {
    printf '%s\n' \
    ' ____            _      _____ _                          __  __             _ _             ' \
    '|  _ \          | |    / ____| |                        |  \/  |           (_) |            ' \
    '| |_) | __ _ ___| |__ | |  __| |_   _  ___ ___  ___  ___| \  / | ___  _ __  _| |_ ___  _ __ ' \
    '|  _ < / _` / __| '\''_ \| | |_ | | | | |/ __/ _ \/ __|/ _ \ |\/| |/ _ \| '\''_ \| | __/ _ \| '\''__|' \
    '| |_) | (_| \__ \ | | | |__| | | |_| | (_| (_) \__ \  __/ |  | | (_) | | | | | || (_) | |   ' \
    '|____/ \__,_|___/_| |_|\_____|_|\__,_|\___\___/|___/\___|_|  |_|\___/|_| |_|_|\__\___/|_|  '  \
    '============================================================================================' \
    "Created by Pink 2026 © Version $VERSION"
    
    sleep 2

}

main
