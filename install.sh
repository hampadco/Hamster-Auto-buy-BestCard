#!/bin/bash

# Colors
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
purple='\033[0;35m'
cyan='\033[0;36m'
blue='\033[0;34m'
rest='\033[0m'

# If running in Termux, update and upgrade
if [ -d "$HOME/.termux" ] && [ -z "$(command -v jq)" ]; then
    echo "Running update & upgrade ..."
    pkg update -y
    pkg upgrade -y
fi

# Function to install necessary packages
install_packages() {
    local packages=(curl jq bc)
    local missing_packages=()

    # Check for missing packages
    for pkg in "${packages[@]}"; do
        if ! command -v "$pkg" &> /dev/null; then
            missing_packages+=("$pkg")
        fi
    done

    # If any package is missing, install missing packages
    if [ ${#missing_packages[@]} -gt 0 ]; then
        if [ -n "$(command -v pkg)" ]; then
            pkg install "${missing_packages[@]}" -y
        elif [ -n "$(command -v apt)" ]; then
            sudo apt update -y
            sudo apt install "${missing_packages[@]}" -y
        elif [ -n "$(command -v yum)" ]; then
            sudo yum update -y
            sudo yum install "${missing_packages[@]}" -y
        elif [ -n "$(command -v dnf)" ]; then
            sudo dnf update -y
            sudo dnf install "${missing_packages[@]}" -y
        else
            echo -e "${yellow}Unsupported package manager. Please install required packages manually.${rest}"
            exit 1
        fi
    fi
}

# Install the necessary packages
install_packages

# Clear the screen
clear

# Prompt for Authorization
echo -e "${purple}============================${rest}"
echo -en "${green}Enter Authorization [${cyan}Example: ${yellow}Bearer 171852....${green}]: ${rest}"
read -r Authorization
echo -e "${purple}============================${rest}"

# Prompt for minimum balance threshold
echo -en "${green}Enter minimum balance threshold (${yellow}the script will stop purchasing if the balance is below this amount${green}):${rest} "
read -r min_balance_threshold

# Function to purchase upgrade
purchase_upgrade() {
    upgrade_id="$1"
    timestamp=$(date +%s%3N)
    response=$(curl -s -X POST \
      -H "Content-Type: application/json" \
      -H "Authorization: $Authorization" \
      -H "Origin: https://hamsterkombat.io" \
      -H "Referer: https://hamsterkombat.io/" \
      -d "{\"upgradeId\": \"$upgrade_id\", \"timestamp\": $timestamp}" \
      https://api.hamsterkombat.io/clicker/buy-upgrade)
    echo "$response"
}

# Function to get the best upgrade item
# Function to get the best upgrade item
get_best_item() {
    curl -s -X POST -H "User-Agent: Mozilla/5.0 (Android 12; Mobile; rv:102.0) Gecko/102.0 Firefox/102.0" \
        -H "Accept: */*" \
        -H "Accept-Language: en-US,en;q=0.5" \
        -H "Referer: https://hamsterkombat.io/" \
        -H "Authorization: $Authorization" \
        -H "Origin: https://hamsterkombat.io" \
        -H "Connection: keep-alive" \
        -H "Sec-Fetch-Dest: empty" \
        -H "Sec-Fetch-Mode: cors" \
        -H "Sec-Fetch-Site: same-site" \
        -H "Priority: u=4" \
        https://api.hamsterkombat.io/clicker/upgrades-for-buy | jq -r '.upgradesForBuy | map(select(.isExpired == false and .isAvailable)) | map(select(.profitPerHourDelta != 0 and .price != 0 and .cooldownSeconds <= 600)) | sort_by(-(.profitPerHourDelta / .price))[:1] | .[0] | {id: .id, section: .section, price: .price, profitPerHourDelta: .profitPerHourDelta, cooldownSeconds: .cooldownSeconds}'
}

# Function to wait for cooldown period
wait_for_cooldown() {
    cooldown_seconds="$1"
    echo -e "${yellow}Upgrade is on cooldown. Waiting for cooldown period of ${cyan}$cooldown_seconds${yellow} seconds...${rest}"
    sleep "$cooldown_seconds"
}

# Main script logic
# Main script logic
main() {
    while true; do
        # Get the best item to buy
        best_item=$(get_best_item)
        
        if [ -z "$best_item" ]; then
            echo -e "${yellow}No suitable upgrade found. Waiting for 60 seconds before trying again...${rest}"
            sleep 60
            continue
        fi

        best_item_id=$(echo "$best_item" | jq -r '.id')
        section=$(echo "$best_item" | jq -r '.section')
        price=$(echo "$best_item" | jq -r '.price')
        profit=$(echo "$best_item" | jq -r '.profitPerHourDelta')
        cooldown=$(echo "$best_item" | jq -r '.cooldownSeconds')

        echo -e "${purple}============================${rest}"
        echo -e "${green}Best item to buy:${yellow} $best_item_id ${green}in section:${yellow} $section${rest}"
        echo -e "${blue}Price: ${cyan}$price${rest}"
        echo -e "${blue}Profit per Hour: ${cyan}$profit${rest}"
        echo -e "${blue}Cooldown: ${cyan}$cooldown ${blue}seconds${rest}"
        echo ""

        # Get current balanceCoins
        current_balance=$(curl -s -X POST \
            -H "Authorization: $Authorization" \
            -H "Origin: https://hamsterkombat.io" \
            -H "Referer: https://hamsterkombat.io/" \
            https://api.hamsterkombat.io/clicker/sync | jq -r '.clickerUser.balanceCoins')

        # Check if current balance is above the threshold after purchase
        if (( $(echo "$current_balance - $price > $min_balance_threshold" | bc -l) )); then
            echo -e "${green}Attempting to purchase upgrade '${yellow}$best_item_id${green}'...${rest}"
            echo ""

            purchase_status=$(purchase_upgrade "$best_item_id")

            if echo "$purchase_status" | grep -q "error_code"; then
                wait_for_cooldown "$cooldown"
            else
                echo -e "${green}Upgrade ${yellow}'$best_item_id'${green} purchased successfully.${rest}"
                sleep_duration=$((RANDOM % 8 + 5))
                echo -e "${green}Waiting for ${yellow}$sleep_duration${green} seconds before next purchase...${rest}"
                sleep "$sleep_duration"
            fi
        else
            echo -e "${red}Current balance ${cyan}(${current_balance}) ${red}minus price of item ${cyan}(${price}) ${red}is below the threshold ${cyan}(${min_balance_threshold})${red}. Waiting for 60 seconds before trying again...${rest}"
            sleep 60
        fi
    done
}

# Execute the main function
main
