#!/bin/bash

set -e

echo "📦 Mengunduh dan memasang Filebrowser..."
wget -q https://github.com/filebrowser/filebrowser/releases/download/v2.35.0/linux-amd64-filebrowser.tar.gz
tar -xzf linux-amd64-filebrowser.tar.gz
sudo mv filebrowser /usr/local/bin/
rm linux-amd64-filebrowser.tar.gz

echo "📁 Menyiapkan direktori konfigurasi dan root cloud..."
sudo mkdir -p /etc/filebrowser
sudo mkdir -p /var/www/projects/cloud
sudo mkdir -p /var/www/tmp
sudo chown -R www-data:www-data /etc/filebrowser
sudo chown -R www-data:www-data /var/www/projects
sudo chown -R www-data:www-data /var/www/tmp

echo "📝 Membuat file konfigurasi JSON..."
sudo tee /etc/filebrowser/filebrowser.json > /dev/null <<EOF
{
  "port": 8081,
  "baseURL": "",
  "address": "127.0.0.1",
  "log": "stdout",
  "database": "/etc/filebrowser/filebrowser.db",
  "root": "/var/www/projects/cloud",
  "auth": {
    "method": "basicauth",
    "header": "Authorization"
  }
}
EOF

echo "🌐 Mengonfigurasi NGINX untuk proxy port 8181..."
sudo tee /etc/nginx/sites-available/filebrowser.conf > /dev/null <<EOF
server {
    listen 8181;
    listen [::]:8181;
    server_name _;

    client_max_body_size 1000m;
    client_body_temp_path /var/www/tmp;
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

sudo ln -sf /etc/nginx/sites-available/filebrowser.conf /etc/nginx/sites-enabled/
sudo nginx -t && sudo systemctl reload nginx

echo "🛠️ Membuat file systemd service..."
sudo tee /etc/systemd/system/filebrowser.service > /dev/null <<EOF
[Unit]
Description=FileBrowser
After=network.target

[Service]
ExecStart=/usr/local/bin/filebrowser -c /etc/filebrowser/filebrowser.json
Restart=on-failure
User=www-data

[Install]
WantedBy=multi-user.target
EOF

echo "🔄 Reload systemd dan mulai Filebrowser..."
sudo systemctl daemon-reload
sudo systemctl enable --now filebrowser

echo "👤 Membuat user admin (password: nexaryncloud2025;)"
sudo -u www-data /usr/local/bin/filebrowser users add admin 'nexaryncloud2025;' \
  --database /etc/filebrowser/filebrowser.db \
  --perm.admin || \
sudo -u www-data /usr/local/bin/filebrowser users update admin \
  --password 'nexaryncloud2025;' \
  --database /etc/filebrowser/filebrowser.db

echo "🔥 Mengatur firewall UFW..."
sudo ufw allow 8081
sudo ufw allow 8181

echo "✅ Instalasi selesai. Akses Filebrowser di: http://<IP-server>:8181/"
