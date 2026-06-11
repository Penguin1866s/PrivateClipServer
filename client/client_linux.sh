#!/bin/bash

echo "=========================================="
echo "  WireGuard Client Creator (Linux/macOS)  "
echo "=========================================="
echo ""

# Request data from user.
read -p "1. Name of the new tunnel connection: " TUNNEL_NAME
read -p "2. Public Key of the Server: " SERVER_PUBLICKEY
read -p "3. Private IP for this client (ex. 10.0.0.2/24): " CLIENT_IP
read -p "4. Server public IP: " SERVER_PUBLIC_IP

# Verify that the WireGuard tool exists.
WIREGUARD_EXE=$(command -v wg)
if [ -z "$WIREGUARD_EXE" ]; then
    echo ""
    echo "ERROR: 'wg' command not found."
    echo "Ensure that WireGuard is installed."
    # This will literally shows "Press any key to continue . . .".
    read -n 1 -s -r -p "Press any key to continue . . ."
    echo ""
    exit 1
fi

# Generate private and public keys.
$WIREGUARD_EXE genkey > temp_private.key
$WIREGUARD_EXE pubkey < temp_private.key > temp_public.key

# Read the variables keys.
PRIVATE_CLIENT_KEY=$(cat temp_private.key)
PUBLIC_CLIENT_KEY=$(cat temp_public.key)

# Create WireGuard configuration file .conf.
CONF_FILE="${TUNNEL_NAME}.conf"

echo "[Interface]" > "$CONF_FILE"
echo "PrivateKey = $PRIVATE_CLIENT_KEY" >> "$CONF_FILE"
echo "Address = $CLIENT_IP" >> "$CONF_FILE"
echo "DNS = 1.1.1.1" >> "$CONF_FILE"
echo "" >> "$CONF_FILE"
echo "[Peer]" >> "$CONF_FILE"
echo "PublicKey = $SERVER_PUBLICKEY" >> "$CONF_FILE"
echo "AllowedIPs = 10.0.0.0/24" >> "$CONF_FILE"
echo "Endpoint = ${SERVER_PUBLIC_IP}:51820" >> "$CONF_FILE"

# Clean the temporal files.
rm temp_private.key
rm temp_public.key

# Show the final result.
echo ""
echo "=========================================="
echo "$CONF_FILE file created successfully!"
echo "=========================================="
echo ""
echo "The public key of the client is:"
echo "$PUBLIC_CLIENT_KEY"
echo ""
echo "1. Create a file in 'keys_inbox' and put in there the public client( '$PUBLIC_CLIENT_KEY' ) to register the client/peer in server (FileBrowser)."
echo "2. In WireGuard select 'Import tunnel from file' and select $CONF_FILE."
echo ""
read -n 1 -s -r -p "Press any key to continue . . ."
echo ""