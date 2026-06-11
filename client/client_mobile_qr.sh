#!/bin/bash
# move to the script directory.
cd "$(dirname "$0")" || exit 1

# 1 Check qrencode is installed.
if ! command -v qrencode &> /dev/null; then
    echo "ERROR: 'qrencode' is not installed."
    echo "Execute: sudo apt install -y qrencode"
    exit 1
fi

# 2 Check the 'client_linux.sh' is in the actual folder.
if [ ! -f "./client_linux.sh" ]; then
    echo "ERROR: Not found './client_linux.sh' in the same folder."
    exit 1
fi

echo "Starting configurator mobile.."
# Start
./client_linux.sh

# Search in the current directory the files finished in .conf order by newest(ls -t)
CONF_FILE=$(ls -t *.conf 2>/dev/null | head -n 1)

echo "=============================================="
echo "  Scan this QR code with the WireGuard app:"
echo "=============================================="
echo ""
qrencode -t ansiutf8 < "$CONF_FILE"
read -n 1 -s -r -p "Press any key to continue . . ."
echo ""
echo "Removing the temp configuration file '$CONF_FILE'.."
rm "$CONF_FILE"
