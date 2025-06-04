#!/bin/bash

# Strict mode
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # The return value of a pipeline is the status of the last command to exit with a non-zero status,
                # or zero if no command exited with a non-zero status.

# --- Configuration & Constants ---
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

PACK_DIR="${SCRIPT_DIR}/packages"       # Contains .deb or .rpm OS packages
DOCKER_DIR="${SCRIPT_DIR}/docker_images" # Contains .tar files of Docker images
APPS_DIR="${SCRIPT_DIR}/apps"           # Contains app-specific files (docker-compose.yml, configs, web files for Nextcloud)
                                        # Example: $APPS_DIR/gitea/docker-compose.yml, $APPS_DIR/nextcloud/ (PHP files)
SCRIPTS_DIR="${SCRIPT_DIR}/scripts"       # Contains helper scripts (backup.sh, custom configs like dnsmasq.conf)
# DOCS_DIR is now part of APPS_DIR or a specific app like BookStack/Wiki.js handles docs.

# --- Logging Helper Functions ---
log_info() { echo "INFO: $1"; }
log_success() { echo "SUCCESS: $1"; }
log_warning() { echo "WARNING: $1"; }
log_error() { echo "ERROR: $1" >&2; }

# --- Pre-flight Checks ---
log_info "🚀 Starting comprehensive offline enterprise server installation..."
if [[ "$EUID" -ne 0 ]]; then
  log_error "This script must be run as root. Please use sudo."
  exit 1
fi

# --- OS Detection ---
OS_ID=""
OS_VERSION_ID=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID,,}"
    OS_VERSION_ID="${VERSION_ID,,}"
elif type lsb_release >/dev/null 2>&1; then
    OS_ID=$(lsb_release -si | tr '[:upper:]' '[:lower:]')
    OS_VERSION_ID=$(lsb_release -sr | tr '[:upper:]' '[:lower:]')
else
    OS_ID="unknown"
fi
log_info "🖥️ Detected OS: $OS_ID $OS_VERSION_ID"

# --- Network Configuration ---
PRIMARY_IP=$(hostname -I 2>/dev/null | awk '{print $1}')
if [ -z "$PRIMARY_IP" ]; then
    log_warning "Could not automatically determine primary IP address. Using 127.0.0.1 as fallback for display."
    PRIMARY_IP="127.0.0.1"
fi
log_info "🌐 Primary IP Address detected/set to: $PRIMARY_IP (Ensure this is the LAN IP for service access)"

# --- Helper Functions ---
command_exists() { command -v "$1" &> /dev/null; }

install_os_packages() {
    log_info "📦 Installing OS-level packages from $PACK_DIR..."
    local pkg_count=0
    if [[ "$OS_ID" == "ubuntu" || "$OS_ID" == "debian" ]]; then
        pkg_count=$(find "$PACK_DIR" -maxdepth 1 -name "*.deb" -type f -print 2>/dev/null | wc -l)
        if [ "$pkg_count" -gt 0 ]; then
            dpkg -i "$PACK_DIR"/*.deb || log_warning "Some .deb packages might have had installation issues."
            log_info "🛠️ Attempting to fix broken dependencies (if any)..."
            if apt-get install --fix-broken --no-install-recommends -y; then
                log_success "DEB package dependency resolution complete."
            else
                log_error "Failed to fix broken dependencies. Ensure all .deb files and their dependencies are in $PACK_DIR."
            fi
        else
            log_info "ℹ️ No .deb packages found in $PACK_DIR."
        fi
    elif [[ "$OS_ID" == "almalinux" || "$OS_ID" == "centos" || "$OS_ID" == "rocky" || "$OS_ID" == "rhel" ]]; then
        pkg_count=$(find "$PACK_DIR" -maxdepth 1 -name "*.rpm" -type f -print 2>/dev/null | wc -l)
        if [ "$pkg_count" -gt 0 ]; then
            if dnf install -y --disablerepo="*" "$PACK_DIR"/*.rpm; then
                log_success "RPM package installation complete."
            else
                log_error "Failed to install RPM packages. Ensure all .rpm files and their dependencies are in $PACK_DIR."
            fi
        else
            log_info "ℹ️ No .rpm packages found in $PACK_DIR."
        fi
    else
        log_warning "OS package installation skipped: Unsupported OS ($OS_ID)."
    fi
}

load_all_docker_images() {
    log_info "🐋 Loading all Docker images from $DOCKER_DIR..."
    if ! command_exists "docker"; then
        log_error "Docker command not found. Cannot load Docker images."
        return 1
    fi
    local tar_files_count
    tar_files_count=$(find "$DOCKER_DIR" -maxdepth 1 -name "*.tar" -type f -print 2>/dev/null | wc -l)

    if [ "$tar_files_count" -gt 0 ]; then
        for img_tar_file in "$DOCKER_DIR"/*.tar; do
            log_info "⏳ Loading Docker image from $img_tar_file..."
            if docker load -i "$img_tar_file"; then
                log_success "Successfully loaded $img_tar_file."
            else
                log_warning "⚠️ Failed to load Docker image from $img_tar_file."
            fi
        done
    else
        log_info "ℹ️ No Docker image .tar files found in $DOCKER_DIR."
    fi
}

manage_system_service() {
    local service_name="$1"
    local action="${2:-enable_start}"
    local service_exists=false

    # Check if service file exists
    if systemctl list-unit-files | grep -qw "$service_name.service"; then
        service_exists=true
    elif systemctl list-unit-files | grep -qw "$service_name"; then # For services like cockpit.socket
        service_exists=true
    fi

    if ! $service_exists; then
        log_warning "Service unit '$service_name' not found. Cannot manage it."
        return 1
    fi

    log_info "⚙️ Managing service: $service_name (Action: $action)..."
    case "$action" in
        enable_start)
            if systemctl enable --now "$service_name"; then log_success "✅ Service $service_name enabled and started."; else log_error "❌ Failed to enable/start $service_name."; fi ;;
        restart)
            if systemctl restart "$service_name"; then log_success "✅ Service $service_name restarted."; else log_error "❌ Failed to restart $service_name."; fi ;;
        start)
            if systemctl start "$service_name"; then log_success "✅ Service $service_name started."; else log_error "❌ Failed to start $service_name."; fi ;;
        stop)
            if systemctl stop "$service_name"; then log_success "✅ Service $service_name stopped."; else log_error "❌ Failed to stop $service_name."; fi ;;
        enable)
            if systemctl enable "$service_name"; then log_success "✅ Service $service_name enabled."; else log_error "❌ Failed to enable $service_name."; fi ;;
        *) log_error "Unsupported action '$action' for manage_system_service." ;;
    esac
}

# Helper to deploy a Docker Compose application
# Assumes $APPS_DIR/{app_name}/docker-compose.yml (or .yaml) exists
# Assumes $APPS_DIR/{app_name}/.env file might exist for environment variables
deploy_docker_compose_app() {
    local app_name="$1"
    local app_url_path="${2:-$app_name}" # URL path if different from app_name
    local app_display_name="${3:-$app_name}" # Display name for messages
    local app_port_info="${4:-}" # Optional port info string for display

    local app_path="${APPS_DIR}/${app_name}"
    local compose_file_yml="${app_path}/docker-compose.yml"
    local compose_file_yaml="${app_path}/docker-compose.yaml"
    local final_compose_file=""

    log_info "--- Deploying $app_display_name ---"
    if [ ! -d "$app_path" ]; then
        log_warning "$app_display_name directory ($app_path) not found. Skipping."
        return
    fi

    if [ -f "$compose_file_yml" ]; then
        final_compose_file="$compose_file_yml"
    elif [ -f "$compose_file_yaml" ]; then
        final_compose_file="$compose_file_yaml"
    else
        log_warning "No docker-compose.yml or .yaml found in $app_path for $app_display_name. Skipping."
        return
    fi

    log_info "Found compose file: $final_compose_file"
    # Create data directories referenced in docker-compose.yml if they don't exist (common pattern)
    # This is a heuristic. Specific volume paths should be managed carefully.
    # Example: grep for volume paths like './data:/some/path' or '/opt/appname_data:/some/path' in compose file
    # and mkdir -p them. For simplicity, this script assumes volumes are handled or user creates them.
    # mkdir -p "${app_path}/data" # Common pattern, but might not always be './data'

    log_info "Starting $app_display_name from $final_compose_file..."
    if docker-compose -f "$final_compose_file" --project-directory "$app_path" up -d; then
        log_success "$app_display_name deployed."
        if [ -n "$app_port_info" ]; then
             log_info "Access $app_display_name at: http://$PRIMARY_IP:$app_port_info (direct) or http://$PRIMARY_IP/$app_url_path (via reverse proxy if configured)"
        else
             log_info "Access $app_display_name at: http://$PRIMARY_IP/$app_url_path (via reverse proxy if configured)"
        fi
    else
        log_error "Failed to deploy $app_display_name. Check logs with 'docker-compose -f \"$final_compose_file\" --project-directory \"$app_path\" logs'."
    fi
}


# --- ======================== Installation Steps ========================== ---

# --- 1. Install Base OS Packages & System Tools ---
log_info "--- Section 1: Installing OS Packages & System Tools ---"
# Essential tools: curl, wget, git, tar, unzip, common utilities, UFW, Fail2ban, Chrony/NTP, Docker, Nginx, Samba, MariaDB, etc.
# These *must* be in $PACK_DIR for offline install.
install_os_packages

# Verify key commands are now available
for cmd in docker docker-compose nginx smbd mysqld cockpit-ws dnsmasq ufw fail2ban-client chronyc; do
    if ! command_exists "$cmd"; then
        log_warning "Command '$cmd' not found after package installation. Associated services might not work."
    fi
done
if ! command_exists "docker-compose"; then
    log_warning "Command 'docker-compose' (v1 or compatible v2 alias) not found. Docker Compose applications cannot be deployed."
fi

# --- 2. Configure and Start Core System Services ---
log_info "--- Section 2: Configuring and Starting Core System Services ---"

manage_system_service sshd # SSH Daemon
if command_exists "docker"; then manage_system_service docker; fi # Docker Engine

# Time Synchronization (Chrony example)
if command_exists "chronyc"; then
    # Ensure chrony.conf in $SCRIPTS_DIR allows local NTP serving if desired or configured for specific peers.
    # For a fully offline LAN, one server should be an NTP server for others.
    # This basic setup just enables the client.
    # if [ -f "${SCRIPTS_DIR}/chrony.conf" ]; then
    #   cp "${SCRIPTS_DIR}/chrony.conf" /etc/chrony/chrony.conf # or /etc/chrony.conf
    # fi
    manage_system_service chronyd # or chrony, depending on OS
    log_info "Chrony (NTP client) service managed. Ensure it's configured to sync with a local NTP server or a designated server in your LAN."
else
    log_warning "Chrony (chronyc) not found. Time synchronization might be an issue."
fi

# Firewall (UFW - Uncomplicated Firewall)
if command_exists "ufw"; then
    log_info "Configuring Firewall (UFW)..."
    ufw allow ssh     # 22/tcp
    ufw allow http    # 80/tcp
    ufw allow https   # 443/tcp
    ufw allow 9090/tcp # Cockpit
    ufw allow 19999/tcp # Netdata
    # Add more rules as needed for Jitsi (UDP ports!), Samba, etc.
    # Example Jitsi ports (can be extensive): 10000/udp, 3478/udp, 5349/tcp
    ufw allow 10000/udp # Jitsi video
    # Samba ports
    ufw allow 137/udp
    ufw allow 138/udp
    ufw allow 139/tcp
    ufw allow 445/tcp

    # Allow specific app ports if not using reverse proxy for everything
    # Example: Bitwarden 8000/tcp if accessed directly
    # ufw allow 8000/tcp # Vaultwarden direct access

    if ufw status | grep -qw active; then
        ufw reload
        log_info "UFW already active, reloaded rules."
    else
        yes | ufw enable # Answer yes to prompt automatically
        log_success "UFW enabled and configured with basic rules."
    fi
    ufw status verbose
else
    log_warning "UFW command not found. Firewall not configured by this script."
fi

# Intrusion Prevention (Fail2ban)
if command_exists "fail2ban-client"; then
    # Basic configuration: copy jail.conf to jail.local and customize.
    # A pre-configured jail.local should be in $SCRIPTS_DIR for offline setup.
    JAIL_LOCAL="/etc/fail2ban/jail.local"
    CUSTOM_JAIL_LOCAL="${SCRIPTS_DIR}/fail2ban_jail.local"
    if [ -f "$CUSTOM_JAIL_LOCAL" ]; then
        cp "$CUSTOM_JAIL_LOCAL" "$JAIL_LOCAL"
        log_info "Copied custom Fail2ban configuration to $JAIL_LOCAL."
    else
        log_warning "Custom Fail2ban config ($CUSTOM_JAIL_LOCAL) not found. Using defaults if any."
        # Create a minimal jail.local if it doesn't exist to enable sshd protection
        if [ ! -f "$JAIL_LOCAL" ] && [ -f "/etc/fail2ban/jail.conf" ]; then
            log_info "Creating a minimal jail.local to protect SSHD."
            cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.d/defaults-debian.conf # Backup default name on debian
            (echo "[DEFAULT]"; echo "bantime = 1h"; echo "[sshd]"; echo "enabled = true") > "$JAIL_LOCAL"
        fi
    fi
    manage_system_service fail2ban
else
    log_warning "Fail2ban (fail2ban-client) not found. Intrusion prevention not configured."
fi


# MariaDB (Database Server) - Started here, used by various apps
if command_exists "mysqld"; then
    MARIADB_SERVICE_NAME="mariadb" # Common names: mariadb, mysql, mysqld
    if ! systemctl list-unit-files | grep -qw "$MARIADB_SERVICE_NAME.service"; then MARIADB_SERVICE_NAME="mysql"; fi
    if ! systemctl list-unit-files | grep -qw "$MARIADB_SERVICE_NAME.service"; then MARIADB_SERVICE_NAME="mysqld"; fi
    manage_system_service "$MARIADB_SERVICE_NAME"
    log_info "MariaDB service managed. App-specific databases/users are assumed to be handled by apps or their Docker Compose files."
else
    log_warning "mysqld (MariaDB/MySQL) not found. Database-dependent apps may fail."
fi

# Cockpit (Web-based System Admin Panel)
if command_exists "cockpit-ws"; then manage_system_service cockpit.socket; fi

# Dnsmasq (Local DNS/DHCP)
DNSMASQ_CONFIG_FILE="/etc/dnsmasq.conf"
CUSTOM_DNSMASQ_CONFIG="${SCRIPTS_DIR}/dnsmasq.conf"
if [ -f "$CUSTOM_DNSMASQ_CONFIG" ]; then
    log_info "Configuring Dnsmasq..."
    if [ -f "$DNSMASQ_CONFIG_FILE" ] && [ ! -L "$DNSMASQ_CONFIG_FILE" ]; then cp "$DNSMASQ_CONFIG_FILE" "${DNSMASQ_CONFIG_FILE}.bak_$(date +%F-%T)"; fi
    cp "$CUSTOM_DNSMASQ_CONFIG" "$DNSMASQ_CONFIG_FILE"
    log_success "Copied custom Dnsmasq configuration."
    if command_exists "dnsmasq"; then manage_system_service dnsmasq; fi
else
    log_warning "Custom Dnsmasq config ($CUSTOM_DNSMASQ_CONFIG) not found. Dnsmasq will use defaults if started."
fi

# Samba (File Sharing)
SAMBA_CONFIG_FILE="/etc/samba/smb.conf"
SHARED_DIR="/srv/samba/shared" # Changed path slightly for clarity
SAMBA_USER="smbadmin" # Changed username to avoid conflict with generic 'admin'
SAMBA_PASSWORD="offlinepassword" # WARNING: Change this!
if command_exists "smbd"; then
    log_info "Configuring Samba..."
    id "$SAMBA_USER" &>/dev/null || (useradd -m -s /sbin/nologin "$SAMBA_USER" && echo "${SAMBA_USER}:${SAMBA_PASSWORD}" | chpasswd)
    (echo "$SAMBA_PASSWORD"; echo "$SAMBA_PASSWORD") | smbpasswd -s -a "$SAMBA_USER" || log_warning "Failed to set Samba password for '$SAMBA_USER'."
    mkdir -p "$SHARED_DIR" && chmod -R 0775 "$SHARED_DIR" && chown -R "${SAMBA_USER}:${SAMBA_USER}" "$SHARED_DIR"
    log_warning "Samba share permissions for $SHARED_DIR set to 0775, owned by $SAMBA_USER. Review for production."
    if [ -f "$SAMBA_CONFIG_FILE" ] && [ ! -L "$SAMBA_CONFIG_FILE" ]; then cp "$SAMBA_CONFIG_FILE" "${SAMBA_CONFIG_FILE}.bak_$(date +%F-%T)"; fi
cat > "$SAMBA_CONFIG_FILE" <<SMBEOF
[global]
   workgroup = WORKGROUP
   server string = Offline Enterprise Server
   netbios name = $(hostname -s | tr '[:lower:]' '[:upper:]')
   security = user
   map to guest = bad user
   dns proxy = no
   # Consider adding logging options

[Shared]
   path = $SHARED_DIR
   comment = Main Shared Folder
   browsable = yes
   writable = yes
   guest ok = no # No guest access
   valid users = @${SAMBA_USER} # Or specific users: $SAMBA_USER
   create mask = 0664
   directory mask = 0775
   # Force user and group for new files
   # force user = $SAMBA_USER
   # force group = $SAMBA_USER
SMBEOF
    log_success "Samba configuration written."
    manage_system_service smbd
    manage_system_service nmbd
else
    log_warning "Samba (smbd) not found. File sharing disabled."
fi

# Nginx (Web Server / Reverse Proxy) - Will be configured more specifically later
if command_exists "nginx"; then manage_system_service nginx; fi


# --- 3. Load All Pre-downloaded Docker Images ---
log_info "--- Section 3: Loading All Docker Images ---"
if command_exists "docker"; then load_all_docker_images; else log_error "Docker not available. Skipping Docker image loading & app deployments."; fi


# --- 4. Deploy Dockerized Applications ---
# Assumes docker & docker-compose are working, and images are loaded.
# Each app needs its own subdirectory in $APPS_DIR with a docker-compose.yml/.yaml and any other needed files (.env, configs).
log_info "--- Section 4: Deploying Dockerized Applications ---"
if command_exists "docker" && command_exists "docker-compose"; then
    # Communication & Collaboration
    deploy_docker_compose_app "mattermost" "chat" "Mattermost Team Chat"
    deploy_docker_compose_app "jitsi" "meet" "Jitsi Video Conferencing"
        # Note: Jitsi often needs specific .env for public IP/domain and UDP ports opened on firewall.

    # Documentation & Knowledge Base
    deploy_docker_compose_app "wikijs" "wiki" "Wiki.js"
    deploy_docker_compose_app "bookstack" "books" "BookStack Knowledge Base"

    # File Sharing & Storage (Nextcloud is handled separately due to non-Docker parts in original script)
    deploy_docker_compose_app "syncthing" "sync" "Syncthing (P2P File Sync)" "GUI:8384 API:22000"
        # Syncthing GUI usually on 8384. Data path setup is crucial in its docker-compose.

    # Project Management & Task Tracking
    deploy_docker_compose_app "wekan" "kanban" "Wekan Kanban Board"
    deploy_docker_compose_app "kanboard" "tasks" "Kanboard Project Management"

    # Code Hosting & Dev Tools
    deploy_docker_compose_app "gitea" "git" "Gitea Git Hosting"
    deploy_docker_compose_app "portainer" "portainer" "Portainer (Docker Management UI)" "9000 or 9443"
        # Portainer CE: port 9000 (HTTP) or 9443 (HTTPS). Needs a persistent volume.

    # CRM & ERP
    deploy_docker_compose_app "erpnext" "erp" "ERPNext"
        # ERPNext is complex. Its docker-compose.yml in $APPS_DIR/erpnext must be complete and well-tested.
    deploy_docker_compose_app "invoiceninja" "invoice" "InvoiceNinja v4 (Invoicing)"
        # Assuming InvoiceNinja v4 for simpler offline Docker setup. Needs .env file in $APPS_DIR/invoiceninja.

    # Notes & Personal Productivity
    deploy_docker_compose_app "joplin-server" "notes-server" "Joplin Server"
    deploy_docker_compose_app "wallabag" "readit" "Wallabag (Read-it-later)"

    # Password & Secrets Management (Vaultwarden - formerly Bitwarden_rs)
    # Using direct docker run as an example, but can also be a docker-compose.
    log_info "--- Deploying Vaultwarden (Password Manager) ---"
    VAULTWARDEN_DATA_DIR="/opt/vaultwarden_data" # Ensure this is backed up
    mkdir -p "$VAULTWARDEN_DATA_DIR"
    # Ensure 'vaultwarden/server:latest' (or specific version) image was loaded.
    # Image name might be 'bitwardenrs/server' in older setups. Adjust if needed.
    if docker run -d --name vaultwarden --restart unless-stopped \
        -v "${VAULTWARDEN_DATA_DIR}:/data" \
        -e WEBSOCKET_ENABLED=true \
        -p 8081:80 -p 3012:3012 \
        vaultwarden/server:latest; then # Using a different host port (8081) to avoid conflict with Nginx
        log_success "Vaultwarden container started. Data in $VAULTWARDEN_DATA_DIR."
        log_info "Access Vaultwarden at http://$PRIMARY_IP:8081 (direct) or http://$PRIMARY_IP/password (via Nginx)"
    else
        log_error "Failed to start Vaultwarden container. Check 'docker logs vaultwarden'."
    fi

    # Monitoring & Observability
    deploy_docker_compose_app "netdata" "netdata-docker" "Netdata (Docker version)" "19999"
        # Netdata via Docker. Assumes its docker-compose has necessary volume mounts like /proc, /sys.
    deploy_docker_compose_app "prometheus-grafana" "monitoring" "Prometheus & Grafana" "Prometheus:9090 Grafana:3000"
        # This needs a $APPS_DIR/prometheus-grafana/docker-compose.yml and config files (prometheus.yml, grafana provisioning).

    # Unified Admin Dashboard (Links to other services)
    deploy_docker_compose_app "heimdall" "dashboard" "Heimdall Dashboard"
        # Heimdall needs a config volume for its persistent data.

else
    log_error "Docker or Docker Compose not available. Skipping all Dockerized application deployments."
fi

# Nextcloud (Traditional web server setup - more complex than Docker for this script)
# This section assumes PHP, required extensions, and a compatible Nginx config are handled.
# Data for Nextcloud (PHP files) should be in $APPS_DIR/nextcloud/
log_info "--- Deploying Nextcloud (Traditional Setup) ---"
NEXTCLOUD_WEB_DIR="/var/www/nextcloud"
NEXTCLOUD_SOURCE_DIR="${APPS_DIR}/nextcloud"
if [ -d "$NEXTCLOUD_SOURCE_DIR" ] && [ -n "$(ls -A "$NEXTCLOUD_SOURCE_DIR" 2>/dev/null)" ]; then
    log_info "Copying Nextcloud files from $NEXTCLOUD_SOURCE_DIR to $NEXTCLOUD_WEB_DIR..."
    mkdir -p "$NEXTCLOUD_WEB_DIR"
    # Using rsync for better copy, but cp -a is also fine.
    if rsync -a --delete "$NEXTCLOUD_SOURCE_DIR/" "$NEXTCLOUD_WEB_DIR/"; then
        log_info "Nextcloud files copied."
        WEB_USER="www-data" # Default for Debian/Ubuntu
        if [[ "$OS_ID" == "almalinux" || "$OS_ID" == "centos" || "$OS_ID" == "rocky" || "$OS_ID" == "rhel" ]]; then
            WEB_USER="nginx" # Or 'apache' if using Apache
            if ! id "$WEB_USER" &>/dev/null; then WEB_USER="apache"; fi
        fi
        if ! id "$WEB_USER" &>/dev/null; then
            log_warning "Web server user ($WEB_USER) not found. Skipping chown for Nextcloud. Manual permission setting required for $NEXTCLOUD_WEB_DIR."
        else
            # Data directory for Nextcloud (must be outside web root for security)
            NEXTCLOUD_DATA_DIR="/var/www/nextcloud_data" # Example, configure in Nextcloud's config.php
            mkdir -p "$NEXTCLOUD_DATA_DIR"
            chown -R "${WEB_USER}:${WEB_USER}" "$NEXTCLOUD_WEB_DIR"
            chown -R "${WEB_USER}:${WEB_USER}" "$NEXTCLOUD_DATA_DIR"
            log_info "Set ownership of $NEXTCLOUD_WEB_DIR and $NEXTCLOUD_DATA_DIR to $WEB_USER."
        fi
        log_success "Nextcloud files deployed."
        log_warning "Manual setup for Nextcloud (Nginx PHP-FPM config, database via MariaDB, initial admin setup via browser, config.php for data dir) is still required."
    else
        log_error "Failed to copy Nextcloud files to $NEXTCLOUD_WEB_DIR."
    fi
else
    log_warning "Nextcloud source directory ($NEXTCLOUD_SOURCE_DIR) not found or empty. Skipping Nextcloud traditional deployment."
fi


# --- 5. Configure Nginx Reverse Proxy ---
# This is CRITICAL. The enterprise_apps.conf must be comprehensive.
log_info "--- Section 5: Configuring Nginx Reverse Proxy ---"
NGINX_CUSTOM_CONF_SOURCE="${APPS_DIR}/reverse-proxy/enterprise_apps.conf" # Changed from default.conf
NGINX_SITES_AVAILABLE_DIR="/etc/nginx/sites-available"
NGINX_SITES_ENABLED_DIR="/etc/nginx/sites-enabled"
NGINX_TARGET_CONF_FILENAME="enterprise_apps.conf"

if command_exists "nginx"; then
    if [ -f "$NGINX_CUSTOM_CONF_SOURCE" ]; then
        log_info "Copying main Nginx reverse proxy configuration..."
        cp "$NGINX_CUSTOM_CONF_SOURCE" "${NGINX_SITES_AVAILABLE_DIR}/${NGINX_TARGET_CONF_FILENAME}"

        # Disable default Nginx site to avoid conflicts, if it exists and is enabled
        if [ -L "${NGINX_SITES_ENABLED_DIR}/default" ]; then
            rm -f "${NGINX_SITES_ENABLED_DIR}/default"
            log_info "Disabled default Nginx site."
        fi
        # Enable the new comprehensive configuration
        ln -sf "${NGINX_SITES_AVAILABLE_DIR}/${NGINX_TARGET_CONF_FILENAME}" "${NGINX_SITES_ENABLED_DIR}/${NGINX_TARGET_CONF_FILENAME}"
        log_success "Nginx reverse proxy configuration linked: $NGINX_TARGET_CONF_FILENAME."

        log_info "Testing Nginx configuration..."
        if nginx -t; then
            log_success "Nginx configuration test successful."
            manage_system_service nginx restart
        else
            log_error "Nginx configuration test failed! Nginx not restarted. Please check your config at $NGINX_CUSTOM_CONF_SOURCE and Nginx error logs."
        fi
    else
        log_warning "Main Nginx reverse proxy configuration file ($NGINX_CUSTOM_CONF_SOURCE) not found. Critical services may not be accessible via friendly URLs."
    fi
else
    log_warning "Nginx not available. Skipping reverse proxy configuration. Web applications will not be easily accessible."
fi


# --- 6. Setup Backup Cron Job ---
log_info "--- Section 6: Setting Up Backup Cron Job ---"
BACKUP_SCRIPT_SOURCE="${SCRIPTS_DIR}/backup.sh" # This script needs to handle backup of all data (Docker volumes, DBs, /srv etc.)
BACKUP_SCRIPT_DEST="/usr/local/bin/enterprise_backup.sh"
BACKUP_LOG_DIR="/var/log/enterprise_backups"
CRON_JOB_COMMAND="0 2 * * * $BACKUP_SCRIPT_DEST >> ${BACKUP_LOG_DIR}/backup-\$(date +\%Y-\%m-\%d).log 2>&1"

mkdir -p "$BACKUP_LOG_DIR"
log_info "Backup logs will be stored in $BACKUP_LOG_DIR."

if [ -f "$BACKUP_SCRIPT_SOURCE" ]; then
    cp "$BACKUP_SCRIPT_SOURCE" "$BACKUP_SCRIPT_DEST"
    chmod +x "$BACKUP_SCRIPT_DEST"
    log_success "Backup script copied to $BACKUP_SCRIPT_DEST and made executable."

    # Add cron job if it doesn't exist already
    if crontab -l 2>/dev/null | grep -Fq "$BACKUP_SCRIPT_DEST"; then
        log_info "Cron job for backup script already exists."
    else
        (crontab -l 2>/dev/null; echo "$CRON_JOB_COMMAND") | crontab -
        log_success "Cron job added: Runs daily at 2 AM."
    fi
    log_info "Ensure $BACKUP_SCRIPT_DEST is robust and correctly backs up all critical data (Docker volumes, databases, configs)."
else
    log_warning "Backup script ($BACKUP_SCRIPT_SOURCE) not found. Automated backups NOT configured."
fi


# --- Final Summary ---
log_info ""
log_success "🎉🎉🎉 COMPREHENSIVE ENTERPRISE SERVER INSTALLATION SCRIPT COMPLETED! 🎉🎉🎉"
log_info "---------------------------------------------------------------------------------"
log_info "Please review all logs and check individual application statuses."
log_info "The server IP is reported as: $PRIMARY_IP"
log_info "Access your services via the URLs defined in your Nginx reverse proxy (enterprise_apps.conf)."
log_info "Example access points (actual paths depend on your Nginx config):"
log_info "  - Admin Dashboard (Links): http://$PRIMARY_IP/dashboard (Heimdall)"
log_info "  - Server Admin (Cockpit): https://$PRIMARY_IP:9090"
log_info "  - Team Chat (Mattermost): http://$PRIMARY_IP/chat"
log_info "  - Video Conferencing (Jitsi): http://$PRIMARY_IP/meet"
log_info "  - Wiki (Wiki.js): http://$PRIMARY_IP/wiki"
log_info "  - Knowledge Base (BookStack): http://$PRIMARY_IP/books"
log_info "  - File Storage (Nextcloud): http://$PRIMARY_IP/nextcloud (Requires manual setup completion!)"
log_info "  - P2P File Sync (Syncthing): http://$PRIMARY_IP:8384 (Direct GUI, or proxy if set up)"
log_info "  - Kanban (Wekan): http://$PRIMARY_IP/kanban"
log_info "  - Project Tasks (Kanboard): http://$PRIMARY_IP/tasks"
log_info "  - Git Hosting (Gitea): http://$PRIMARY_IP/git"
log_info "  - Docker Management (Portainer): http://$PRIMARY_IP/portainer (or direct :9000/:9443 if not proxied)"
log_info "  - ERP System (ERPNext): http://$PRIMARY_IP/erp (Complex! Verify setup)"
log_info "  - Invoicing (InvoiceNinja): http://$PRIMARY_IP/invoice"
log_info "  - Notes Server (Joplin): http://$PRIMARY_IP/notes-server"
log_info "  - Read-it-Later (Wallabag): http://$PRIMARY_IP/readit"
log_info "  - Password Manager (Vaultwarden): http://$PRIMARY_IP:8081 (direct) or http://$PRIMARY_IP/password (proxied)"
log_info "  - Monitoring (Netdata): http://$PRIMARY_IP:19999"
log_info "  - Monitoring (Grafana): http://$PRIMARY_IP/grafana (Prometheus backend, needs config)"
log_info "  - Samba Share: smb://$PRIMARY_IP/Shared (User: $SAMBA_USER)"
log_info "---------------------------------------------------------------------------------"
log_info "🔑 IMPORTANT POST-INSTALLATION ACTIONS:"
log_info "   1. VERIFY NGINX: Ensure '$NGINX_SITES_ENABLED_DIR/$NGINX_TARGET_CONF_FILENAME' is correct and Nginx serves all apps."
log_info "   2. APP CONFIGURATION: Many apps (Nextcloud, ERPNext, Jitsi, Grafana, etc.) require significant post-install configuration via their web UIs."
log_info "   3. DATABASE SETUP: For apps not using internal Docker databases, ensure connections to MariaDB are configured and databases/users created."
log_info "   4. CHANGE DEFAULT PASSWORDS: Especially for Samba ($SAMBA_USER), Vaultwarden admin, Gitea admin, etc."
log_info "   5. DATA PERSISTENCE & BACKUPS: Double-check all Docker volumes are mapped to persistent storage on the host and that your '$BACKUP_SCRIPT_DEST' is comprehensive and tested."
log_info "   6. SECURITY: Review UFW rules, Fail2ban status. Consider further hardening (SELinux/AppArmor, regular security audits even offline)."
log_info "   7. USER MANAGEMENT: Plan how users will be managed across these services (e.g., manual creation, LDAP integration - advanced)."
log_info "   8. TEST EVERYTHING thoroughly before considering it 'production grade'."
log_info ""
log_info "✅ Installation script finished. Rebooting is not strictly necessary unless kernel updates were part of OS packages."

exit 0
