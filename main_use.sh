#!/bin/bash

sudo docker compose up -d --build
#sudo docker compose down --rmi all --remove-orphans

echo "=========================================="
echo "FOR CLIENTS:"
echo "=========================================="
echo
echo "The first admin password: "
#sudo docker logs privateclipserver_filebrowser 2>&1 | grep -oP "User 'admin' initialized with randomly generated password: \K.*"
sudo docker logs privateclipserver_filebrowser 2>&1 | grep -oP "password: \K.*"
# -o   ---> only matching(not output the complete line).
# -P   ---> enable Regular Expresions(PCRE -> Perl Compatible Regular Expressions).

# \K  --> discard everything that was matched so far.
# .*  --> Any character and those who remain.
echo
echo "Public Key of Server:"
sudo docker exec privateclipserver_wireguard cat /etc/wireguard/publickey
echo
echo "The last ip client assigned: "
sudo docker exec privateclipserver_wireguard cat /etc/wireguard/wg0.conf | grep -oP "AllowedIPs = \K.*" | tail -n1
echo
echo "The public ip Server:"
curl ifconfig.me
echo