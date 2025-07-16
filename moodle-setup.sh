#!/bin/bash

### 🇻🇳 Script Triển khai Moodle + Proxy nội bộ + DNS LAN + Backup/Restore ###
# Dành cho hệ thống nội bộ, sử dụng tên miền như: http://moodle.lan
# Yêu cầu: Ubuntu 22.04+, quyền root

set -e

## ----------- 1. Biến cấu hình ----------- ##
MOODLE_VERSION="4.3.4"
MOODLE_DIR="/var/www/moodle"
DATA_DIR="/var/moodledata"
DB_NAME="moodle"
DB_USER="moodleuser"
DB_PASS="StrongPassword123!"
DB_HOST="localhost"
BACKUP_DIR="/var/backups/moodle"
MOODLE_DOMAIN="moodle.lan"
PROXY_PORT=80
MOODLE_INTERNAL_PORT=8080

## ----------- 2. Cài gói hệ thống ----------- ##
echo "[+] Cài Apache, PHP, MariaDB, nginx, dnsmasq..."
apt update && apt install -y \
    apache2 mariadb-server \
    php php-cli php-curl php-gd php-intl php-mbstring \
    php-mysql php-xml php-zip php-soap php-bcmath php-readline \
    php-opcache unzip git curl graphviz imagemagick php-imagick \
    nginx dnsmasq

systemctl enable apache2 mariadb nginx dnsmasq

## ----------- 3. Cấu hình MariaDB ----------- ##
echo "[+] Cấu hình CSDL..."
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS ${DB_NAME} DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON ${DB_NAME}.* TO '${DB_USER}'@'${DB_HOST}';
FLUSH PRIVILEGES;
EOF

## ----------- 4. Tải và triển khai Moodle ----------- ##
echo "[+] Tải Moodle..."
mkdir -p ${MOODLE_DIR} ${DATA_DIR}
cd /tmp && curl -L -o moodle.tgz https://download.moodle.org/download.php/direct/stable43/moodle-latest-43.tgz
tar -xzf moodle.tgz -C /var/www
chown -R www-data:www-data ${MOODLE_DIR} ${DATA_DIR}
chmod -R 755 ${MOODLE_DIR} ${DATA_DIR}

## ----------- 5. Apache chạy cổng nội bộ 8080 ----------- ##
sed -i 's/Listen 80/Listen 8080/' /etc/apache2/ports.conf
sed -i 's/<VirtualHost \*:80>/<VirtualHost *:8080>/' /etc/apache2/sites-available/000-default.conf
systemctl restart apache2

## ----------- 6. Cài proxy ngược với nginx ----------- ##
echo "[+] Cấu hình proxy nginx cho ${MOODLE_DOMAIN}"
cat <<EOF >/etc/nginx/sites-available/${MOODLE_DOMAIN}
server {
    listen ${PROXY_PORT};
    server_name ${MOODLE_DOMAIN};

    location / {
        proxy_pass         http://127.0.0.1:${MOODLE_INTERNAL_PORT};
        proxy_set_header   Host \$host;
        proxy_set_header   X-Real-IP \$remote_addr;
        proxy_set_header   X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header   X-Forwarded-Proto \$scheme;
    }
}
EOF

ln -sf /etc/nginx/sites-available/${MOODLE_DOMAIN} /etc/nginx/sites-enabled/
systemctl reload nginx

## ----------- 7. Cài DNS nội bộ với dnsmasq ----------- ##
echo "[+] Cấu hình dnsmasq cho tên miền nội bộ ${MOODLE_DOMAIN}"
echo "address=/${MOODLE_DOMAIN}/127.0.0.1" >> /etc/dnsmasq.conf
systemctl restart dnsmasq

## ----------- 8. Cài theme và tiếng Việt ----------- ##
echo "[+] Cài giao diện Moove và gói ngôn ngữ tiếng Việt..."
sudo -u www-data php ${MOODLE_DIR}/admin/cli/install_plugin.php --plugins=theme_moove --allow-unstable || true
mkdir -p ${MOODLE_DIR}/data/lang
cd ${MOODLE_DIR}/data/lang && curl -O https://download.moodle.org/langpack/4.3/vi.zip
unzip -o vi.zip -d ${MOODLE_DIR}/lang
chown -R www-data:www-data ${MOODLE_DIR}/lang

## ----------- 9. Tạo script backup ----------- ##
echo "[+] Tạo backup_moodle.sh..."
cat <<EOF >/usr/local/bin/backup_moodle.sh
#!/bin/bash
mkdir -p ${BACKUP_DIR}
NOW=\$(date +"%Y%m%d-%H%M%S")
tar -czf ${BACKUP_DIR}/moodledata-\$NOW.tar.gz ${DATA_DIR}
tar -czf ${BACKUP_DIR}/moodlecode-\$NOW.tar.gz ${MOODLE_DIR}
mysqldump -u ${DB_USER} -p${DB_PASS} ${DB_NAME} > ${BACKUP_DIR}/moodledb-\$NOW.sql
echo "[✓] Backup xong tại ${BACKUP_DIR}"
EOF
chmod +x /usr/local/bin/backup_moodle.sh

## ----------- 10. Tạo script restore ----------- ##
echo "[+] Tạo restore_moodle.sh..."
cat <<EOF >/usr/local/bin/restore_moodle.sh
#!/bin/bash
LATEST_DATA=\$(ls -t ${BACKUP_DIR}/moodledata-*.tar.gz | head -n1)
LATEST_CODE=\$(ls -t ${BACKUP_DIR}/moodlecode-*.tar.gz | head -n1)
LATEST_DB=\$(ls -t ${BACKUP_DIR}/moodledb-*.sql | head -n1)

tar -xzf \$LATEST_CODE -C /
tar -xzf \$LATEST_DATA -C /
mysql -u ${DB_USER} -p${DB_PASS} ${DB_NAME} < \$LATEST_DB
chown -R www-data:www-data ${MOODLE_DIR} ${DATA_DIR}
echo "[✓] Phục hồi xong"
EOF
chmod +x /usr/local/bin/restore_moodle.sh

## ----------- 11. Hướng dẫn cuối ----------- ##
echo "[✓] Đã hoàn tất! Moodle có thể truy cập qua:"
echo "    → http://${MOODLE_DOMAIN}/ (nếu client dùng DNS nội bộ hoặc chỉnh /etc/hosts)"
echo "# ➕ Thông tin CSDL: DB=${DB_NAME}, user=${DB_USER}, pass=${DB_PASS}"
echo "# ➕ Script backup: /usr/local/bin/backup_moodle.sh"
echo "# ➕ Script restore: /usr/local/bin/restore_moodle.sh"
echo "# ➕ DNS nội bộ: dnsmasq đã trỏ moodle.lan về localhost"
echo "# ➕ Nginx proxy: moodle.lan:80 → Apache:8080"

echo "✅ Truy cập Moodle Mobile App với http://${MOODLE_DOMAIN} nếu cùng mạng"

exit 0
