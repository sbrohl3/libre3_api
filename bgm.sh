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

# 01/03/2026
# Pink 2026

# LibreLinkUp Credentials
email=""
password=""

# Color codes for text
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color / reset

# API INFO
API_VERSION="4.16.0"
BASE_URL="https://api.libreview.io"

# Obfuscate patient credentials printed on startup
SHOW_INFO=false
OBFUSCATE=true 

function login_user() { 

    if [ -f "current_session.json" ]; then {
        login_info=$(<current_session.json)
    }
    else {
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

        echo $login_info > current_session.json
    }
    fi

    echo $login_info

}

function fetch_account_id() {
    local account_id=$(printf '%s' "$user_id" | sha256sum | awk '{print $1}')
    
    echo $account_id

}

function fetch_connection() {
    local connection_data=$(curl -sS -X GET \
        --url ${BASE_URL}/llu/connections \
        --header "Accept: application/json, application/xml, multipart/form-data" \
        --header "Authorization: Bearer ${token}" \
        --header "product: llu.android" \
        --header "version: ${API_VERSION}" \
        --header "Account-Id: ${account_id}")

    echo $connection_data

}

function fetch_graph() {
    local graph_data=$(curl -sS --request GET \
        --url "${BASE_URL}/llu/connections/${patient_id}/graph" \
        --header "Accept: application/json" \
        --header "Authorization: Bearer ${token}" \
        --header "product: llu.android" \
        --header "version: ${API_VERSION}" \
        --header "Account-Id: ${account_id}")

    echo $graph_data

}

function fetch_patient_id() {
    local patient_id=$(jq -r '.data[].patientId' <<<"$connection")
   
    echo $patient_id 

}

function fetch_token() {
    local token=$(echo $user_info | jq -r .data.authTicket.token)

    echo $token

}

function fetch_user() {
    user=$(curl -sS -X GET \
    --url "${BASE_URL}/user" \
    --header "Accept: application/json, application/xml" \
    --header "Authorization: Bearer ${token}" \
    --header "product: llu.android" \
    --header "version: ${API_VERSION}" \
    --header "Account-Id: ${account_id}")

    echo $user

}

function fetch_user_id() {
   local user_id=$(jq -r '.data.user.id' <<<"$user_info")
   
   echo $user_id

}

function read_measurement() {
    while true; do
        redraw_screen
        
        # Get latest graph data
        graph_data=$(fetch_graph)

        echo -e "Welcome $(jq -r .data.user.firstName <<< $user_info),\n"
        #echo -e "Welcome $USER,\n"

        local bg_value=$(echo $graph_data | jq .data.connection.glucoseMeasurement.Value)
        local is_high=$(echo $graph_data | jq .data.connection.glucoseMeasurement.isHigh)
        local is_low=$(echo $graph_data | jq .data.connection.glucoseMeasurement.isLow)

        if [[ "$is_high" == "true" ]]; then {
            color=$YELLOW
        }
        elif [[ "$is_low" == "true" ]]; then {
            color=$RED
        }
        else {
            color=$GREEN
        }
        fi

        echo -e "\t\tYour current blood glucose measurement is: ${color}${bg_value}${NC}\t\t\t\t\t\t\t\t$(date)\n" 

        # Plot latest graph data to terminal
        local gd=$(echo $graph_data | jq .data.graphData)

        plot_graph $gd   

        # Wait before next plot
        sleep 60
    done

}

function redraw_screen() {
  printf '\e[H\e[J'
}

function main() {
    user_info=$(login_user)
    
    # Get Oauth Token to make API calls
    token=$(fetch_token $user_info)
    
    # Get Libre User account UUID
    user_id=$(fetch_user_id)

    # Get the sha256 sum of the UUID to authenticate to each API call
    account_id=$(fetch_account_id)

    # Grab the current user connection (Must connect Libre App to LibreLinkUp app and open at least once to see data with this API call)
    connection=$(fetch_connection)

    # Get the unique patient ID for the User UUID
    patient_id=$(fetch_patient_id)
    
    temp_token=$token
    temp_patientId=$patient_id

    if [[ $SHOW_INFO == true ]]; then
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

    # Go into measurement loop
    read_measurement

}

function plot_graph() {
    mapfile -t values < <(echo "$graph_data" | jq -r '.data.graphData[].Value')

    cols=$(tput cols)
    n=${#values[@]}

    # space for " 999 | " on the left
    ypad=7

    target=$(( cols - ypad ))
    (( target < 10 )) && target=10

    step=$(( (n + target - 1) / target ))
    (( step < 1 )) && step=1

    ds=()
    for ((i=0; i<n; i+=step)); do
        ds+=("${values[i]}")
    done

    max_value=0
    min_value=999999
    for v in "${ds[@]}"; do
        (( v > max_value )) && max_value=$v
        (( v < min_value )) && min_value=$v
    done

    graph_height=20

    heights=()
    for v in "${ds[@]}"; do
        heights+=( $(( v * graph_height / max_value )) )
    done

    # draw with scale
    for ((row=graph_height; row>=1; row--)); do
        # value at this row (top row ~= max_value)
        label=$(( (row * max_value + graph_height - 1) / graph_height ))  # ceil

        # only print tick labels every 5 rows (adjust if you want)
        if (( row == graph_height || row == 1 || row % 5 == 0 )); then
            printf "%3d | " "$label"
        else
            printf "    | "
        fi

        for h in "${heights[@]}"; do
            (( h >= row )) && printf "█" || printf " "
        done
        printf "\n"
    done

    # x-axis
    printf "    + "
    printf "%*s\n" "${#heights[@]}" "" | tr ' ' '-'

    # optional: min/max info
    printf "\tmin=%d max=%d\n" "$min_value" "$max_value"

}

function print_user_info() {
    echo $user_info
}

main
