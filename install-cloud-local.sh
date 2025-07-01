#!/bin/bash
set -e

# === Konfigurasi dasar ===
VERSION="v2.35.0"
FB_BIN="/usr/local/bin/filebrowser"
FB_CONF_DIR="/etc/filebrowser"
FB_DB="$FB_CONF_DIR/filebrowser.db"
FB_ROOT="/var/www/projects/cloud"
FB_TMP="/var/www/tmp"
FB_NGINX_CONF="/etc/nginx/sites-available/filebrowser.conf"
FB_SYSTEMD="/etc/systemd/system/filebrowser.service"
FB_USER="www-data"
ADMIN_USER="admin"
ADMIN_PASS="nexaryncloud2025;"

function uninstall_filebrowser() {
  echo "🧹 Menghapus Filebrowser..."

  echo "🛑 Stop dan disable service..."
  sudo systemctl stop filebrowser || true
  sudo systemctl disable filebrowser || true
  sudo rm -f "$FB_SYSTEMD"
  sudo systemctl daemon-reload

  echo "🗑️ Hapus binary dan config..."
  sudo rm -f "$FB_BIN"
  sudo rm -rf "$FB_CONF_DIR"

  echo "🗑️ Hapus direktori data..."
  sudo rm -rf "$FB_ROOT"
  sudo rm -rf "$FB_TMP"

  echo "🗑️ Hapus konfigurasi NGINX..."
  sudo rm -f "$FB_NGINX_CONF"
  sudo rm -f "/etc/nginx/sites-enabled/filebrowser.conf"
  sudo nginx -t && sudo systemctl reload nginx

  echo "🔒 Tutup firewall port..."
  sudo ufw delete allow 8081 || true
  sudo ufw delete allow 8181 || true

  echo "✅ Filebrowser berhasil dihapus!"
}

function install_filebrowser() {
  echo "📦 Mengunduh dan memasang Filebrowser..."
  wget -q https://github.com/filebrowser/filebrowser/releases/download/$VERSION/linux-amd64-filebrowser.tar.gz
  tar -xzf linux-amd64-filebrowser.tar.gz
  sudo mv filebrowser "$FB_BIN"
  rm linux-amd64-filebrowser.tar.gz

  echo "📁 Menyiapkan direktori konfigurasi dan root cloud..."
  sudo mkdir -p "$FB_CONF_DIR"
  sudo mkdir -p "$FB_ROOT"
  sudo mkdir -p "$FB_TMP"
  sudo chown -R $FB_USER:$FB_USER "$FB_CONF_DIR"
  sudo chown -R $FB_USER:$FB_USER "$(dirname $FB_ROOT)"
  sudo chown -R $FB_USER:$FB_USER "$FB_TMP"

  echo "📝 Membuat file konfigurasi JSON..."
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

  echo "👤 Inisialisasi database dan admin user..."
  sudo -u $FB_USER $FB_BIN -c "$FB_CONF_DIR/filebrowser.json" &
  sleep 3
  pkill -f "$FB_BIN -c $FB_CONF_DIR/filebrowser.json" || true

  sudo -u $FB_USER $FB_BIN users add $ADMIN_USER "$ADMIN_PASS" \
    --database "$FB_DB" \
    --perm.admin || \
  sudo -u $FB_USER $FB_BIN users update $ADMIN_USER \
    --password "$ADMIN_PASS" \
    --database "$FB_DB"

  echo "🌐 Mengonfigurasi NGINX untuk port 8181..."
  sudo tee "$FB_NGINX_CONF" > /dev/null <<EOF
server {
    listen 8181;
    listen [::]:8181;
    server_name _;

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

  echo "🚀 Menyalakan Filebrowser service..."
  sudo systemctl daemon-reload
  sudo systemctl enable --now filebrowser

  echo "🔥 Mengatur firewall UFW..."
  sudo ufw allow 8081
  sudo ufw allow 8181

  echo "✅ Instalasi selesai!"
  echo "🌐 Akses Filebrowser: http://<IP-server>:8181/"
  echo "🔐 Login: $ADMIN_USER / $ADMIN_PASS"
}

# === Mode CLI ===
if [[ "$1" == "--install" ]]; then
  install_filebrowser
elif [[ "$1" == "--reset" ]]; then
  uninstall_filebrowser
else
  echo "❌ Gunakan dengan benar:"
  echo "   ./install-cloud.sh --install   ← untuk menginstal Filebrowser"
  echo "   ./install-cloud.sh --reset     ← untuk menghapus total"
  exit 1
fi
