#!/bin/bash
set -e
cd /root
wget -q https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O openvpn-install.sh 2>/dev/null || curl -sL -o openvpn-install.sh https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

if [ -f /etc/openvpn/server/server.conf ]; then
  echo "OpenVPN already installed, adding android client"
  printf '1\nandroid\n' | ./openvpn-install.sh
else
  echo "Installing OpenVPN (UDP 1194, client: android)"
  printf '\n\n\nandroid\n ' | ./openvpn-install.sh
fi

for f in /root/android.ovpn /root/client.ovpn; do
  if [ -f "$f" ]; then
    base64 -w 0 "$f"
    echo ""
    exit 0
  fi
done
echo "ERROR: No ovpn found"
ls -la /root/*.ovpn 2>/dev/null || true
exit 1
