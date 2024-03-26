#!/bin/bash

set -euo pipefail

# Define global variables
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly INSTALL_DIR="/opt/5G"
readonly PSIPHON_URL="https://raw.githubusercontent.com/Psiphon-Labs/psiphon-tunnel-core-binaries/master/psiphond/psiphond"
readonly SERVICE_FILE="/etc/systemd/system/psiphon.service"
readonly LOG_FILE="/var/log/psiphon_setup.log"

# Function to log messages to a file
log_message() {
    local log_timestamp
    log_timestamp=$(date +"%Y-%m-%d %T")
    echo "[$log_timestamp] $*" | sudo tee -a "$LOG_FILE" >/dev/null
}

# Function to check for required commands
check_required_commands() {
    local missing_cmds=()
    for cmd in curl wget sed systemctl; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_cmds+=("$cmd")
        fi
    done

    if [[ ${#missing_cmds[@]} -ne 0 ]]; then
        log_message "Error: Missing required commands: ${missing_cmds[*]}"
        exit 1
    fi
}

# Function to update DNS settings securely
update_dns_settings() {
    log_message "Updating DNS settings..."
    sudo sed -i '/^#DNSStubListener=yes/c\DNSStubListener=no' /etc/systemd/resolved.conf
    echo "DNS=1.1.1.1" | sudo tee -a /etc/systemd/resolved.conf >/dev/null
    sudo systemctl restart systemd-resolved
}

# Function to install necessary packages
install_packages() {
    log_message "Installing necessary packages..."
    if ! sudo apt-get update; then
        log_message "Failed to update package repositories."
        exit 1
    fi
    if ! sudo apt-get install -y curl wget screen; then
        log_message "Failed to install necessary packages."
        exit 1
    fi
}

# Function to download and set up Psiphon
setup_psiphon() {
    log_message "Setting up Psiphon in $INSTALL_DIR..."
    sudo mkdir -p "$INSTALL_DIR"
    log_message "Downloading Psiphon..."
    if ! sudo wget -nv "$PSIPHON_URL" -O "$INSTALL_DIR/psiphond"; then
        log_message "Failed to download Psiphon."
        exit 1
    fi
    sudo chmod +x "$INSTALL_DIR/psiphond"

    log_message "Generating Psiphon configuration..."
    local ip_address
    ip_address=$(curl -s https://api.ipify.org)
    (cd "$INSTALL_DIR" && sudo ./psiphond --ipaddress "$ip_address" --protocol SSH:80 --protocol OSSH:53 generate)

    sudo sed -i 's/"ServerIPAddress": "[^"]*"/"ServerIPAddress": "0.0.0.0"/g' "$INSTALL_DIR/psiphond.config"
    log_message "Psiphon installation and configuration complete."
}

# Function to create and enable systemd service
setup_systemd_service() {
    log_message "Creating systemd service for Psiphon..."
    sudo tee "$SERVICE_FILE" >/dev/null <<EOF
[Unit]
Description=Psiphon Service
After=network.target

[Service]
Type=simple
ExecStart=$INSTALL_DIR/psiphond run
WorkingDirectory=$INSTALL_DIR
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable psiphon.service
    sudo systemctl start psiphon.service
    log_message "Psiphon service is now enabled and started."
}

# Function to display the contents of server-entry.dat
display_server_entry() {
    log_message "Displaying contents of server-entry.dat..."
    if [[ -f "$INSTALL_DIR/server-entry.dat" ]]; then
        sudo cat "$INSTALL_DIR/server-entry.dat"
    else
        log_message "server-entry.dat file not found."
    fi
}

# Main function
main() {
    # Set up logging
    sudo touch "$LOG_FILE"
    sudo chown "$(whoami)" "$LOG_FILE"
    
    log_message "Starting the setup process..."
    
    check_required_commands
    update_dns_settings
    install_packages
    setup_psiphon
    setup_systemd_service
    
    log_message "Setup completed successfully."
    
    read -rp "Would you like to display the contents of server-entry.dat now? (y/N): " display_confirm
    if [[ "${display_confirm,,}" =~ ^(yes|y)$ ]]; then
        display_server_entry
    fi

    read -rp "Would you like to reboot now? (y/N): " confirm
    if [[ "${confirm,,}" =~ ^(yes|y)$ ]]; then
        log_message "Rebooting the system..."
        sudo reboot
    else
        log_message "Please reboot the system at your earliest convenience to apply all changes."
    fi
}

# Execute main function
main
