#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "Script must be run as root"
   exit 1
fi

read -p "Enter your domain (must already point to this VPS): " DOMAIN

# Check domain DNS
SERVER_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  echo "❌ $DOMAIN is not pointing to this server (Expected: $SERVER_IP | Found: $DOMAIN_IP)"
  exit 1
fi

echo "✅ Domain is correctly pointed."

echo "▶️ Installing Docker & Compose..."
apt-get update
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

echo "✅ Docker installed."

# Tạo thư mục và đặt quyền đúng
mkdir -p /home/n8n-data
chown -R 1000:1000 /home/n8n-data
chmod -R 755 /home/n8n-data

# Ghi docker-compose.yml
cat <<EOF > /home/n8n-data/docker-compose.yml
version: '3.8'
services:
  n8n:
    image: n8nio/n8n:0.228.2
    restart: always
    environment:
      - N8N_HOST=${DOMAIN}
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://${DOMAIN}
      - NODE_ENV=production
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_ENFORCE_SETTINGS_FILE_PERMISSIONS=true
    user: "1000:1000"
    volumes:
      - /home/n8n-data:/home/node/.n8n
    networks:
      - n8n_net

  caddy:
    image: caddy:2
    restart: always
    ports:
      - "80:80"
      - "443:443"
    volumes:
      - /home/n8n-data/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data:/data
      - caddy_config:/config
    depends_on:
      - n8n
    networks:
      - n8n_net

networks:
  n8n_net:
    driver: bridge

volumes:
  caddy_data:
  caddy_config:
EOF

# Ghi Caddyfile
cat <<EOF > /home/n8n-data/Caddyfile
${DOMAIN} {
  reverse_proxy n8n:5678
}
EOF

# Chạy
cd /home/n8n-data
docker compose up -d

echo ""
echo "🎉 Installed successfully! Visit: https://${DOMAIN}"
