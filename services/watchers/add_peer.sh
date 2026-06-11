#!/bin/bash
# Path to the WireGuard main configuration file
WG_CONF="/etc/wireguard/wg0.conf"

# Verify if user passed the publicKey as an argument, and if not, request it.
if [ -z "$1" ]; then
    read -p "Enter the public key for the new client: " NEW_PUBKEY
else
    NEW_PUBKEY="$1"
fi

if [ -z "$NEW_PUBKEY" ]; then
    echo "Error: The publicKey it can't be empty."
    exit 1
fi

if [ ! -f "$WG_CONF" ]; then
    echo "Error: The $WG_CONF file cannot be found."
    exit 1
fi

# 1.Obtain the last number of client.
# Search lines with '# --- Client X ---', take the last one, and extract only the number.
LAST_CLIENT_NUM=$(grep -oE '# --- Client [0-9]+ ---' "$WG_CONF" | tail -n 1 | grep -oE '[0-9]+')
if [ -z "$LAST_CLIENT_NUM" ]; then LAST_CLIENT_NUM=0; fi
NEW_CLIENT_NUM=$((LAST_CLIENT_NUM + 1))

# 2.Obtain the last ip assigned.
# Search lines with 'AllowedIPs = 10.0.0.X', take the last one, and extract only the last($)number.
LAST_IP_OCTET=$(grep -oE 'AllowedIPs = 10\.0\.0\.[0-9]+' "$WG_CONF" | tail -n 1 | grep -oE '[0-9]+$')
if [ -z "$LAST_IP_OCTET" ]; then LAST_IP_OCTET=1; fi
NEW_IP_OCTET=$((LAST_IP_OCTET + 1))

# 3. Append the configuration parameters in the wireguard configuration file(wg0.conf).
cat <<EOF >> "$WG_CONF"

[Peer]
# --- Client $NEW_CLIENT_NUM ---
PublicKey = $NEW_PUBKEY
AllowedIPs = 10.0.0.$NEW_IP_OCTET/32
EOF

echo "Client $NEW_CLIENT_NUM successfully added (IP: 10.0.0.$NEW_IP_OCTET/32)"

# 4. Restart WireGuard container to apply changes
echo "Restarting WireGuard container ..."
docker restart privateclipserver_wireguard   # The container_name: value of the docker-compose.yml
docker restart privateclipserver_filebrowser # This is necesary for the merge of the networks'network_mode: "service:wireguard"'
docker restart privateclipserver_nginx # The same of the last comment.
#wg syncconf wg0 <(wg-quick strip wg0)