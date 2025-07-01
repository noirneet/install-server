#!/bin/bash
set -e

# === Konfigurasi umum ===
VERSION="v2.35.0"
FB_BIN="/usr/local/bin/filebrowser"
FB_CONF_DIR="/etc/filebrowser"
FB_DB="$FB_CONF_DIR/filebrowser.db"
FB_ROOT="/var/www/projects/cloud"
FB_TMP="/var/www/tmp"
FB_NGINX_CONF="/etc/nginx/sites-available/filebrowser-prod.conf"
FB_SYSTEMD="/etc/systemd/system/filebrowser.service"
FB_USER="www-data"
DOMAIN="cloud.midragondev.my.id"
ADMIN_USER="admin"
ADMIN_PASS="nexaryncloud2025;"

function uninstall_prod() {
  echo "🧹 Menghapus Filebrowser production..."

  sudo systemctl stop filebrowser || true
  sudo systemctl disable filebrowser || true
  sudo rm -f "$FB_SYSTEMD"
  sudo systemctl daemon-reload

  sudo rm -f "$FB_BIN"
  sudo rm -rf "$FB_CONF_DIR"
  sudo rm -rf "$FB_ROOT"
  sudo rm -rf "$FB_TMP"

  sudo rm -f "$FB_NGINX_CONF"
  sudo rm -f /etc/nginx/sites-enabled/filebrowser-prod.conf
  sudo nginx -t && sudo systemctl reload nginx

  sudo ufw delete allow 8081 || true

  echo "✅ Filebrowser production berhasil dihapus!"
}

function install_prod() {
  echo "📦 Mengunduh dan memasang Filebrowser production..."
  wget -q https://github.com/filebrowser/filebrowser/releases/download/$VERSION/linux-amd64-filebrowser.tar.gz
  tar -xzf linux-amd64-filebrowser.tar.gz
  sudo mv filebrowser "$FB_BIN"
  rm linux-amd64-filebrowser.tar.gz

  echo "📁 Membuat direktori root dan konfigurasi..."
  sudo mkdir -p "$FB_CONF_DIR" "$FB_ROOT" "$FB_TMP"
  sudo chown -R $FB_USER:$FB_USER "$FB_CONF_DIR" "$(dirname $FB_ROOT)" "$FB_TMP"

  echo "📝 Menulis konfigurasi JSON..."
  sudo tee "$FB_CONF_DIR/filebrowser.json" > /dev/null <<EOF
{
  "port": 8081,
  "baseURL": "",
  "address": "127.0.0.1",
  "log": "stdout",
  "database": "$FB_DB",
  "root": "$FB_ROOT",
  "auth": {
    "method": "basicauth",
    "header": "Authorization"
  }
}
EOF

  echo "🛠️ Membuat systemd service..."
  sudo tee "$FB_SYSTEMD" > /dev/null <<EOF
[Unit]
Description=FileBrowser
After=network.target

[Service]
ExecStart=$FB_BIN -c $FB_CONF_DIR/filebrowser.json
Restart=on-failure
User=$FB_USER

[Install]
WantedBy=multi-user.target
EOF

  echo "👤 Inisialisasi database dan user admin..."
  sudo -u $FB_USER $FB_BIN -c "$FB_CONF_DIR/filebrowser.json" &
  sleep 3
  pkill -f "$FB_BIN -c $FB_CONF_DIR/filebrowser.json" || true

  sudo -u $FB_USER $FB_BIN users add $ADMIN_USER "$ADMIN_PASS" \
    --database "$FB_DB" \
    --perm.admin || \
  sudo -u $FB_USER $FB_BIN users update $ADMIN_USER \
    --password "$ADMIN_PASS" \
    --database "$FB_DB"

  echo "🌐 Membuat konfigurasi NGINX production ($DOMAIN)..."
  sudo tee "$FB_NGINX_CONF" > /dev/null <<EOF
server {
    listen 80;
    server_name $DOMAIN;

    client_max_body_size 1000m;
    client_body_temp_path $FB_TMP;
    proxy_request_buffering off;
    proxy_buffering off;

    client_body_timeout 120s;
    client_header_timeout 120s;
    send_timeout 120s;

    location / {
        proxy_pass http://127.0.0.1:8081;
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection "upgrade";
    }
}
EOF

  sudo ln -sf "$FB_NGINX_CONF" /etc/nginx/sites-enabled/
  sudo nginx -t && sudo systemctl reload nginx

  echo "🚀 Mengaktifkan Filebrowser service..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now filebrowser

  echo "🔥 Membuka port firewall (8081)..."
  sudo ufw allow 8081

  echo "✅ Instalasi production selesai!"
  echo "🌐 Akses: http://$DOMAIN"
  echo "🔐 Login: $ADMIN_USER / $ADMIN_PASS"
}

# === Mode CLI ===
if [[ "$1" == "--install" ]]; then
  install_prod
elif [[ "$1" == "--reset" ]]; then
  uninstall_prod
else
  echo "❌ Gunakan perintah yang benar:"
  echo "   ./install-cloud-prod.sh --install   ← untuk instalasi production"
  echo "   ./install-cloud-prod.sh --reset     ← untuk menghapus production"
  exit 1
fi
