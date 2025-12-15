
#!/bin/bash

# ====== CONFIGURATION ======
INTERFACE=$(ip -o link show | awk -F': ' '/wlx/ {print $2}')
TPATH="$HOME/.cache/iwd_rofi_menu_files"

RAW_NETWORK="$TPATH/ssid_raw.txt"
NETWORK="$TPATH/ssid_formatted.txt"
RAW_METADATA="$TPATH/metadata_raw.txt"
METADATA="$TPATH/metadata_formatted.txt"
TEMP_PASSWORD="$TPATH/temp_password.txt"

THEME="$HOME/.config/rofi/styles/wifi.rasi"
PASS_THEME="$HOME/.config/rofi/styles/wifi_password.rasi"
ROFI="rofi -dmenu -mouse -i -theme $THEME"

MENU=("Refresh" "Enable Wi-Fi" "Disable Wi-Fi" "Network Info" "Scan Networks" "Connect" "Disconnect")

mkdir -p "$TPATH"

wifi=()
ssid=()

# ====== UTILITY FUNCTIONS ======
clean_up() { [ -e "$TPATH" ] && rm -r "$TPATH"; }
notify() { dunstctl close-all; notify-send "$1" "$2"; }

power() { iwctl device "$INTERFACE" set-property Powered "$1"; main; }

disconnect() {
    iwctl station "$INTERFACE" disconnect
    notify "Network Disconnected!" "Disconnected from $selected_ssid"
}

check_status() {
    local status=$(iwctl station "$INTERFACE" show | awk '/State/ {print $2}')
    local iface_status="OFF"
    local wifi_status="OFF"
    [[ -n "$status" ]] && iface_status="ON"
    [[ "$status" != "disconnected" && -n "$status" ]] && wifi_status="ON"
    echo "$iface_status $wifi_status"
}

# ====== NETWORK FUNCTIONS ======
format_networks() {
    iwctl station "$INTERFACE" scan
    iwctl station "$INTERFACE" get-networks > "$RAW_NETWORK"

    {
        echo "SSID,SECURITY,SIGNAL"
        local i=1
        sed $'s/[^[:print:]\t]//g' "$RAW_NETWORK" | while read -r line; do
            ((i < 5)) && ((i++)) && continue
            if (( i == 5 )); then
                local status=($(check_status))
                [[ ${status[1]} == "ON" ]] && line="${line:18}" || line="${line:9}"
                echo "$line" | sed 's/  \+/,/g'
                ((i++))
                continue
            fi
            [[ -z "$line" ]] && continue
            echo "$line" | sed 's/  \+/,/g'
        done
    } > "$NETWORK"

    sed -e 's/\*\*\*\*\[1;90m\[0m/[####] /g' -e 's/\*\*\*\[1;90m\*\[0m/[###-] /g' \
        -e 's/\*\*\[1;90m\*\*\[0m/[##--] /g' -e 's/\*\[1;90m\*\*\*\[0m/[#---] /g' \
        -e 's/\[1;90m\*\*\*\*\[0m/[----] /g' -e 's/\*\*\*\*/[####] /g' \
        "$NETWORK" > "${NETWORK}.tmp" && mv "${NETWORK}.tmp" "$NETWORK"
}

get_networks() {
    ssid=(); local security=(); local signal=(); wifi=()
    format_networks
    while IFS=',' read -r col1 col2 col3 col4; do
        if [[ "$col1" != "0m> [0m" ]]; then
            ssid+=("$col1"); security+=("$col2"); signal+=("$col3")
        else
            ssid+=("$col2"); security+=("$col3"); signal+=("$col4")
        fi
    done < <(tail -n +2 "$NETWORK")

    for i in "${!ssid[@]}"; do
        wifi+=("${signal[$i]} ${ssid[$i]} (${security[$i]})")
    done
    [[ "${wifi[2]}" == ' works available ()' ]] && wifi[2]='No networks available!!'
}

connect_to_network() {
    selected_ssid="${ssid[$1]}"
    notify "Connecting..." "Attempting to access $selected_ssid"

    known=$(iwctl known-networks list | grep -w "$selected_ssid")
    local connection_output=""

    notify_connection() {
        if [[ -z "$connection_output" ]]; then
            notify "Connected!" "You are now connected to $selected_ssid"
        elif [[ $connection_output == "Terminate" ]]; then
            notify "Incorrect Password" "Retrying..."
            iwctl known-networks "$selected_ssid" forget
            sleep 2
            get_password
        else
            notify "Connection Failed" "Please try again"
        fi
    }

    get_password() {
        (rofi -dmenu -password -p "  " -theme "$PASS_THEME") > "$TEMP_PASSWORD"
        connection_output=$(timeout 2 iwctl station "$INTERFACE" connect "$selected_ssid" --passphrase="$(<"$TEMP_PASSWORD")" 2>&1)
        notify_connection
    }

    if [[ -n "$known" ]]; then
        connection_output=$(timeout 2 iwctl station "$INTERFACE" connect "$selected_ssid" 2>&1)
        notify_connection
    else
        if iwctl station "$INTERFACE" get-networks | grep -q "$selected_ssid" | grep -q 'open'; then
            connection_output=$(iwctl station "$INTERFACE" connect "$selected_ssid" 2>&1)
            notify_connection
        else
            get_password
        fi
    fi
}

# ====== METADATA FUNCTIONS ======
fetch_wifi_metadata() {
    iwctl station "$INTERFACE" show > "$RAW_METADATA"
    {
        echo "󱚷  Return"
        echo "󱛄  Refresh"
        local i=1
        sed $'s/[^[:print:]\t]//g' "$RAW_METADATA" | while read -r line; do
            ((i <= 5)) && ((i++)) && continue
            [[ -z "$line" ]] && continue
            echo "$line" | sed 's/  \+/,/g'
        done
    } > "$METADATA"

    local list=()
    while IFS=, read -r value; do list+=("$value"); done < "$METADATA"
    echo "${list[@]}"
}

wifi_status() {
    local values=($(fetch_wifi_metadata))
    local data
    data=$(awk -F',' 'BEGIN{max=10} {if(length($1)>max) max=length($1); keys[NR]=$1; vals[NR]=$2} END{for(i=1;i<=NR;i++) printf "%-*s  %s\n", max, keys[i], vals[i]}' "$METADATA")
    local selected=$(echo -e "$data" | $ROFI -format i)
    (( selected == 0 )) && return
    (( selected == 1 )) && wifi_status && return
    echo "${values["$selected"]}" | xclip -selection clipboard
}

# ====== SCAN FUNCTION ======
function scan() {
    # Continue scanning if 'Rescan' option is selected
    local selected_wifi_index=1
    while (( selected_wifi_index == 1 )); do
        notify "Scanning..." "For nearby networks!!"
        wifi=("󱚷  Retur") ; wifi+=("󱛇  Rescan") ; get_networks
        selected_wifi_index=$( printf "%s\n" "${wifi[@]}" | $ROFI_DEFAULT_MODE -format i)
    done

    # Connect to the selected network if an SSID is selected
    if [[ -n "$selected_wifi_index" ]] && (( selected_wifi_index > 1 )); then
        connect_to_network "$((selected_wifi_index - 2))"
    fi
}

# ====== MENU FUNCTIONS ======
rofi_menu() {
    local options="${MENU[0]}"
    local status=($(check_status))
    if [[ "${status[0]}" == "OFF" ]]; then
        options+="\n${MENU[1]}"
    else
        options+="\n${MENU[2]}"
        [[ "${status[1]}" == "OFF" ]] && options+="\n${MENU[5]}" || options+="\n${MENU[3]}\n${MENU[4]}\n${MENU[6]}"
    fi
    echo -e "$options" | $ROFI
}

run_cmd() {
    case "$1" in
        "${MENU[0]}") main ;;
        "${MENU[1]}") power on ;;
        "${MENU[2]}") power off ;;
        "${MENU[3]}") wifi_status; main ;;
        "${MENU[4]}"|"${MENU[5]}") scan; main ;;
        "${MENU[6]}") disconnect; main ;;
        *) return ;;
    esac
}

# ====== MAIN LOOP ======
main() { 
    local choice
    choice=$(rofi_menu)
    run_cmd "$choice"
}

main
clean_up

