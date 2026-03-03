#!/bin/bash

# Exit on any error
set -e

# --- 1. OS Detection ---
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    LIKE=$ID_LIKE
else
    echo "Unsupported OS: /etc/os-release not found."
    exit 1
fi

echo "Detected System: $OS (Base: $LIKE)"

# --- 2. Timezone & Locale ---
# Your specific requirement for Asia/Jakarta
timedatectl set-timezone Asia/Jakarta

# --- 3. Package Management Logic ---
case "$OS" in
    ubuntu|debian|raspbian)
        echo "Running Debian/Ubuntu tasks..."
        apt update && apt upgrade -y
        apt install -y qemu-guest-agent curl wget jq
        systemctl enable --now qemu-guest-agent
        ;;
        
    fedora|centos|rhel|almalinux|rocky)
        echo "Running Red Hat-based tasks..."
        dnf update -y
        dnf install -y qemu-guest-agent curl wget jq
        systemctl enable --now qemu-guest-agent
        ;;

    *)
        echo "OS $OS not explicitly supported, attempting generic setup..."
        ;;
esac

# --- 4. Remote Monitoring (Example: Netdata or Prometheus) ---
# Add your specific monitoring agent install command here
# curl -s https://my-monitoring-server.com/install.sh | bash

# --- 5. SSH Public Key Setup ---
# Ensures the .ssh directory exists and has correct permissions
mkdir -p ~/.ssh
chmod 700 ~/.ssh
# Replace the string below with your actual public key
# echo "ssh-ed25519 AAAAC3Nza..." >> ~/.ssh/authorized_keys
chmod 600 ~/.ssh/authorized_keys

echo "Bootstrap complete for $OS!"
