#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# 1. Update and upgrade the system packages
sudo apt update && sudo apt upgrade -y

# 2. Add the official CrowdSec repository and install CrowdSec core
curl -s https://install.crowdsec.net | sudo sh
sudo apt update && sudo apt install crowdsec -y

# 3. Create config directory, install and enable nftables
sudo mkdir -p /etc/crowdsec/bouncers/
sudo apt install nftables -y
sudo systemctl enable --now nftables

# 4. Install the nftables firewall bouncer package
sudo apt install crowdsec-firewall-bouncer-nftables -y

# 5. Wait for the CrowdSec Local API to fully start up
echo "Waiting for CrowdSec API to start..."
sleep 5

# 6. Generate the API key in a single line to avoid terminal line-break issues
sudo cscli bouncers delete server-bouncer > /dev/null 2>&1
NEW_KEY=$(sudo cscli bouncers add server-bouncer -o raw | tr -d '\r\n ')
# Verify if the API key was successfully generated
if [ -z "$NEW_KEY" ]; then
    echo "Error: Failed to generate API key!"
    exit 1
fi

# 7. Write the clean configuration file with correct YAML indentations
sudo tee /etc/crowdsec/bouncers/crowdsec-firewall-bouncer.yaml > /dev/null <<EOT
mode: nftables
api_url: http://127.0.0
api_key: ${NEW_KEY}
log_mode: file
log_dir: /var/log/
log_level: info
nftables:
  ipv4_table: crowdsec
  ipv6_table: crowdsec6
  deny_action: drop
  deny_log: false
  blacklists_group: crowdsec-blacklists
EOT

# 8. Restart and enable the firewall bouncer service
sudo systemctl restart crowdsec-firewall-bouncer
sudo systemctl enable crowdsec-firewall-bouncer

# 9. Verify the active bouncers list
echo "--- Active CrowdSec Bouncers List ---"
sudo cscli bouncers list