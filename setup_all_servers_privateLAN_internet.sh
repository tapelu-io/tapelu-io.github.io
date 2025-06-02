#!/bin/bash
# File: setup_all_servers.sh
# One-click build script to prepare full project code for:
# - Server A (Private LAN, no internet)
# - Server R (Relay with dual NIC between LAN A and LAN B)
# - Server B (Internet-facing)
# Includes: WireGuard VPN, MQTT with TLS, ClamAV malware scanning

set -e

WORKDIR="$HOME/secure_bridge_project"
echo "🔧 Creating workspace at $WORKDIR"
rm -rf "$WORKDIR"
mkdir -p "$WORKDIR/serverA" "$WORKDIR/serverR" "$WORKDIR/serverB" "$WORKDIR/certs" "$WORKDIR/keys"

# === Generate WireGuard Key Pairs ===
echo "🔑 Generating WireGuard key pairs..."
wg genkey | tee "$WORKDIR/keys/serverA_private.key" | wg pubkey > "$WORKDIR/keys/serverA_public.key"
wg genkey | tee "$WORKDIR/keys/serverR_private.key" | wg pubkey > "$WORKDIR/keys/serverR_public.key"
wg genkey | tee "$WORKDIR/keys/serverB_private.key" | wg pubkey > "$WORKDIR/keys/serverB_public.key"

# === Generate TLS Certificates ===
echo "🔐 Generating TLS certificates..."
CERTDIR="$WORKDIR/certs"
openssl req -x509 -newkey rsa:2048 -keyout "$CERTDIR/server.key" -out "$CERTDIR/server.crt" -days 365 -nodes -subj "/CN=mosquitto"
cp "$CERTDIR/server.crt" "$CERTDIR/ca.crt"

# === Shared Variables ===
A_PUB=$(cat "$WORKDIR/keys/serverA_public.key")
A_PRIV=$(cat "$WORKDIR/keys/serverA_private.key")
R_PUB=$(cat "$WORKDIR/keys/serverR_public.key")
R_PRIV=$(cat "$WORKDIR/keys/serverR_private.key")
B_PUB=$(cat "$WORKDIR/keys/serverB_public.key")
B_PRIV=$(cat "$WORKDIR/keys/serverB_private.key")

# === Helper: Add generic instructions ===
echo "📘 Creating guide..."
cat > "$WORKDIR/README.txt" <<GUIDE
SECURE BRIDGE PROJECT (Server A + Server R + Server B)
=====================================================

🛠 SETUP
1. Copy the following folders to each respective server:
   - serverA -> Server A (private LAN)
   - serverR -> Server R (dual NIC relay)
   - serverB -> Server B (internet)

2. Replace placeholders in .conf files:
   - <RELAY_PUBLIC_IP> with Server R's public IP from LAN B
   - <SERVER_B_PUBLIC_IP> with Server B's public IP

3. On each server, run:
   chmod +x setup_serverX.sh
   sudo ./setup_serverX.sh

📦 OFFLINE INSTALL (Optional)
Use `dpkg-repack` or manually collect `.deb` files into a `packages/` directory if servers don't have internet access.

🔍 MESSAGE SCANNING
ClamAV is set up on Server B to inspect incoming MQTT messages. Configure Mosquitto plugin or external bridge script to route messages through ClamAV.
GUIDE

# === Server A ===
echo "⚙️ Generating config for Server A..."
mkdir -p "$WORKDIR/serverA/wireguard" "$WORKDIR/serverA/mosquitto" "$WORKDIR/serverA/certs"
cat > "$WORKDIR/serverA/setup_serverA.sh" <<EOF
#!/bin/bash
set -e
echo "Installing offline packages (if provided)..."
sudo dpkg -i ./packages/*.deb || true
sudo apt install -f -y

sudo cp ./wireguard/wg0.conf /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

sudo cp ./mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf
sudo cp ./certs/* /etc/mosquitto/
sudo systemctl restart mosquitto
EOF
chmod +x "$WORKDIR/serverA/setup_serverA.sh"

cat > "$WORKDIR/serverA/wireguard/wg0.conf" <<EOF
[Interface]
Address = 10.10.0.2/24
PrivateKey = $A_PRIV
ListenPort = 51820

[Peer]
PublicKey = $R_PUB
Endpoint = 192.168.100.10:51820
AllowedIPs = 0.0.0.0/0
PersistentKeepalive = 25
EOF

cat > "$WORKDIR/serverA/mosquitto/mosquitto.conf" <<EOF
listener 8883
cafile /etc/mosquitto/ca.crt
certfile /etc/mosquitto/server.crt
keyfile /etc/mosquitto/server.key
require_certificate true
allow_anonymous false
EOF

cp "$CERTDIR"/* "$WORKDIR/serverA/certs/"

# === Server R ===
echo "⚙️ Generating config for Server R..."
mkdir -p "$WORKDIR/serverR/wireguard"
cat > "$WORKDIR/serverR/setup_serverR.sh" <<EOF
#!/bin/bash
set -e

sudo dpkg -i ./packages/*.deb || true
sudo apt install -f -y

sudo cp ./wireguard/wg0.conf /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0
EOF
chmod +x "$WORKDIR/serverR/setup_serverR.sh"

cat > "$WORKDIR/serverR/wireguard/wg0.conf" <<EOF
[Interface]
Address = 10.10.0.1/24
PrivateKey = $R_PRIV
ListenPort = 51820
PostUp = sysctl -w net.ipv4.ip_forward=1; iptables -t nat -A POSTROUTING -o eth1 -j MASQUERADE
PostDown = iptables -t nat -D POSTROUTING -o eth1 -j MASQUERADE

[Peer]
PublicKey = $A_PUB
AllowedIPs = 10.10.0.2/32

[Peer]
PublicKey = $B_PUB
Endpoint = <SERVER_B_PUBLIC_IP>:51820
AllowedIPs = 10.10.0.3/32
EOF

# === Server B ===
echo "⚙️ Generating config for Server B..."
mkdir -p "$WORKDIR/serverB/wireguard" "$WORKDIR/serverB/mosquitto" "$WORKDIR/serverB/certs"
cat > "$WORKDIR/serverB/setup_serverB.sh" <<EOF
#!/bin/bash
set -e
sudo apt update && sudo apt install -y wireguard mosquitto clamav clamav-daemon
sudo freshclam

sudo cp ./wireguard/wg0.conf /etc/wireguard/wg0.conf
sudo systemctl enable wg-quick@wg0
sudo systemctl start wg-quick@wg0

sudo cp ./mosquitto/mosquitto.conf /etc/mosquitto/mosquitto.conf
sudo cp ./certs/* /etc/mosquitto/
sudo systemctl restart mosquitto
EOF
chmod +x "$WORKDIR/serverB/setup_serverB.sh"

cat > "$WORKDIR/serverB/wireguard/wg0.conf" <<EOF
[Interface]
Address = 10.10.0.3/24
PrivateKey = $B_PRIV
ListenPort = 51820

[Peer]
PublicKey = $R_PUB
Endpoint = <RELAY_PUBLIC_IP>:51820
AllowedIPs = 10.10.0.0/24
EOF

cat > "$WORKDIR/serverB/mosquitto/mosquitto.conf" <<EOF
listener 8883
cafile /etc/mosquitto/ca.crt
certfile /etc/mosquitto/server.crt
keyfile /etc/mosquitto/server.key
require_certificate true
allow_anonymous false
EOF

cp "$CERTDIR"/* "$WORKDIR/serverB/certs/"

# === Done ===
echo "✅ COMPLETE!"
echo "📦 Transfer the 'serverA', 'serverR', and 'serverB' folders to respective servers."
echo "📘 Read the README.txt in $WORKDIR for full instructions."
echo "💡 Don't forget to replace <RELAY_PUBLIC_IP> and <SERVER_B_PUBLIC_IP> in wg0.conf files."
