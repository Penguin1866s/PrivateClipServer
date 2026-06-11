#!/bin/bash

WG_DIR="/etc/wireguard"
WG_CONF="$WG_DIR/wg0.conf"

# Check if the configuration file already exists
if [ ! -f "$WG_CONF" ]; then
    echo "Configuration not found. Generating keys and wg0.conf..."
    
    # Set permissions for the folder
    umask 077
    
    # Generate keys
    wg genkey | tee "$WG_DIR/privatekey" | wg pubkey > "$WG_DIR/publickey"
    
    # Read the generated private key into a variable
    PRIVATE_KEY=$(cat "$WG_DIR/privatekey")
    
    # Generate the wg0.conf file dynamically
    cat <<EOF > "$WG_CONF"
[Interface]
PrivateKey = $PRIVATE_KEY
Address = 10.0.0.1/24
ListenPort = 51820

# In Docker, the output interface is almost always eth0
PostUp = iptables -A FORWARD -i %i -j ACCEPT; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
PostDown = iptables -D FORWARD -i %i -j ACCEPT; iptables -t nat -D POSTROUTING -o eth0 -j MASQUERADE

#[Peer]
# --- Client N ---
#PublicKey = <CLIENT_PUBLIC_KEY> # example of a valid value "cwQTrSoYV3UXgsD3aFsfcDj/rscR08tBzJ6APfy2WDA="
#PublicKey = [this is a template for the 'add_peer.sh']
#AllowedIPs = 10.0.0.1/32
EOF

    echo "Initial configuration generated successfully."
else
    echo "Configuration found. Skipping generation."
fi

# Start the WireGuard interface
wg-quick up wg0

# Keep the container running infinitely
sleep infinity