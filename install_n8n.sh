#!/bin/bash

set -e

if [[ $EUID -ne 0 ]]; then
   echo "❌ Script must be run as root"
   exit 1
fi

read -p "Enter your domain (must already point to this VPS): " DOMAIN

# Kiểm tra domain
SERVER_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN" | tail -n1)
if [[ "$SERVER_IP" != "$DOMAIN_IP" ]]; then
  echo "❌ $DOMAIN is not pointing to this server (Expected: $SERVER_IP | Found: $DOMAIN_IP)"
  exit 1
fi

echo "✅ Domain is correctly pointed."

# ===============================
# ✅ CÀI ĐẶT DOCKER + COMPOSE
# ===============================

echo "🛠️ Installing Docker via get.docker.com script..."
curl -fsSL https://get.docker.com | sh

echo "🛠️ Installing docker compose plugin..."
apt-get install -y docker-compose-plugin

# ===============================
# 📁 TẠO FOLDER & VOLUME
# ===============================

mkdir -p /home/n8n-data/.n8n
mkdir -p /home/n8n-data/custom_nodes
chown -R 1000:1000 /home/n8n-data

# ===============================
# 🧾 TẠO FILE docker-compose.yml
# ===============================

cat <<EOF > /home/n8n-data/docker-compose.yml
version: '3'
services:
  n8n:
    image: n8nio/n8n:latest
    container_name: n8n
    restart: always
    environment:
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN
      - NODE_ENV=production
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
      - N8N_DISABLE_PRODUCTION_MAIN_PROCESS=true
    volumes:
      - /home/n8n-data/.n8n:/home/node/.n8n
      - /home/n8n-data/custom_nodes:/home/node/custom_nodes
    working_dir: /home/node/.n8n
    networks:
      - n8n_net
    command: >
      /bin/sh -c "npm install /home/node/custom_nodes/* || true && n8n"

  caddy:
    image: caddy:2
    container_name: caddy
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

# ===============================
# 📄 TẠO FILE Caddyfile
# ===============================

cat <<EOF > /home/n8n-data/Caddyfile
$DOMAIN {
    reverse_proxy n8n:5678
}
EOF

# ===============================
# 🚀 KHỞI ĐỘNG DỊCH VỤ
# ===============================

cd /home/n8n-data
docker compose up -d

echo ""
echo "🎉 Installed successfully! Visit: https://$DOMAIN"
