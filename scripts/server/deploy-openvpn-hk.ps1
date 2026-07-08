# Deploy OpenVPN on HK server via SSH
# Uses plink to run commands
$hkHost = "38.76.194.13"
$hkPass = "DtrT4XnmtBwG"
$hkKey = "SHA256:lrXpFN9ZprUFxlX2h1V2eYLL5fqEkyvq4SG3TYLseGc"

$script = @'
set -e
cd /root
wget -q https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh -O openvpn-install.sh 2>/dev/null || curl -sL -o openvpn-install.sh https://raw.githubusercontent.com/Nyr/openvpn-install/master/openvpn-install.sh
chmod +x openvpn-install.sh

if [ -f /etc/openvpn/server/server.conf ]; then
  echo "OpenVPN already installed, adding android client"
  printf '1\nandroid\n' | ./openvpn-install.sh
  cp /root/android.ovpn /root/android.ovpn.bak 2>/dev/null || true
else
  echo "Installing OpenVPN (UDP 1194, client: android)"
  printf '\n\n\nandroid\n ' | ./openvpn-install.sh
fi

# Config may be android.ovpn or client.ovpn
for f in /root/android.ovpn /root/client.ovpn; do
  [ -f "$f" ] && { base64 -w 0 "$f"; echo ""; exit 0; }
done
echo "ERROR: No ovpn found"; ls -la /root/*.ovpn 2>/dev/null; exit 1
'@

$script | plink -ssh -batch -pw $hkPass -hostkey $hkKey root@$hkHost "bash -s"
