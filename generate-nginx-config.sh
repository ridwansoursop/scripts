#!/bin/bash
# ============================================================
# Script otomatisasi pembuatan NGINX reverse proxy + SSL
# Mendukung opsi WebSocket (opsional)
# ============================================================

# Hentikan script jika terjadi error, variable kosong, atau pipe gagal
set -euo pipefail

# -------------------------------
# Input dari user
# -------------------------------
read -p "Masukkan domain/subdomain (contoh: sub.domain.tld): " DOMAIN
read -p "Masukkan alamat backend (contoh: http://10.0.0.1:3000): " BACKEND
read -p "Aktifkan WebSocket? (y/n): " ENABLE_WS

# -------------------------------
# Validasi input dasar
# -------------------------------
if [[ -z "$DOMAIN" || -z "$BACKEND" ]]; then
    echo "[X] Domain dan backend tidak boleh kosong"
    exit 1
fi

if [[ ! "$BACKEND" =~ ^https?:// ]]; then
    echo "[X] Backend harus diawali http:// atau https://"
    exit 1
fi

# -------------------------------
# Path file
# -------------------------------
CERT_DST="/etc/pki/tls/certs/${DOMAIN}.pem"
KEY_DST="/etc/pki/tls/private/${DOMAIN}.key"
NGINX_CONF="/etc/nginx/conf.d/${DOMAIN}.conf"

# -------------------------------
# Cegah overwrite konfigurasi tanpa konfirmasi
# -------------------------------
if [[ -f "$NGINX_CONF" ]]; then
    read -p "File ${NGINX_CONF} sudah ada. Timpa? (y/n): " CONFIRM
    [[ ! "$CONFIRM" =~ ^[Yy]$ ]] && echo "[!] Dibatalkan." && exit 0
fi

# -------------------------------
# Konfigurasi WebSocket (opsional)
# -------------------------------
WS_CONFIG=""

if [[ "$ENABLE_WS" =~ ^[Yy]$ ]]; then
    WS_CONFIG=$(cat <<'EOF'
        # Header WebSocket
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";

        # Timeout panjang untuk koneksi persistent
        proxy_read_timeout 36000s;
        proxy_send_timeout 36000s;
EOF
)
    echo "[+] WebSocket diaktifkan"
else
    echo "[+] WebSocket tidak diaktifkan"
fi

# -------------------------------
# Input SSL certificate
# -------------------------------
echo -e "\nTempel isi SSL Certificate (.pem), lalu tekan CTRL+D:"
CERT_CONTENT=$(</dev/stdin)

echo -e "\nTempel isi SSL Certificate Key (.key), lalu tekan CTRL+D:"
KEY_CONTENT=$(</dev/stdin)

# -------------------------------
# Simpan certificate dan key
# -------------------------------
echo "[+] Menyimpan certificate dan key..."

echo "$CERT_CONTENT" | sudo tee "$CERT_DST" > /dev/null
sudo chmod 644 "$CERT_DST"

echo "$KEY_CONTENT" | sudo tee "$KEY_DST" > /dev/null
sudo chmod 600 "$KEY_DST"

# -------------------------------
# Buat konfigurasi NGINX
# -------------------------------
echo "[+] Membuat konfigurasi NGINX..."

sudo tee "$NGINX_CONF" > /dev/null <<EOF
# ============================================================
# HTTP → HTTPS Redirect
# ============================================================
server {
    listen 80;
    server_name ${DOMAIN};
    return 301 https://\$host\$request_uri;
}

# ============================================================
# HTTPS Reverse Proxy
# ============================================================
server {
    listen 443 ssl http2;
    server_name ${DOMAIN};

    access_log /var/log/nginx/${DOMAIN}-access.log;
    error_log  /var/log/nginx/${DOMAIN}-error.log;

    # ---------------------------
    # SSL Configuration
    # ---------------------------
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_certificate     ${CERT_DST};
    ssl_certificate_key ${KEY_DST};
    ssl_session_cache shared:SSL:1m;
    ssl_session_timeout 10m;
    ssl_ciphers PROFILE=SYSTEM;
    ssl_prefer_server_ciphers on;

    # ---------------------------
    # Security Headers (basic)
    # ---------------------------
    add_header X-Frame-Options SAMEORIGIN always;
    add_header X-Content-Type-Options nosniff always;
    add_header Referrer-Policy strict-origin-when-cross-origin always;

    # ---------------------------
    # Reverse Proxy Configuration
    # ---------------------------
    location / {
        include /etc/nginx/conf.d/acl-list.conf;

        proxy_pass ${BACKEND};
        proxy_pass_header Authorization;

        # Header standar reverse proxy
        proxy_set_header Host \$host;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;

        # HTTP 1.1 wajib untuk WebSocket
        proxy_http_version 1.1;

        ${WS_CONFIG}

        # Optimasi proxy
        proxy_buffering off;
        proxy_redirect off;
        client_max_body_size 0;
    }
}
EOF

# -------------------------------
# Test & reload NGINX
# -------------------------------
echo "[+] Mengecek konfigurasi NGINX..."
if sudo nginx -t; then
    echo "[✓] Konfigurasi valid, reload NGINX..."
    sudo systemctl reload nginx
    echo "[✓] Selesai. Config untuk domain ${DOMAIN} siap digunakan."
else
    echo "[X] Konfigurasi NGINX tidak valid. Periksa error di atas."
    exit 1
fi
