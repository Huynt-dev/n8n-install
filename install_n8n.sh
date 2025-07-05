#!/bin/bash

# ✅ Yêu cầu root
if [[ $EUID -ne 0 ]]; then
   echo "❌ Script cần được chạy với quyền root"
   exit 1
fi

echo "🛠️ Cài đặt Docker + Docker Compose..."
apt-get update
apt-get install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add -
add-apt-repository -y "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose

echo "🌐 Nhập domain/subdomain bạn muốn dùng cho n8n:"
read -p "🔹 Domain: " DOMAIN

echo "🧱 Nhập tên profile (vd: team1, crm, analytics...):"
read -p "🔹 Profile: " PROFILE

# Kiểm tra DNS đã trỏ chưa
SERVER_IP=$(curl -s https://api.ipify.org)
DOMAIN_IP=$(dig +short "$DOMAIN")

if [ "$DOMAIN_IP" != "$SERVER_IP" ]; then
  echo "❌ Domain chưa trỏ đúng về VPS."
  echo "💡 Trỏ domain $DOMAIN ➜ $SERVER_IP rồi chạy lại."
  exit 1
fi

# Thư mục chứa cấu hình
BASE_DIR="/opt/n8n_$PROFILE"
mkdir -p $BASE_DIR/data
mkdir -p $BASE_DIR/caddy

# ✅ Caddyfile
cat <<EOF > $BASE_DIR/caddy/Caddyfile
$DOMAIN {
  reverse_proxy n8n_$PROFILE:5678
}
EOF

# ✅ docker-compose.yml
cat <<EOF > $BASE_DIR/docker-compose.yml
version: "3"

services:
  n8n_$PROFILE:
    image: n8nio/n8n
    restart: always
    environment:
      - N8N_HOST=$DOMAIN
      - N8N_PORT=5678
      - N8N_PROTOCOL=https
      - WEBHOOK_URL=https://$DOMAIN
      - N8N_BASIC_AUTH_ACTIVE=true
      - N8N_BASIC_AUTH_USER=admin
      - N8N_BASIC_AUTH_PASSWORD=admin123
      - GENERIC_TIMEZONE=Asia/Ho_Chi_Minh
    volumes:
      - $BASE_DIR/data:/home/node/.n8n
    networks:
      - n8n_net

  caddy_$PROFILE:
    image: caddy:2
    restart: always
    ports:
      - "80"
      - "443"
    volumes:
      - $BASE_DIR/caddy/Caddyfile:/etc/caddy/Caddyfile
      - caddy_data_$PROFILE:/data
      - caddy_config_$PROFILE:/config
    depends_on:
      - n8n_$PROFILE
    networks:
      - n8n_net

networks:
  n8n_net:
    driver: bridge

volumes:
  caddy_data_$PROFILE:
  caddy_config_$PROFILE:
EOF

# ✅ Phân quyền
chown -R 1000:1000 $BASE_DIR
chmod -R 755 $BASE_DIR

# ✅ Khởi động container
cd $BASE_DIR
docker-compose up -d

echo ""
echo "✅ Đã triển khai profile n8n: $PROFILE"
echo "🌐 Truy cập: https://$DOMAIN"
echo "🔐 Tài khoản: admin / admin123"
echo ""
