#!/bin/bash

#############################
# Configuration
#############################

INTERFACE=$(ip -o link show | awk -F': ' '/wlx/ {print $2}')
TPATH="$HOME/.cache/iwd_rofi_menu_files"
mkdir -p "$TPATH"

RAW_NETWORK_FILE="$TPATH/iwd_rofi_menu_ssid_raw.txt"
NETWORK_FILE="$TPATH/iwd_rofi_menu_ssid_structured.txt"
RAW_METADATA_FILE="$TPATH/iwd_rofi_menu_metadata_raw.txt"
METADATA_FILE="$TPATH/iwd_rofi_menu_metadata_structured.txt"
TEMP_PASSWORD_FILE="$TPATH/iwd_rofi_menu_temp_ssid_password.txt"

THEME_FILE="$HOME/.config/rofi/styles/wifi.rasi"
PASS_WIN_THEME="$HOME/.config/rofi/styles/wifi_password.rasi"
ROFI_DEFAULT_MODE="rofi -dmenu -mouse -i -theme $THEME_FILE"

MENU_OPTIONS=("Refresh" "Enable Wi-Fi" "Disable Wi-Fi" "Network Info" "Scan Networks" "Connect" "Disconnect")
wifi=()
ssid=()

#############################
# Utilities
#############################

clean_up() { [ -e "$TPATH" ] && rm -r "$TPATH"; }
notify() { dunstctl close-all; notify-send "$1" "$2"; }

check_status() {
    local status=$(iwctl station "$INTERFACE" show | awk '/State/ {print $2}')
    if [[ -n "$status" ]]; then
        local iface="ON"
        local wifi_status=$([[ "$status" == "disconnected" ]] && echo "OFF" || echo "ON")
    else
        local iface="OFF" wifi_status=""
    fi
    echo "$iface $wifi_status"
}

connect_with_password() {	
    rofi -dmenu -password -p "" -theme "$PASS_WIN_THEME" > "$TEMP_PASSWORD_FILE"
    password="$(<"$TEMP_PASSWORD_FILE")"
	connection_output=$(timeout 2 iwctl station "$INTERFACE" connect "$1" --passphrase="$password" 2>&1)
}

notify_connection() {
    if [[ -z "$output" ]] || [[ "$state" == "connected" ]]; then
        notify "Connection Successful" "Connected to $1"
    else
        notify "Connection Failed" "Something went wrong."
    fi
}

#############################
# Network Functions
#############################

format_networks() {
    iwctl station "$INTERFACE" scan
    iwctl station "$INTERFACE" get-networks > "$RAW_NETWORK_FILE"

    {
        echo "SSID,SECURITY,SIGNAL"
        local i=1
        sed $'s/[^[:print:]\t]//g' "$RAW_NETWORK_FILE" | while read -r line; do
            ((i<5)) && ((i++)) && continue
            if ((i==5)); then
                local wifi_status=($(check_status))
                [[ ${wifi_status[1]} == "ON" ]] && line="${line:18}" || line="${line:9}"
                echo "$line" | sed 's/  \+/,/g'
                ((i++))
                continue
            fi
            [[ -z "$line" ]] && continue
            echo "$line" | sed 's/  \+/,/g'
        done
    } > "$NETWORK_FILE"

    sed -e 's/\*\*\*\*\[1;90m\[0m/[####]/g' -e 's/\*\*\*\[1;90m\*\[0m/[###-]/g' \
        -e 's/\*\*\[1;90m\*\*\[0m/[##--]/g' -e 's/\*\[1;90m\*\*\*\[0m/[#---]/g' \
        -e 's/\[1;90m\*\*\*\*\[0m/[----]/g' -e 's/\*\*\*\*/[####]/g' \
        "$NETWORK_FILE" > "${NETWORK_FILE}.tmp" && mv "${NETWORK_FILE}.tmp" "$NETWORK_FILE"
}

get_networks() {
    ssid=() wifi=()
    local security=() signal=()
    format_networks

    while IFS=',' read -r col1 col2 col3 col4; do
        if [[ "$col1" != "0m> [0m" ]]; then
            ssid+=("$col1") security+=("$col2") signal+=("$col3")
        else
            ssid+=("$col2") security+=("$col3") signal+=("$col4")
        fi
    done < <(tail -n +2 "$NETWORK_FILE")

    for ((i=0; i<${#ssid[@]}; i++)); do
        wifi+=("${signal[$i]} ${ssid[$i]} (${security[$i]})")
    done

    [[ "${wifi[0]}" == ' works available ()' ]] && wifi[0]='No networks available!'
}

connect_to_network() {
    local selected_ssid="${ssid[$1]}"
	local ssid_security="${security[$1]}"
	local known=$(iwctl known-networks list | grep -w "$selected_ssid")
	local state=$(iwctl station "$INTERFACE" show | awk '/State/ {print $2}')
    
	notify "Connecting..." "Attempting $selected_ssid"

    if [[ -n "$known" ]]; then
        connection_output=$(timeout 2 iwctl station "$INTERFACE" connect "$selected_ssid" 2>&1)
        if [[ $state != "connected" ]]; then
			notify "Wrong Password" "Retrying..."
			iwctl known-networks "<"$ssid">" forget
			connect_with_password "$selected_ssid" "$ssid_security"
			return
		fi
		notify_connection "$selected_ssid" "$connection_output"
    else
        if iwctl station "$INTERFACE" get-networks | grep -q "$selected_ssid" | grep -q 'open'; then
            connection_output=$(iwctl station "$INTERFACE" connect "$selected_ssid" 2>&1)
            notify_connection "$selected_ssid" "$connection_output"
        else
            connect_with_password "$selected_ssid" "$ssid_security"
			notify_connection "$selected_ssid" "$connection_output"
        fi
    fi
}

#############################
# Metadata Functions
#############################

fetch_wifi_metadata() {
    iwctl station "$INTERFACE" show > "$RAW_METADATA_FILE"
    {
        echo "󱚷  Return"
        echo "󱛄  Refresh"
        sed $'s/[^[:print:]\t]//g' "$RAW_METADATA_FILE" | tail -n +6 | sed '/^$/d; s/  \+/,/g'
    } > "$METADATA_FILE"

    mapfile -t list < "$METADATA_FILE"
    echo "${list[@]}"
}

wifi_status() {
    local values=($(fetch_wifi_metadata))
    local data=$(awk -F',' 'BEGIN{max=10}{if(length($1)>max)max=length($1);keys[NR]=$1;vals[NR]=$2}END{for(i=1;i<=NR;i++)printf "%-*s  %s\n",max,keys[i],vals[i]}' "$METADATA_FILE")
    local selected_index=$(echo -e "$data" | $ROFI_DEFAULT_MODE -format i)
    ((selected_index==0)) && return
    ((selected_index==1)) && wifi_status && return
    echo "${values[$selected_index]}" | xclip -selection clipboard
}

#############################
# Menu Functions
#############################

power() { iwctl device "$INTERFACE" set-property Powered "$1" ; main; }
notify() { dunstctl close-all ; notify-send "$1" "$2";}
function disconnect() {
    iwctl station "$INTERFACE" disconnect
    notify "Network Disconnected!!" "You are now disconnected to $selected_ssid..."
}

scan() {
    local selected_index=1
    while ((selected_index==1)); do
        notify "Scanning..." "Nearby networks"
        get_networks
		wifi_opts=("󱚷  Return" "󱛇  Rescan" "${wifi[@]}")
        selected_index=$(printf "%s\n" "${wifi_opts[@]}" | $ROFI_DEFAULT_MODE -format i)
    done
    ((selected_index>1)) && connect_to_network "$((selected_index-2))"
}

rofi_menu() {
    local options="${MENU_OPTIONS[0]}"
    local status=($(check_status))

    if [[ "${status[0]}" == "OFF" ]]; then
        options+="\n${MENU_OPTIONS[1]}"
    else
        options+="\n${MENU_OPTIONS[2]}"
        if [[ "${status[1]}" == "OFF" ]]; then
            options+="\n${MENU_OPTIONS[5]}"
        else
            options+="\n${MENU_OPTIONS[3]}\n${MENU_OPTIONS[4]}\n${MENU_OPTIONS[6]}"
        fi
    fi

    echo -e "$options" | $ROFI_DEFAULT_MODE
}

run_cmd() {
    case "$1" in
        "${MENU_OPTIONS[0]}") main ;;
        "${MENU_OPTIONS[1]}") power on ;;
        "${MENU_OPTIONS[2]}") power off ;;
        "${MENU_OPTIONS[3]}") wifi_status; main ;;
        "${MENU_OPTIONS[4]}"| "${MENU_OPTIONS[5]}") scan; main ;;
        "${MENU_OPTIONS[6]}") disconnect; main ;;
    esac
}

#############################
# Main
#############################

main() {
    local choice=$(rofi_menu)
    run_cmd "$choice"
}

main && clean_up
