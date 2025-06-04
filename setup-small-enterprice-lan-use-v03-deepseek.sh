#!/bin/bash
set -euo pipefail

# Global variables
DISTRO=""
DISTRO_VERSION=""
ARCH=""
OFFLINE_DIR="enterprise-offline"
INSTALL_DIR="/opt/enterprise"
DOCS_DIR="$INSTALL_DIR/docs"
CONFIG_DIR="$INSTALL_DIR/config"
CERTS_DIR="$INSTALL_DIR/certs"
REPO_DIR="$INSTALL_DIR/repos"
DATA_DIR="$INSTALL_DIR/data"
COMPOSE_DIR="$INSTALL_DIR/compose"
LOG_FILE="/var/log/enterprise-installer.log"

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Resource optimization variables
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))
TOTAL_CORES=$(nproc)

# Main function
main() {
    detect_os
    parse_arguments "$@"
    
    if [[ $MODE == "online" ]]; then
        prepare_offline_bundle
    elif [[ $MODE == "offline" ]]; then
        offline_installation
    else
        echo -e "${RED}Invalid mode specified. Use --online or --offline${NC}"
        exit 1
    fi
}

# Detect OS and architecture
detect_os() {
    ARCH=$(uname -m)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="almalinux"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    else
        echo -e "${RED}Unsupported Linux distribution${NC}"
        exit 1
    fi

    echo -e "${GREEN}Detected OS: $DISTRO $DISTRO_VERSION ($ARCH)${NC}"
    echo -e "${YELLOW}System Resources: ${TOTAL_CORES} CPU Cores, ${TOTAL_MEM_MB}MB RAM${NC}"
}

# Parse command line arguments
parse_arguments() {
    MODE=""
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --online)
                MODE="online"
                shift
                ;;
            --offline)
                MODE="offline"
                shift
                ;;
            *)
                echo -e "${RED}Unknown argument: $1${NC}"
                exit 1
                ;;
        esac
    done

    if [[ -z "$MODE" ]]; then
        echo -e "${RED}Please specify --online or --offline mode${NC}"
        exit 1
    fi
}

# Calculate optimized resource limits
calculate_resources() {
    # Calculate DB resources (25% of total RAM)
    DB_MEM=$((TOTAL_MEM_MB / 4))
    DB_SHARED_BUFFERS=$((DB_MEM / 4))
    DB_WORK_MEM=$((DB_MEM / 100))
    
    # Calculate Redis memory (10% of total RAM, max 1GB)
    REDIS_MEM=$((TOTAL_MEM_MB / 10))
    [[ $REDIS_MEM -gt 1024 ]] && REDIS_MEM=1024
    
    # Calculate application resources
    APP_MEM=$((TOTAL_MEM_MB / 20))
    [[ $APP_MEM -lt 128 ]] && APP_MEM=128
    [[ $APP_MEM -gt 1024 ]] && APP_MEM=1024
    
    # Calculate worker processes
    WORKER_PROCESSES=$TOTAL_CORES
    [[ $WORKER_PROCESSES -gt 8 ]] && WORKER_PROCESSES=8
}

# Online preparation functions
prepare_offline_bundle() {
    echo -e "${GREEN}Starting offline bundle preparation...${NC}"
    
    # Calculate resource allocations
    calculate_resources
    
    # Create directory structure
    create_directory_structure
    
    # Install required tools for preparation
    install_preparation_tools
    
    # Download system packages
    download_system_packages
    
    # Download Docker images
    download_docker_images
    
    # Generate SSL certificates
    generate_ssl_certificates
    
    # Create local repositories
    create_local_repositories
    
    # Generate documentation
    generate_documentation
    
    # Create Docker Compose configuration
    create_docker_compose_config
    
    # Create installer script
    create_installer_script
    
    # Package everything
    package_offline_bundle
    
    echo -e "${GREEN}Offline bundle preparation complete!${NC}"
    echo -e "Created $OFFLINE_DIR.tar.gz - transfer this to your offline server"
    echo -e "Allocated Resources:"
    echo -e "  - Database: ${DB_MEM}MB (Shared buffers: ${DB_SHARED_BUFFERS}MB)"
    echo -e "  - Redis: ${REDIS_MEM}MB"
    echo -e "  - Applications: ${APP_MEM}MB each"
    echo -e "  - Worker Processes: ${WORKER_PROCESSES}"
}

create_directory_structure() {
    echo -e "${YELLOW}Creating directory structure...${NC}"
    mkdir -p "$OFFLINE_DIR"/{packages,docker,repos,config,certs,docs,scripts,data,compose}
}

install_preparation_tools() {
    echo -e "${YELLOW}Installing required tools for preparation...${NC}"
    
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
        apt-get update
        apt-get install -y curl wget tar gzip skopeo docker.io docker-compose createrepo-c jq
    elif [[ "$DISTRO" == "almalinux" ]]; then
        dnf install -y curl wget tar gzip skopeo docker-ce docker-compose-plugin createrepo_c jq
        systemctl enable --now docker
    fi
}

download_system_packages() {
    echo -e "${YELLOW}Downloading system packages...${NC}"
    
    local pkg_list=(
        "haproxy nginx bind9 dnsmasq fail2ban"
        "cockpit netdata postgresql redis-server"
    )
    
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
        mkdir -p "$OFFLINE_DIR/packages/apt"
        apt-get update
        apt-get download $(echo "${pkg_list[@]}" | tr ' ' '\n' | sort -u)
        mv *.deb "$OFFLINE_DIR/packages/apt/"
        
        # Create Packages.gz for local repo
        cd "$OFFLINE_DIR/packages/apt"
        dpkg-scanpackages . /dev/null | gzip -9c > Packages.gz
        cd -
    elif [[ "$DISTRO" == "almalinux" ]]; then
        mkdir -p "$OFFLINE_DIR/packages/yum"
        dnf download $(echo "${pkg_list[@]}" | tr ' ' '\n' | sort -u)
        mv *.rpm "$OFFLINE_DIR/packages/yum/"
        
        # Create yum repo metadata
        createrepo_c "$OFFLINE_DIR/packages/yum"
    fi
}

download_docker_images() {
    echo -e "${YELLOW}Downloading Docker images...${NC}"
    
    # Core infrastructure images
    local core_images=(
        "traefik:latest"
        "portainer/portainer-ce:latest"
        "lscr.io/linuxserver/heimdall:latest"
        "postgres:15-alpine"
        "redis:7-alpine"
        "nginx:alpine"
        "haproxy:alpine"
    )
    
    # Enterprise application images
    local app_images=(
        "nextcloud:latest"
        "rocket.chat:latest"
        "jitsi/web:latest"
        "suitecrm/suitecrm:latest"
        "mattermost/mattermost-team-edition:latest"
        "gitlab/gitlab-ce:latest"
        "onlyoffice/documentserver:latest"
        "frappe/erpnext:latest"
        "odoo:latest"
        "moodle:latest"
        "matomo:latest"
        "wekan/wekan:latest"
        "taiga:latest"
        "discourse:latest"
        "openproject/openproject:latest"
        "invoiceninja/invoiceninja:latest"
        "monica:latest"
        "grafana/grafana:latest"
        "prom/prometheus:latest"
        "prom/node-exporter:latest"
        "prom/alertmanager:latest"
    )
    
    # Download core images
    for image in "${core_images[@]}"; do
        echo "Downloading $image..."
        skopeo copy docker://$image dir:$OFFLINE_DIR/docker/$(echo $image | tr '/:' '_')
    done
    
    # Download application images
    for image in "${app_images[@]}"; do
        echo "Downloading $image..."
        skopeo copy docker://$image dir:$OFFLINE_DIR/docker/$(echo $image | tr '/:' '_')
    done
}

generate_ssl_certificates() {
    echo -e "${YELLOW}Generating SSL certificates...${NC}"
    
    mkdir -p "$OFFLINE_DIR/certs"
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$OFFLINE_DIR/certs/enterprise.key" \
        -out "$OFFLINE_DIR/certs/enterprise.crt" \
        -subj "/CN=enterprise.local/O=Enterprise Platform/C=US"
    
    # Generate wildcard certificate
    openssl req -x509 -nodes -days 3650 -newkey rsa:4096 \
        -keyout "$OFFLINE_DIR/certs/wildcard.key" \
        -out "$OFFLINE_DIR/certs/wildcard.crt" \
        -subj "/CN=*.enterprise.local/O=Enterprise Platform/C=US"
}

create_local_repositories() {
    echo -e "${YELLOW}Creating local repositories...${NC}"
    
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
        cat > "$OFFLINE_DIR/config/apt-local.list" <<EOF
deb [trusted=yes] file://$INSTALL_DIR/repos/apt ./
EOF
    elif [[ "$DISTRO" == "almalinux" ]]; then
        cat > "$OFFLINE_DIR/config/yum-local.repo" <<EOF
[local]
name=Local Enterprise Repository
baseurl=file://$INSTALL_DIR/repos/yum
enabled=1
gpgcheck=0
EOF
    fi
}

generate_documentation() {
    echo -e "${YELLOW}Generating documentation templates...${NC}"
    
    mkdir -p "$OFFLINE_DIR/docs"
    
    # Admin guide
    cat > "$OFFLINE_DIR/docs/ADMIN_GUIDE.md" <<EOF
# Enterprise Platform Admin Guide

## System Architecture
- **Host OS**: $DISTRO $DISTRO_VERSION
- **Total RAM**: ${TOTAL_MEM_MB}MB
- **CPU Cores**: ${TOTAL_CORES}
- **Installation Directory**: $INSTALL_DIR

## Resource Allocation
- Database Memory: ${DB_MEM}MB
- Redis Memory: ${REDIS_MEM}MB
- Application Memory: ${APP_MEM}MB each
- Worker Processes: ${WORKER_PROCESSES}

## Service Ports
| Service       | Port  | Protocol |
|---------------|-------|----------|
| Traefik UI    | 8080  | HTTP     |
| Portainer     | 9000  | HTTP     |
| Heimdall      | 9080  | HTTP     |
| Cockpit       | 9090  | HTTP     |
| Netdata       | 19999 | HTTP     |

## Maintenance Commands
- Start all services: \`docker-compose -f $COMPOSE_DIR/docker-compose.yml up -d\`
- Stop all services: \`docker-compose -f $COMPOSE_DIR/docker-compose.yml down\`
- View logs: \`docker-compose -f $COMPOSE_DIR/docker-compose.yml logs -f\`

## Backup Procedure
1. Stop services: \`docker-compose -f $COMPOSE_DIR/docker-compose.yml down\`
2. Backup: \`tar -czf /backup/enterprise-backup-\$(date +%F).tar.gz $INSTALL_DIR\`
3. Start services: \`docker-compose -f $COMPOSE_DIR/docker-compose.yml up -d\`
EOF

    # User guide
    cat > "$OFFLINE_DIR/docs/USER_GUIDE.md" <<EOF
# Enterprise Platform User Guide

## Accessing Services
- **Dashboard**: https://your-server-ip
- **Applications**: 
  - Nextcloud: /nextcloud
  - Rocket.Chat: /chat
  - GitLab: /gitlab
  - Mattermost: /mattermost
  - ERPNext: /erpnext
  - Odoo: /odoo
  - InvoiceNinja: /invoicing

## Getting Started
1. Access the unified dashboard at the server IP
2. Use the application launcher to access services
3. Default credentials (change immediately):
   - Username: admin
   - Password: changeme

## Support
Contact your system administrator for:
- Account issues
- Application access problems
- Performance concerns
EOF
}

create_docker_compose_config() {
    echo -e "${YELLOW}Creating Docker Compose configuration...${NC}"
    
    mkdir -p "$OFFLINE_DIR/compose"
    
    # Main docker-compose file
    cat > "$OFFLINE_DIR/compose/docker-compose.yml" <<EOF
version: '3.8'

networks:
  enterprise-net:
    driver: bridge

services:
  # Reverse Proxy
  traefik:
    image: traefik:latest
    container_name: traefik
    ports:
      - "80:80"
      - "443:443"
      - "8080:8080" # Dashboard
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - $CONFIG_DIR/traefik.yml:/etc/traefik/traefik.yml
      - $CONFIG_DIR/dynamic.yml:/etc/traefik/dynamic.yml
      - $CERTS_DIR:/certs
    networks:
      - enterprise-net
    restart: unless-stopped

  # Management
  portainer:
    image: portainer/portainer-ce:latest
    container_name: portainer
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock
      - $DATA_DIR/portainer:/data
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.portainer.rule=Host(\`portainer.enterprise.local\`)"
      - "traefik.http.routers.portainer.tls=true"
      - "traefik.http.routers.portainer.entrypoints=websecure"
      - "traefik.http.services.portainer.loadbalancer.server.port=9000"
    restart: unless-stopped

  # Unified Dashboard
  heimdall:
    image: lscr.io/linuxserver/heimdall:latest
    container_name: heimdall
    environment:
      - PUID=1000
      - PGID=1000
      - TZ=UTC
    volumes:
      - $DATA_DIR/heimdall:/config
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.heimdall.rule=Host(\`dashboard.enterprise.local\`)"
      - "traefik.http.routers.heimdall.tls=true"
      - "traefik.http.routers.heimdall.entrypoints=websecure"
      - "traefik.http.services.heimdall.loadbalancer.server.port=80"
    restart: unless-stopped

  # Database
  postgres:
    image: postgres:15-alpine
    container_name: postgres
    environment:
      POSTGRES_DB: enterprise
      POSTGRES_USER: admin
      POSTGRES_PASSWORD: \${DB_PASSWORD}
    volumes:
      - $DATA_DIR/postgres:/var/lib/postgresql/data
    networks:
      - enterprise-net
    restart: unless-stopped
    # Resource optimization
    deploy:
      resources:
        limits:
          cpus: '1.0'
          memory: ${DB_MEM}M

  # Cache
  redis:
    image: redis:7-alpine
    container_name: redis
    command: redis-server --maxmemory ${REDIS_MEM}mb --maxmemory-policy allkeys-lru
    volumes:
      - $DATA_DIR/redis:/data
    networks:
      - enterprise-net
    restart: unless-stopped

  # Enterprise Applications
  nextcloud:
    image: nextcloud:latest
    container_name: nextcloud
    volumes:
      - $DATA_DIR/nextcloud:/var/www/html
    environment:
      - POSTGRES_HOST=postgres
      - POSTGRES_DB=nextcloud
      - POSTGRES_USER=admin
      - POSTGRES_PASSWORD=\${DB_PASSWORD}
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.nextcloud.rule=PathPrefix(\`/nextcloud\`)"
      - "traefik.http.routers.nextcloud.tls=true"
    depends_on:
      - postgres
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${APP_MEM}M

  gitlab:
    image: gitlab/gitlab-ce:latest
    container_name: gitlab
    volumes:
      - $DATA_DIR/gitlab/config:/etc/gitlab
      - $DATA_DIR/gitlab/logs:/var/log/gitlab
      - $DATA_DIR/gitlab/data:/var/opt/gitlab
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.gitlab.rule=Host(\`gitlab.enterprise.local\`)"
      - "traefik.http.routers.gitlab.tls=true"
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: 2048M

  erpnext:
    image: frappe/erpnext:latest
    container_name: erpnext
    environment:
      - MARIADB_HOST=postgres
      - SITE_NAME=erp.enterprise.local
      - ADMIN_PASSWORD=\${ADMIN_PASSWORD}
    volumes:
      - $DATA_DIR/erpnext:/home/frappe/frappe-bench/sites
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.erpnext.rule=Host(\`erp.enterprise.local\`)"
      - "traefik.http.routers.erpnext.tls=true"
    depends_on:
      - postgres
    restart: unless-stopped
    deploy:
      resources:
        limits:
          memory: ${APP_MEM}M

  # Monitoring
  prometheus:
    image: prom/prometheus:latest
    container_name: prometheus
    volumes:
      - $CONFIG_DIR/prometheus.yml:/etc/prometheus/prometheus.yml
    networks:
      - enterprise-net
    restart: unless-stopped

  grafana:
    image: grafana/grafana:latest
    container_name: grafana
    volumes:
      - $DATA_DIR/grafana:/var/lib/grafana
    networks:
      - enterprise-net
    labels:
      - "traefik.http.routers.grafana.rule=Host(\`grafana.enterprise.local\`)"
      - "traefik.http.routers.grafana.tls=true"
    restart: unless-stopped
EOF

    # Traefik configuration
    mkdir -p "$OFFLINE_DIR/config"
    cat > "$OFFLINE_DIR/config/traefik.yml" <<EOF
global:
  sendAnonymousUsage: false

entryPoints:
  web:
    address: ":80"
    http:
      redirections:
        entryPoint:
          to: websecure
          scheme: https
  websecure:
    address: ":443"

providers:
  docker:
    exposedByDefault: false
  file:
    filename: /etc/traefik/dynamic.yml

certificatesResolvers:
  default:
    acme:
      email: admin@enterprise.local
      storage: /etc/traefik/acme.json
      httpChallenge:
        entryPoint: web
EOF

    cat > "$OFFLINE_DIR/config/dynamic.yml" <<EOF
http:
  middlewares:
    https-redirect:
      redirectScheme:
        scheme: https
    secure-headers:
      headers:
        sslRedirect: true
        stsIncludeSubdomains: true
        stsPreload: true
        stsSeconds: 31536000
        forceSTSHeader: true

tls:
  certificates:
    - certFile: /certs/enterprise.crt
      keyFile: /certs/enterprise.key
    - certFile: /certs/wildcard.crt
      keyFile: /certs/wildcard.key
EOF
}

create_installer_script() {
    echo -e "${YELLOW}Creating offline installer script...${NC}"
    
    cat > "$OFFLINE_DIR/install.sh" <<'EOF'
#!/bin/bash
set -euo pipefail

# Installation functions
install_system_packages() {
    echo -e "${YELLOW}Installing system packages...${NC}"
    
    if [[ "$DISTRO" == "ubuntu" || "$DISTRO" == "debian" ]]; then
        # Setup local APT repo
        cp "$CONFIG_DIR/apt-local.list" /etc/apt/sources.list.d/enterprise.list
        mkdir -p /var/local/apt-repo
        cp -r "$REPO_DIR/apt/"* /var/local/apt-repo/
        apt-get update
        
        # Install packages
        apt-get install -y haproxy nginx bind9 dnsmasq \
            postgresql redis-server cockpit netdata fail2ban \
            docker.io docker-compose
    elif [[ "$DISTRO" == "almalinux" ]]; then
        # Setup local YUM repo
        cp "$CONFIG_DIR/yum-local.repo" /etc/yum.repos.d/enterprise.repo
        mkdir -p /var/local/yum-repo
        cp -r "$REPO_DIR/yum/"* /var/local/yum-repo/
        dnf makecache
        
        # Install packages
        dnf install -y haproxy nginx bind dnsmasq \
            postgresql redis cockpit netdata fail2ban \
            docker-ce docker-compose-plugin
    fi
    
    # Start and enable Docker
    systemctl enable --now docker
}

load_docker_images() {
    echo -e "${YELLOW}Loading Docker images...${NC}"
    
    if ! command -v docker &>/dev/null; then
        echo -e "${RED}Docker is not installed!${NC}"
        exit 1
    fi
    
    for img_dir in "$INSTALL_DIR/docker/"*; do
        skopeo copy dir:"$img_dir" docker-daemon:$(basename "$img_dir" | tr '_' '/:')
    done
}

configure_system() {
    echo -e "${YELLOW}Configuring system...${NC}"
    
    # Disable conflicting services
    systemctl stop apache2 httpd || true
    systemctl disable apache2 httpd || true
    
    # Enable and start required services
    systemctl enable --now postgresql redis
    
    # Configure firewall
    if command -v ufw &>/dev/null; then
        ufw allow 22,80,443,9090,9000,9080/tcp
        ufw --force enable
    elif command -v firewall-cmd &>/dev/null; then
        firewall-cmd --permanent --add-service={http,https,ssh,cockpit}
        firewall-cmd --permanent --add-port={9000/tcp,9080/tcp}
        firewall-cmd --reload
    fi
    
    # Configure kernel parameters
    sysctl -w net.core.somaxconn=65535
    sysctl -w vm.overcommit_memory=1
    sysctl -w kernel.panic=10
    sysctl -w kernel.panic_on_oops=1
    echo "net.core.somaxconn=65535" >> /etc/sysctl.conf
    echo "vm.overcommit_memory=1" >> /etc/sysctl.conf
}

generate_passwords() {
    echo -e "${YELLOW}Generating secure passwords...${NC}"
    
    DB_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()' < /dev/urandom | head -c 32)
    ADMIN_PASSWORD=$(tr -dc 'A-Za-z0-9!@#$%^&*()' < /dev/urandom | head -c 24)
    SECRET_KEY=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)
    
    # Create env file
    cat > "$COMPOSE_DIR/.env" <<ENV_EOF
DB_PASSWORD=$DB_PASSWORD
ADMIN_PASSWORD=$ADMIN_PASSWORD
SECRET_KEY=$SECRET_KEY
ENV_EOF
    
    # Store passwords in secure location
    mkdir -p "$CONFIG_DIR/secrets"
    chmod 700 "$CONFIG_DIR/secrets"
    echo "Database Password: $DB_PASSWORD" > "$CONFIG_DIR/secrets/passwords.txt"
    echo "Admin Password: $ADMIN_PASSWORD" >> "$CONFIG_DIR/secrets/passwords.txt"
    echo "Secret Key: $SECRET_KEY" >> "$CONFIG_DIR/secrets/passwords.txt"
    chmod 600 "$CONFIG_DIR/secrets/passwords.txt"
}

optimize_configurations() {
    echo -e "${YELLOW}Optimizing configurations...${NC}"
    
    # PostgreSQL optimization
    sed -i "s/#shared_buffers = 128MB/shared_buffers = ${DB_SHARED_BUFFERS}MB/" /etc/postgresql/*/main/postgresql.conf
    sed -i "s/#work_mem = 4MB/work_mem = ${DB_WORK_MEM}MB/" /etc/postgresql/*/main/postgresql.conf
    sed -i "s/#max_connections = 100/max_connections = 200/" /etc/postgresql/*/main/postgresql.conf
    
    # Redis optimization
    sed -i "s/# maxmemory <bytes>/maxmemory ${REDIS_MEM}mb/" /etc/redis/redis.conf
    sed -i "s/# maxmemory-policy noeviction/maxmemory-policy allkeys-lru/" /etc/redis/redis.conf
    
    # Nginx optimization
    sed -i "s/worker_processes auto/worker_processes ${WORKER_PROCESSES}/" /etc/nginx/nginx.conf
    sed -i "s/# server_names_hash_bucket_size 64;/server_names_hash_bucket_size 128;/" /etc/nginx/nginx.conf
    
    # HAProxy optimization
    echo "maxconn 50000" >> /etc/haproxy/haproxy.cfg
    echo "tune.ssl.default-dh-param 2048" >> /etc/haproxy/haproxy.cfg
}

start_services() {
    echo -e "${YELLOW}Starting services...${NC}"
    
    # Start Docker Compose stack
    docker-compose -f "$COMPOSE_DIR/docker-compose.yml" --env-file "$COMPOSE_DIR/.env" up -d
    
    # Enable system services
    systemctl restart nginx postgresql redis
    systemctl enable --now cockpit.socket netdata
}

post_installation() {
    echo -e "${YELLOW}Running post-installation tasks...${NC}"
    
    # Initialize applications
    docker exec -it erpnext bench new-site erp.enterprise.local \
        --mariadb-root-password "$DB_PASSWORD" \
        --admin-password "$ADMIN_PASSWORD"
    
    # Display installation summary
    IP_ADDR=$(hostname -I | awk '{print $1}')
    echo -e "${GREEN}Installation complete!${NC}"
    echo -e "================================================"
    echo -e "Enterprise Platform Access Information"
    echo -e "================================================"
    echo -e "Dashboard:      https://$IP_ADDR"
    echo -e "Portainer:      https://$IP_ADDR:9000"
    echo -e "Heimdall:       https://$IP_ADDR:9080"
    echo -e "Cockpit:        https://$IP_ADDR:9090"
    echo -e "Netdata:        http://$IP_ADDR:19999"
    echo -e "Admin Password: $ADMIN_PASSWORD"
    echo -e "================================================"
    echo -e "Passwords stored in: $CONFIG_DIR/secrets/passwords.txt"
    echo -e "Documentation: $DOCS_DIR"
}

# Main offline installation
offline_installation() {
    detect_os
    calculate_resources
    
    echo -e "${GREEN}Starting offline installation...${NC}"
    
    # Create installation directory
    mkdir -p "$INSTALL_DIR"
    cp -r ./* "$INSTALL_DIR/"
    
    # Install system packages
    install_system_packages
    
    # Load Docker images
    load_docker_images
    
    # Configure system
    configure_system
    
    # Generate passwords
    generate_passwords
    
    # Optimize configurations
    optimize_configurations
    
    # Start services
    start_services
    
    # Post-installation tasks
    post_installation
}

# Include common functions
INSTALL_DIR="/opt/enterprise"
DOCS_DIR="$INSTALL_DIR/docs"
CONFIG_DIR="$INSTALL_DIR/config"
CERTS_DIR="$INSTALL_DIR/certs"
REPO_DIR="$INSTALL_DIR/repos"
DATA_DIR="$INSTALL_DIR/data"
COMPOSE_DIR="$INSTALL_DIR/compose"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Resource optimization variables
TOTAL_MEM=$(grep MemTotal /proc/meminfo | awk '{print $2}')
TOTAL_MEM_MB=$((TOTAL_MEM / 1024))
TOTAL_CORES=$(nproc)

calculate_resources() {
    DB_MEM=$((TOTAL_MEM_MB / 4))
    DB_SHARED_BUFFERS=$((DB_MEM / 4))
    DB_WORK_MEM=$((DB_MEM / 100))
    REDIS_MEM=$((TOTAL_MEM_MB / 10))
    [[ $REDIS_MEM -gt 1024 ]] && REDIS_MEM=1024
    APP_MEM=$((TOTAL_MEM_MB / 20))
    [[ $APP_MEM -lt 128 ]] && APP_MEM=128
    [[ $APP_MEM -gt 1024 ]] && APP_MEM=1024
    WORKER_PROCESSES=$TOTAL_CORES
    [[ $WORKER_PROCESSES -gt 8 ]] && WORKER_PROCESSES=8
}

detect_os() {
    ARCH=$(uname -m)
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        DISTRO_VERSION=$VERSION_ID
    elif [[ -f /etc/redhat-release ]]; then
        DISTRO="almalinux"
        DISTRO_VERSION=$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release)
    else
        echo -e "${RED}Unsupported Linux distribution${NC}"
        exit 1
    fi
}

offline_installation
EOF

    chmod +x "$OFFLINE_DIR/install.sh"
}

package_offline_bundle() {
    echo -e "${YELLOW}Packaging offline bundle...${NC}"
    tar -czf "$OFFLINE_DIR.tar.gz" "$OFFLINE_DIR"
    echo -e "${GREEN}Created offline bundle: $OFFLINE_DIR.tar.gz${NC}"
    du -sh "$OFFLINE_DIR.tar.gz"
}

# Offline installation functions
offline_installation() {
    echo -e "${GREEN}Starting offline installation...${NC}"
    
    # Check if we're running from the extracted directory
    if [[ ! -f "install.sh" ]]; then
        echo -e "${RED}Please extract the offline bundle and run install.sh${NC}"
        exit 1
    fi
    
    # The actual installation is handled by the embedded install.sh script
    ./install.sh
}

# Start main function
main "$@"
