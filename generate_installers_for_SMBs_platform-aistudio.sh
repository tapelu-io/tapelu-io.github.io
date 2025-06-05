#!/bin/bash

# Script to Generate SMB Self-Hosting Platform .deb and .rpm Installers
# Name: generate_installers_for_SMBs_platform.sh
# Version: 1.0.8 (rpmbuild output suppressed to /dev/null)

set -e # Exit on error

# --- Configuration ---
PROJECT_NAME="smbplatform"
PROJECT_VERSION="1.0.0"
RELEASE_VERSION="1"
MAINTAINER_NAME="Your SMB Solutions"
MAINTAINER_EMAIL="support@example.com"
DESCRIPTION="All-in-one self-hosted platform for Small-Medium Businesses."
SUMMARY="SMB Self-Host Platform"
LICENSE="MIT"
URL="https://example.com/smbplatform"

BUILD_DIR_BASE="smbplatform_build_root"

# --- Helper Functions ---
log_info() { echo "[INFO] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_warn() { echo "[WARN] $(date '+%Y-%m-%d %H:%M:%S') - $1"; }
log_error() { echo "[ERROR] $(date '+%Y-%m-%d %H:%M:%S') - $1"; exit 1; }

check_build_tool() {
    command -v "$1" >/dev/null 2>&1 || log_error "Build tool '$1' not found. Please install it. (e.g., sudo apt install $1 or sudo yum install $1)"
}

# --- Main Generator Logic ---
generate_project_files() {
    log_info "Creating project structure in ./${BUILD_DIR_BASE}..."
    rm -rf "./${BUILD_DIR_BASE}"
    mkdir -p "./${BUILD_DIR_BASE}/src/preconfig_example" 
    mkdir -p "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN"
    mkdir -p "./${BUILD_DIR_BASE}/packaging/rpm/SOURCES"
    mkdir -p "./${BUILD_DIR_BASE}/packaging/rpm/SPECS"
    mkdir -p "./${BUILD_DIR_BASE}/packaging/rpm/BUILD"
    mkdir -p "./${BUILD_DIR_BASE}/packaging/rpm/RPMS"
    mkdir -p "./${BUILD_DIR_BASE}/packaging/rpm/SRPMS"
    mkdir -p "./${BUILD_DIR_BASE}/dist"

    # --- 1. Create the main installer script (platform_installer.sh) ---
    log_info "Generating src/platform_installer.sh..."
    cat > "./${BUILD_DIR_BASE}/src/platform_installer.sh" << 'EOF_INSTALLER'
#!/bin/bash
# SMB Platform Installer Script (to be run on target server)
# Version: __PROJECT_VERSION__

set -e
# set -x # Uncomment for debugging

BASE_INSTALL_DIR="/opt/__PROJECT_NAME__"
PRECONFIG_FILE_PATH="/etc/__PROJECT_NAME__/preconfig.env"
DATA_DIR="${BASE_INSTALL_DIR}/data"
CONFIG_DIR="${BASE_INSTALL_DIR}/config"
COMPOSE_FILE="${BASE_INSTALL_DIR}/docker-compose.yml"
ENV_FILE="${BASE_INSTALL_DIR}/.env"
LOG_FILE="${BASE_INSTALL_DIR}/installer.log"
SCRIPT_NAME_ON_TARGET="platform_installer.sh"

_log_() {
    local level="$1"; local message="$2"
    echo "[${level}] $(date '+%Y-%m-%d %H:%M:%S') - ${message}" | tee -a "${LOG_FILE}"
}
log_info() { _log_ "INFO" "$1"; }
log_warn() { _log_ "WARN" "$1"; }
log_error() { _log_ "ERROR" "$1"; exit 1; }

check_command() { command -v "$1" &>/dev/null || log_error "$1 is not installed..."; }
root_check() { [ "$(id -u)" -ne 0 ] && log_error "This script must be run as root or with sudo."; }

install_dependencies() {
    log_info "Checking and installing dependencies (Docker, Docker Compose, curl, jq, openssl)..."
    root_check
    local PKG_MANAGER=""
    if command -v apt-get &>/dev/null; then PKG_MANAGER="apt";
    elif command -v yum &>/dev/null; then PKG_MANAGER="yum";
    elif command -v dnf &>/dev/null; then PKG_MANAGER="dnf";
    else log_error "Unsupported package manager."; fi

    local to_install_common=()
    for cmd_tool in curl jq openssl coreutils; do
        command -v "$cmd_tool" &>/dev/null || to_install_common+=("$cmd_tool")
    done
    if [ ${#to_install_common[@]} -gt 0 ]; then
        log_info "Installing common utilities: ${to_install_common[*]}"
        case "$PKG_MANAGER" in
            apt) sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq "${to_install_common[@]}" >/dev/null ;;
            yum) sudo yum install -y -q "${to_install_common[@]}" >/dev/null ;;
            dnf) sudo dnf install -y -q "${to_install_common[@]}" >/dev/null ;;
        esac
        for cmd_tool in "${to_install_common[@]}"; do
             command -v "$cmd_tool" &>/dev/null || log_error "Failed to install $cmd_tool."
        done
    fi
    if ! command -v docker &> /dev/null; then
        log_info "Installing Docker..."
        curl -fsSL https://get.docker.com -o get-docker.sh && sudo sh get-docker.sh && sudo rm get-docker.sh
        sudo systemctl enable docker --now
        if [ -n "$SUDO_USER" ] && id "$SUDO_USER" &>/dev/null; then sudo usermod -aG docker "$SUDO_USER"; fi
        log_info "Docker installed."
    else log_info "Docker found."; fi
    check_command docker
    if ! (docker compose version &>/dev/null || docker-compose version &>/dev/null) ; then
        log_info "Installing Docker Compose..."
        case "$PKG_MANAGER" in
            apt) sudo apt-get update -qq >/dev/null && sudo apt-get install -y -qq docker-compose-plugin >/dev/null ;;
            yum|dnf) sudo "${PKG_MANAGER}" install -y -q docker-compose-plugin >/dev/null ;;
        esac
        if ! docker compose version &>/dev/null && ! command -v docker-compose &>/dev/null; then
            log_info "Docker Compose plugin install failed/unavailable, trying standalone."
            LATEST_COMPOSE_TAG_NAME=$(curl -s https://api.github.com/repos/docker/compose/releases/latest | jq .tag_name -r)
            [ -z "$LATEST_COMPOSE_TAG_NAME" ] || [ "$LATEST_COMPOSE_TAG_NAME" == "null" ] && log_error "Could not fetch latest Docker Compose tag."
            sudo curl -SL "https://github.com/docker/compose/releases/download/${LATEST_COMPOSE_TAG_NAME}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
            if [ -d "/usr/bin" ]; then sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose || log_warn "Could not symlink docker-compose."; fi
        fi
    fi
    (docker compose version &>/dev/null || docker-compose version &>/dev/null) || log_error "Docker Compose required and not installed."
    log_info "Dependency check complete."
}

_save_env_config() {
    local main_domain_val="$1"
    local admin_email_val="$2"
    POSTGRES_PASSWORD_NC=$(grep '^POSTGRES_PASSWORD_NC=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2 || openssl rand -base64 16)
    POSTGRES_PASSWORD_MM=$(grep '^POSTGRES_PASSWORD_MM=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2 || openssl rand -base64 16)
    MYSQL_ROOT_PASSWORD_BS=$(grep '^MYSQL_ROOT_PASSWORD_BS=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2 || openssl rand -base64 16)
    MYSQL_PASSWORD_BS=$(grep '^MYSQL_PASSWORD_BS=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2 || openssl rand -base64 16)
    VAULTWARDEN_ADMIN_TOKEN=$(grep '^VAULTWARDEN_ADMIN_TOKEN=' "${ENV_FILE}" 2>/dev/null | cut -d'=' -f2 || openssl rand -base64 48)

    log_info "Saving configuration to ${ENV_FILE}"
    mkdir -p "$(dirname "${ENV_FILE}")"
    cat > "${ENV_FILE}" <<EOF_ENV
MAIN_DOMAIN=${main_domain_val}
ADMIN_EMAIL=${admin_email_val}
BASE_INSTALL_DIR=${BASE_INSTALL_DIR}
POSTGRES_PASSWORD_NC=${POSTGRES_PASSWORD_NC}
POSTGRES_PASSWORD_MM=${POSTGRES_PASSWORD_MM}
MYSQL_ROOT_PASSWORD_BS=${MYSQL_ROOT_PASSWORD_BS}
MYSQL_PASSWORD_BS=${MYSQL_PASSWORD_BS}
VAULTWARDEN_ADMIN_TOKEN=${VAULTWARDEN_ADMIN_TOKEN}
DOCKER_NETWORK=smbplatform_net
EOF_ENV
    chmod 600 "${ENV_FILE}"
    log_info "Configuration saved to ${ENV_FILE}."
}

gather_config_interactive() {
    log_info "Gathering essential configuration interactively..."
    mkdir -p "$(dirname "${LOG_FILE}")"; touch "${LOG_FILE}"; chmod 600 "${LOG_FILE}"
    local current_domain=""; local current_email=""
    if [ -f "${ENV_FILE}" ]; then
        current_domain=$(grep '^MAIN_DOMAIN=' "${ENV_FILE}" | cut -d'=' -f2)
        current_email=$(grep '^ADMIN_EMAIL=' "${ENV_FILE}" | cut -d'=' -f2)
    fi
    read -r -p "Enter main domain (e.g., platform.yourcompany.com) [${current_domain:-platform.example.com}]: " MAIN_DOMAIN_INPUT
    local final_main_domain=${MAIN_DOMAIN_INPUT:-${current_domain:-platform.example.com}}
    read -r -p "Enter admin email (e.g., admin@yourcompany.com) [${current_email:-admin@example.com}]: " ADMIN_EMAIL_INPUT
    local final_admin_email=${ADMIN_EMAIL_INPUT:-${current_email:-admin@example.com}}
    _save_env_config "${final_main_domain}" "${final_admin_email}"
}

gather_config_non_interactive() {
    log_info "Attempting non-interactive configuration from ${PRECONFIG_FILE_PATH}..."
    mkdir -p "$(dirname "${LOG_FILE}")"; touch "${LOG_FILE}"; chmod 600 "${LOG_FILE}"
    if [ ! -f "${PRECONFIG_FILE_PATH}" ]; then
        log_warn "Pre-configuration file ${PRECONFIG_FILE_PATH} not found."
        log_warn "Please create it with MAIN_DOMAIN and ADMIN_EMAIL, or run interactive setup:"
        log_warn "sudo ${BASE_INSTALL_DIR}/${SCRIPT_NAME_ON_TARGET} setup_interactive"
        return 1 
    fi
    
    local main_domain_val admin_email_val
    main_domain_val=$(grep '^MAIN_DOMAIN=' "${PRECONFIG_FILE_PATH}" | cut -d'=' -f2 | tr -d '[:space:]')
    admin_email_val=$(grep '^ADMIN_EMAIL=' "${PRECONFIG_FILE_PATH}" | cut -d'=' -f2 | tr -d '[:space:]')

    if [ -z "${main_domain_val}" ] || [ -z "${admin_email_val}" ]; then
        log_warn "MAIN_DOMAIN or ADMIN_EMAIL not found or empty in ${PRECONFIG_FILE_PATH}."
        log_warn "Please ensure the file contains valid entries, or run interactive setup:"
        log_warn "sudo ${BASE_INSTALL_DIR}/${SCRIPT_NAME_ON_TARGET} setup_interactive"
        return 1
    fi
    log_info "Using MAIN_DOMAIN=${main_domain_val} and ADMIN_EMAIL=${admin_email_val} from preconfig."
    _save_env_config "${main_domain_val}" "${admin_email_val}"
    return 0 
}

create_platform_directories() {
    log_info "Creating required directories under ${BASE_INSTALL_DIR}..."
    mkdir -p "${DATA_DIR}" "${CONFIG_DIR}"
    declare -a DIRS_TO_CREATE=(
        "portainer_data" "npm_data" "npm_letsencrypt" "heimdall_config"
        "nextcloud_html" "nextcloud_custom_apps" "nextcloud_config" "nextcloud_data" "nextcloud_db_data"
        "mattermost_config" "mattermost_data" "mattermost_logs" "mattermost_plugins" "mattermost_client_plugins" "mattermost_db_data"
        "vaultwarden_data"
        "bookstack_db_data" "bookstack_app_config"
        "uptime_kuma_data"
    )
    for subdir in "${DIRS_TO_CREATE[@]}"; do mkdir -p "${DATA_DIR}/${subdir}"; done
    log_info "Platform directories created."
}
generate_final_compose_file() {
    log_info "Generating final Docker Compose file: ${COMPOSE_FILE}"
    ( set -o allexport; source "${ENV_FILE}"; set +o allexport 
cat > "${COMPOSE_FILE}" <<EOF_COMPOSE_INNER
version: '3.8'
networks: {platform_net: {name: \${DOCKER_NETWORK}, driver: bridge}}
services:
  portainer: {image: portainer/portainer-ce:latest, container_name: portainer, restart: unless-stopped, security_opt: [no-new-privileges:true], volumes: ["/var/run/docker.sock:/var/run/docker.sock", "${DATA_DIR}/portainer_data:/data"], networks: [platform_net]}
  npm: {image: jc21/nginx-proxy-manager:latest, container_name: npm, restart: unless-stopped, ports: ['80:80','443:443','81:81'], volumes: ["${DATA_DIR}/npm_data:/data", "${DATA_DIR}/npm_letsencrypt:/etc/letsencrypt"], environment: {DISABLE_IPV6: 'true'}, networks: [platform_net]}
  heimdall: {image: lscr.io/linuxserver/heimdall:latest, container_name: heimdall, restart: unless-stopped, environment: [PUID=1000, PGID=1000, TZ=Etc/UTC], volumes: ["${DATA_DIR}/heimdall_config:/config"], networks: [platform_net]}
  nextcloud_db: {image: postgres:15-alpine, container_name: nextcloud_db, restart: unless-stopped, volumes: ["${DATA_DIR}/nextcloud_db_data:/var/lib/postgresql/data"], environment: {POSTGRES_USER: nextcloud, POSTGRES_PASSWORD: \${POSTGRES_PASSWORD_NC}, POSTGRES_DB: nextcloud}, networks: [platform_net]}
  nextcloud: {image: nextcloud:latest, container_name: nextcloud, restart: unless-stopped, depends_on: [nextcloud_db], volumes: ["${DATA_DIR}/nextcloud_html:/var/www/html", "${DATA_DIR}/nextcloud_custom_apps:/var/www/html/custom_apps", "${DATA_DIR}/nextcloud_config:/var/www/html/config", "${DATA_DIR}/nextcloud_data:/var/www/html/data"], environment: {POSTGRES_HOST: nextcloud_db, POSTGRES_DB: nextcloud, POSTGRES_USER: nextcloud, POSTGRES_PASSWORD: \${POSTGRES_PASSWORD_NC}, NEXTCLOUD_TRUSTED_DOMAINS: "nextcloud.\${MAIN_DOMAIN} localhost \$(hostname -i)", PHP_MEMORY_LIMIT: 1G, PHP_UPLOAD_LIMIT: 10G, NEXTCLOUD_UPDATE: 1}, networks: [platform_net]}
  mattermost_db: {image: postgres:15-alpine, container_name: mattermost_db, restart: unless-stopped, volumes: ["${DATA_DIR}/mattermost_db_data:/var/lib/postgresql/data"], environment: {POSTGRES_USER: mmuser, POSTGRES_PASSWORD: \${POSTGRES_PASSWORD_MM}, POSTGRES_DB: mattermost}, networks: [platform_net]}
  mattermost: {image: mattermost/mattermost-team-edition:latest, container_name: mattermost, restart: unless-stopped, depends_on: [mattermost_db], volumes: ["${DATA_DIR}/mattermost_config:/mattermost/config:rw", "${DATA_DIR}/mattermost_data:/mattermost/data:rw", "${DATA_DIR}/mattermost_logs:/mattermost/logs:rw", "${DATA_DIR}/mattermost_plugins:/mattermost/plugins:rw", "${DATA_DIR}/mattermost_client_plugins:/mattermost/client/plugins:rw"], environment: {MM_SQLSETTINGS_DRIVERNAME: postgres, MM_SQLSETTINGS_DATASOURCE: "postgres://mmuser:\${POSTGRES_PASSWORD_MM}@mattermost_db:5432/mattermost?sslmode=disable&connect_timeout=10", MM_SERVICESETTINGS_SITEURL: "https://mattermost.\${MAIN_DOMAIN}"}, networks: [platform_net]}
  vaultwarden: {image: vaultwarden/server:latest, container_name: vaultwarden, restart: unless-stopped, volumes: ["${DATA_DIR}/vaultwarden_data:/data"], environment: {DOMAIN: "https://vault.\${MAIN_DOMAIN}", SIGNUPS_ALLOWED: 'true', ADMIN_TOKEN: \${VAULTWARDEN_ADMIN_TOKEN}, WEBSOCKET_ENABLED: 'true'}, networks: [platform_net]}
  bookstack_db: {image: mariadb:10.11, container_name: bookstack_db, restart: unless-stopped, environment: {MYSQL_ROOT_PASSWORD: \${MYSQL_ROOT_PASSWORD_BS}, MYSQL_DATABASE: bookstackapp, MYSQL_USER: bookstack, MYSQL_PASSWORD: \${MYSQL_PASSWORD_BS}}, volumes: ["${DATA_DIR}/bookstack_db_data:/var/lib/mysql"], networks: [platform_net]}
  bookstack: {image: lscr.io/linuxserver/bookstack:latest, container_name: bookstack, restart: unless-stopped, depends_on: [bookstack_db], environment: {PUID: 1000, PGID: 1000, APP_URL: "https://docs.\${MAIN_DOMAIN}", DB_HOST: bookstack_db, DB_USER: bookstack, DB_PASS: \${MYSQL_PASSWORD_BS}, DB_DATABASE: bookstackapp}, volumes: ["${DATA_DIR}/bookstack_app_config:/config"], networks: [platform_net]}
  uptime_kuma: {image: louislam/uptime-kuma:1, container_name: uptime_kuma, restart: unless-stopped, volumes: ["${DATA_DIR}/uptime_kuma_data:/app/data"], networks: [platform_net]}
EOF_COMPOSE_INNER
    )
    log_info "Docker Compose file generated: ${COMPOSE_FILE}"
}
get_docker_compose_command() { if docker compose version &>/dev/null; then echo "docker compose"; elif docker-compose version &>/dev/null; then echo "docker-compose"; else log_error "Docker Compose command not found."; return 1; fi; }
start_platform_services() {
    log_info "Starting platform services..."
    [ ! -f "${COMPOSE_FILE}" ] && log_error "Compose file missing!"; [ ! -f "${ENV_FILE}" ] && log_error "Env file missing!"
    local DOCKER_COMPOSE_CMD; DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
    cd "$(dirname "${COMPOSE_FILE}")" || log_error "Cannot cd to compose dir."
    local network_name; network_name=$(grep '^DOCKER_NETWORK=' "${ENV_FILE}" | cut -d'=' -f2)
    docker network inspect "${network_name}" >/dev/null 2>&1 || { log_info "Creating Docker network: ${network_name}"; docker network create "${network_name}" || log_error "Failed to create network ${network_name}"; }
    log_info "Pulling images..."; ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull || log_warn "Image pull failed for some."
    log_info "Starting services..."; ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" up -d --remove-orphans || log_error "Service start failed."
    log_info "Services started."; ${DOCKER_COMPOSE_CMD} ps
}
stop_platform_services() {
    log_info "Stopping platform services..."
    [ ! -f "${COMPOSE_FILE}" ] && { log_warn "Compose file missing."; return; }
    local DOCKER_COMPOSE_CMD; DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
    cd "$(dirname "${COMPOSE_FILE}")" || log_error "Cannot cd to compose dir."
    ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" down || log_warn "Service stop failed for some."
    log_info "Services stopped."
}
show_platform_status() {
    log_info "Platform service status:"
    [ ! -f "${COMPOSE_FILE}" ] && { log_warn "Compose file missing."; return; }
    local DOCKER_COMPOSE_CMD; DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
    cd "$(dirname "${COMPOSE_FILE}")" || log_error "Cannot cd to compose dir."
    ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" ps
}
show_platform_logs() {
    log_info "Platform service logs (Ctrl+C to stop)..."
    [ ! -f "${COMPOSE_FILE}" ] && { log_warn "Compose file missing."; return; }
    local DOCKER_COMPOSE_CMD; DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
    cd "$(dirname "${COMPOSE_FILE}")" || log_error "Cannot cd to compose dir."
    ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" logs -f --tail="100" "$@"
}
pull_latest_images() {
    log_info "Pulling latest images..."
    [ ! -f "${COMPOSE_FILE}" ] && { log_warn "Compose file missing."; return; }
    local DOCKER_COMPOSE_CMD; DOCKER_COMPOSE_CMD=$(get_docker_compose_command)
    cd "$(dirname "${COMPOSE_FILE}")" || log_error "Cannot cd to compose dir."
    ${DOCKER_COMPOSE_CMD} --env-file "${ENV_FILE}" -f "${COMPOSE_FILE}" pull || log_warn "Image pull failed for some."
    log_info "Image pull complete."
}
display_post_install_guidance() {
    if [ -f "${ENV_FILE}" ]; then set -o allexport; source "${ENV_FILE}"; set +o allexport; else log_warn "Env file missing."; MAIN_DOMAIN="your_domain.com"; fi
    log_info "--- SMB Platform Setup/Update Complete ---"
    log_info "Access services (ensure DNS points to this server's IP):"
    log_info "1. Nginx Proxy Manager (Admin UI): http://<SERVER_IP>:81 (Default: admin@example.com / changeme)"
    log_info "   Use NPM for Proxy Hosts & SSL for:"
    log_info "     - nextcloud.\${MAIN_DOMAIN} (nextcloud:80)"
    log_info "     - mattermost.\${MAIN_DOMAIN} (mattermost:8065)"
    log_info "     - vault.\${MAIN_DOMAIN} (vaultwarden:80) + Advanced WebSocket config for /notifications/hub to vaultwarden:3012"
    log_info "     - docs.\${MAIN_DOMAIN} (bookstack:80)"
    log_info "     - status.\${MAIN_DOMAIN} (uptime_kuma:3001)"
    log_info "     - dashboard.\${MAIN_DOMAIN} (heimdall:80)"
    log_info "     - portainer.\${MAIN_DOMAIN} (portainer:9000)"
    log_info "2. Initial App Setup via their HTTPS URLs..."
    log_info "SERVICE MANAGEMENT: sudo ${BASE_INSTALL_DIR}/${SCRIPT_NAME_ON_TARGET} [status|start|stop|restart|logs|pull|config_interactive]"
    log_info "                      sudo systemctl [start|stop|status] __PROJECT_NAME__"
    log_info "DATA: ${DATA_DIR} (Backup this and ${ENV_FILE}!)"
}


main_installer() {
    mkdir -p "${BASE_INSTALL_DIR}" 
    touch "${LOG_FILE}" >/dev/null 2>&1; chmod 600 "${LOG_FILE}" >/dev/null 2>&1
    log_info "SMB Platform Installer script started. Log: ${LOG_FILE}"
    root_check

    case "$1" in
        setup_interactive) 
            install_dependencies
            gather_config_interactive
            create_platform_directories
            generate_final_compose_file
            start_platform_services
            display_post_install_guidance
            log_info "Interactive setup complete. Services should be running."
            log_info "Ensure systemd service is enabled: sudo systemctl enable __PROJECT_NAME__"
            ;;
        setup_non_interactive) 
            install_dependencies
            if gather_config_non_interactive; then 
                create_platform_directories
                generate_final_compose_file
                start_platform_services
                display_post_install_guidance
                log_info "Non-interactive setup complete. Services should be running."
                log_info "Ensure systemd service is enabled: sudo systemctl enable __PROJECT_NAME__"
            else
                log_warn "Non-interactive setup could not complete due to missing pre-configuration."
                log_warn "Run 'sudo ${BASE_INSTALL_DIR}/${SCRIPT_NAME_ON_TARGET} setup_interactive' manually."
            fi
            ;;
        start) start_platform_services ;;
        stop) stop_platform_services ;;
        restart) stop_platform_services; pull_latest_images; start_platform_services ;;
        status) show_platform_status ;;
        logs) shift; show_platform_logs "$@" ;;
        pull) pull_latest_images ;;
        config_interactive) 
            install_dependencies
            gather_config_interactive
            generate_final_compose_file
            log_info "Configuration regenerated. Restart: sudo ... restart"
            ;;
        help|--help|-h)
            echo "Usage: sudo ${BASE_INSTALL_DIR}/${SCRIPT_NAME_ON_TARGET} [COMMAND]"
            echo "Commands: setup_interactive, setup_non_interactive, start, stop, restart, status, logs, pull, config_interactive, help"
            ;;
        *)
            if [ -z "$1" ]; then
                if [ ! -f "${ENV_FILE}" ]; then
                    log_info "No command. Run 'sudo ... setup_interactive' or provide preconfig for 'setup_non_interactive'."
                else
                    show_platform_status
                fi
            else log_error "Invalid command: $1. Use 'help'."; fi ;;
    esac
}
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main_installer "$@"; fi
EOF_INSTALLER
    sed -i "s/__PROJECT_NAME__/${PROJECT_NAME}/g" "./${BUILD_DIR_BASE}/src/platform_installer.sh"
    sed -i "s/__PROJECT_VERSION__/${PROJECT_VERSION}/g" "./${BUILD_DIR_BASE}/src/platform_installer.sh"
    chmod +x "./${BUILD_DIR_BASE}/src/platform_installer.sh"

    log_info "Generating src/preconfig_example/preconfig.env.example ..."
    cat > "./${BUILD_DIR_BASE}/src/preconfig_example/preconfig.env.example" << EOF_PRECONFIG_EXAMPLE
# Example pre-configuration file for __PROJECT_NAME__
# Copy this file to /etc/__PROJECT_NAME__/preconfig.env
# OR create /etc/__PROJECT_NAME__/preconfig.env with the following content
# before installing the __PROJECT_NAME__ .deb or .rpm package
# for a fully non-interactive setup.

# Replace with your actual main domain
MAIN_DOMAIN=platform.yourcompany.com

# Replace with your actual admin email for SSL certificates and notifications
ADMIN_EMAIL=admin@yourcompany.com
EOF_PRECONFIG_EXAMPLE
    sed -i "s/__PROJECT_NAME__/${PROJECT_NAME}/g" "./${BUILD_DIR_BASE}/src/preconfig_example/preconfig.env.example"

    log_info "Generating src/${PROJECT_NAME}.service..."
    cat > "./${BUILD_DIR_BASE}/src/${PROJECT_NAME}.service" << EOF_SYSTEMD
[Unit]
Description=${SUMMARY} Service
Requires=docker.service
After=docker.service network-online.target
[Service]
Type=oneshot
RemainAfterExit=yes
WorkingDirectory=/opt/${PROJECT_NAME}
ExecStart=/opt/${PROJECT_NAME}/platform_installer.sh start
ExecStop=/opt/${PROJECT_NAME}/platform_installer.sh stop
StandardOutput=journal
StandardError=journal
User=root
[Install]
WantedBy=multi-user.target
EOF_SYSTEMD

    log_info "Generating DEB packaging files..."
    cat > "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/control" << EOF_DEB_CONTROL
Package: ${PROJECT_NAME}
Version: ${PROJECT_VERSION}-${RELEASE_VERSION}
Architecture: all
Maintainer: ${MAINTAINER_NAME} <${MAINTAINER_EMAIL}>
Depends: docker-ce | docker.io | docker-engine, curl, jq, openssl, coreutils
Description: ${SUMMARY}
 ${DESCRIPTION}
 .
 This package installs the ${PROJECT_NAME} and its management scripts.
 It will attempt a non-interactive setup if /etc/${PROJECT_NAME}/preconfig.env exists.
 Otherwise, run 'sudo /opt/${PROJECT_NAME}/platform_installer.sh setup_interactive'.
Installed-Size: 120
Section: utils
Priority: optional
Homepage: ${URL}
EOF_DEB_CONTROL

    cat > "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/postinst" << EOF_DEB_POSTINST
#!/bin/bash
set -e
echo "Enabling ${PROJECT_NAME} systemd service..."
if command -v systemctl >/dev/null; then
    systemctl enable ${PROJECT_NAME}.service
    systemctl daemon-reload 
else
    echo "Warning: systemctl not found, cannot enable service automatically."
fi

echo ""
echo "${PROJECT_NAME} package installed successfully."
echo "Attempting non-interactive setup..."
echo "Pre-configuration can be provided in /etc/${PROJECT_NAME}/preconfig.env"
echo "See /opt/${PROJECT_NAME}/preconfig_example/preconfig.env.example for an example."
echo "Installer log will be in /opt/${PROJECT_NAME}/installer.log"

mkdir -p /opt/${PROJECT_NAME} 
mkdir -p /etc/${PROJECT_NAME} 

if /opt/${PROJECT_NAME}/platform_installer.sh setup_non_interactive; then
    echo "Non-interactive setup attempt finished. Check logs for details."
    if systemctl is-enabled --quiet ${PROJECT_NAME}.service && ! systemctl is-active --quiet ${PROJECT_NAME}.service; then
        echo "Starting ${PROJECT_NAME} service..."
        systemctl start ${PROJECT_NAME}.service || echo "Warning: Failed to start ${PROJECT_NAME} service via systemctl."
    fi
else
    echo "Non-interactive setup could not complete automatically (e.g. preconfig missing/invalid)."
    echo "Please review /opt/${PROJECT_NAME}/installer.log and then run:"
    echo "  sudo /opt/${PROJECT_NAME}/platform_installer.sh setup_interactive"
fi

if getent group docker > /dev/null && [ -n "\$SUDO_USER" ] && id "\$SUDO_USER" &>/dev/null; then
    if ! groups "\$SUDO_USER" | grep -q -w 'docker'; then 
        echo "Adding user \$SUDO_USER to docker group. You may need to log out/in."
        usermod -aG docker "\$SUDO_USER" || echo "Warning: Failed to add user \$SUDO_USER to docker group."
    fi
fi
exit 0
EOF_DEB_POSTINST
    chmod 0755 "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/postinst"

    cat > "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/prerm" << EOF_DEB_PRERM
#!/bin/bash
set -e
echo "Stopping and disabling ${PROJECT_NAME} service before removal..."
if command -v systemctl >/dev/null; then
  if systemctl is-active --quiet ${PROJECT_NAME}.service; then systemctl stop ${PROJECT_NAME}.service; fi
  if systemctl is-enabled --quiet ${PROJECT_NAME}.service; then systemctl disable ${PROJECT_NAME}.service; fi
fi
echo "Note: Docker containers/data in /opt/${PROJECT_NAME}/data are NOT automatically removed."
exit 0
EOF_DEB_PRERM
    chmod 0755 "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/prerm"

    log_info "Generating RPM .spec file..."
    cat > "./${BUILD_DIR_BASE}/packaging/rpm/SPECS/${PROJECT_NAME}.spec" << EOF_RPM_SPEC
Name:       ${PROJECT_NAME}
Version:    ${PROJECT_VERSION}
Release:    ${RELEASE_VERSION}%{?dist}
Summary:    ${SUMMARY}
License:    ${LICENSE}
URL:        ${URL}
Packager:   ${MAINTAINER_NAME} <${MAINTAINER_EMAIL}>
Source0:    %{name}-%{version}.tar.gz

BuildArch:  noarch
Requires:   curl, jq, openssl, coreutils, systemd

%description
${DESCRIPTION}
This package installs the ${PROJECT_NAME} and its management scripts.
It will attempt a non-interactive setup if /etc/%{name}/preconfig.env exists.
Otherwise, run 'sudo /opt/%{name}/platform_installer.sh setup_interactive'.

%prep
%setup -q -n src 

%build
# No build

%install
mkdir -p %{buildroot}/opt/%{name}
mkdir -p %{buildroot}/usr/lib/systemd/system 
mkdir -p %{buildroot}/opt/%{name}/preconfig_example 
mkdir -p %{buildroot}/etc/%{name} 

install -m 0755 platform_installer.sh %{buildroot}/opt/%{name}/platform_installer.sh
install -m 0644 preconfig_example/preconfig.env.example %{buildroot}/opt/%{name}/preconfig_example/preconfig.env.example
install -m 0644 ${PROJECT_NAME}.service %{buildroot}/usr/lib/systemd/system/%{name}.service

%post
%systemd_post %{name}.service
echo ""
echo "${PROJECT_NAME} package installed successfully."
echo "Attempting non-interactive setup..."
echo "Pre-configuration can be provided in /etc/%{name}/preconfig.env"
echo "See /opt/%{name}/preconfig_example/preconfig.env.example for an example."
echo "Installer log will be in /opt/%{name}/installer.log"

mkdir -p /opt/%{name} 

if /opt/%{name}/platform_installer.sh setup_non_interactive; then
    echo "Non-interactive setup attempt finished. Check logs for details."
    if systemctl is-enabled --quiet %{name}.service && ! systemctl is-active --quiet %{name}.service; then
        echo "Starting %{name} service..."
        systemctl start %{name}.service || echo "Warning: Failed to start %{name} service via systemctl."
    fi
else
    echo "Non-interactive setup could not complete automatically (e.g. preconfig missing/invalid)."
    echo "Please review /opt/%{name}/installer.log and then run:"
    echo "  sudo /opt/%{name}/platform_installer.sh setup_interactive"
fi

%preun
%systemd_preun %{name}.service

%postun
%systemd_postun_with_restart %{name}.service
echo "Note: Docker containers/data in /opt/%{name}/data are NOT automatically removed."

%files
/opt/%{name}/platform_installer.sh
/opt/%{name}/preconfig_example/preconfig.env.example
%dir /etc/%{name} 
/usr/lib/systemd/system/%{name}.service

%changelog
* $(date +"%a %b %d %Y") ${MAINTAINER_NAME} <${MAINTAINER_EMAIL}> - ${PROJECT_VERSION}-${RELEASE_VERSION}
- Suppressed rpmbuild output.
EOF_RPM_SPEC

    log_info "Project file generation complete."
}

build_deb_package() {
    log_info "Building DEB package..."
    check_build_tool "dpkg-deb"; check_build_tool "fakeroot"
    local DEB_BUILD_AREA="./${BUILD_DIR_BASE}/deb_package_root"
    rm -rf "${DEB_BUILD_AREA}"
    mkdir -p "${DEB_BUILD_AREA}/DEBIAN"
    mkdir -p "${DEB_BUILD_AREA}/opt/${PROJECT_NAME}/preconfig_example"
    mkdir -p "${DEB_BUILD_AREA}/usr/lib/systemd/system"
    mkdir -p "${DEB_BUILD_AREA}/etc/${PROJECT_NAME}" 

    cp -r "./${BUILD_DIR_BASE}/packaging/deb/DEBIAN/"* "${DEB_BUILD_AREA}/DEBIAN/"
    cp "./${BUILD_DIR_BASE}/src/platform_installer.sh" "${DEB_BUILD_AREA}/opt/${PROJECT_NAME}/"
    cp "./${BUILD_DIR_BASE}/src/preconfig_example/preconfig.env.example" "${DEB_BUILD_AREA}/opt/${PROJECT_NAME}/preconfig_example/"
    cp "./${BUILD_DIR_BASE}/src/${PROJECT_NAME}.service" "${DEB_BUILD_AREA}/usr/lib/systemd/system/"
    
    local DEB_FILENAME="${PROJECT_NAME}_${PROJECT_VERSION}-${RELEASE_VERSION}_all.deb"
    fakeroot dpkg-deb --build "${DEB_BUILD_AREA}" "./${BUILD_DIR_BASE}/dist/${DEB_FILENAME}"
    log_info "DEB package created: ./${BUILD_DIR_BASE}/dist/${DEB_FILENAME}"
}

build_rpm_package() {
    log_info "Building RPM package..."
    check_build_tool "rpmbuild"; check_build_tool "tar"

    local RPM_SOURCES_DIR_ABS 
    RPM_SOURCES_DIR_ABS="$(cd "./${BUILD_DIR_BASE}/packaging/rpm/SOURCES" && pwd)"
    local TARBALL_NAME="${PROJECT_NAME}-${PROJECT_VERSION}.tar.gz" 
    local TARBALL_FULL_PATH="${RPM_SOURCES_DIR_ABS}/${TARBALL_NAME}"

    log_info "Creating source tarball: ${TARBALL_FULL_PATH}"
    (cd "./${BUILD_DIR_BASE}" && tar -czf "${TARBALL_FULL_PATH}" src)

    if [ ! -f "${TARBALL_FULL_PATH}" ]; then
        log_error "Failed to create source tarball at ${TARBALL_FULL_PATH}"
    fi

    log_info "Attempting to build RPM (rpmbuild output suppressed)..."
    local RPM_TOPDIR_ABS; RPM_TOPDIR_ABS="$(cd "./${BUILD_DIR_BASE}/packaging/rpm" && pwd)"

    local dist_tag=".elX" 
    if [ -f /etc/os-release ]; then 
        # shellcheck source=/dev/null
        source /etc/os-release
        if [[ "$ID" == "almalinux" || "$ID" == "centos" || "$ID" == "rhel" || "$ID" == "fedora" || "$ID" == "rocky" ]]; then
            dist_tag=".el${VERSION_ID%%.*}"; [[ "$ID" == "fedora" ]] && dist_tag=".fc${VERSION_ID}"
        fi
    elif [ -f /etc/redhat-release ]; then 
        dist_tag=".el$(grep -oE '[0-9]+' /etc/redhat-release | head -1)"
    else 
        log_warn "Could not accurately determine OS distribution tag for RPM naming on build host. Using '${dist_tag}'."
    fi
    log_info "Using dist tag: ${dist_tag} for RPM build."

    # Suppress rpmbuild stdout and stderr by redirecting to /dev/null
    # WARNING: This hides all build messages from rpmbuild, including potential errors during spec processing.
    if rpmbuild -ba \
        --define "_topdir ${RPM_TOPDIR_ABS}" \
        --define "dist ${dist_tag}" \
        "${RPM_TOPDIR_ABS}/SPECS/${PROJECT_NAME}.spec" > /dev/null 2>&1; then # Output suppressed
      log_info "rpmbuild command completed."
    else
      # If rpmbuild returns non-zero, it indicates failure.
      log_error "rpmbuild command failed. No detailed output from rpmbuild was captured due to suppression. Check spec file and rpmbuild environment manually if issues persist."
    fi
    
    local BUILT_RPM_PATH; 
    BUILT_RPM_PATH=$(find "${RPM_TOPDIR_ABS}/RPMS/noarch/" -name "${PROJECT_NAME}-${PROJECT_VERSION}-${RELEASE_VERSION}${dist_tag}.noarch.rpm" -print -quit 2>/dev/null)
    
    if [ -n "${BUILT_RPM_PATH}" ] && [ -f "${BUILT_RPM_PATH}" ]; then
        cp "${BUILT_RPM_PATH}" "./${BUILD_DIR_BASE}/dist/"
        log_info "RPM package created: ./${BUILD_DIR_BASE}/dist/$(basename "${BUILT_RPM_PATH}")"
    else
        log_warn "RPM build process finished, but the RPM file was not found where expected."
        log_warn "Expected: ${RPM_TOPDIR_ABS}/RPMS/noarch/${PROJECT_NAME}-${PROJECT_VERSION}-${RELEASE_VERSION}${dist_tag}.noarch.rpm"
        ls -R "${RPM_TOPDIR_ABS}/RPMS/" || true
    fi
}


# --- Main Script Execution ---
log_info "Starting SMB Platform Package Generator (generate_installers_for_SMBs_platform.sh)..."
generate_project_files
build_deb_package
build_rpm_package
log_info "Package generation process complete. Output: ./${BUILD_DIR_BASE}/dist/"
exit 0
