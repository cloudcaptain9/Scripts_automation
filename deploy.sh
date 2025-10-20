#!/bin/bash

#############################################
# Docker Deployment Automation Script
# File: deploy.sh
# Description: Automates setup, deployment, and configuration
#              of a Dockerized application on a remote Linux server
#############################################

set -euo pipefail

# Color codes for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Log file with timestamp
readonly LOG_FILE="deploy_$(date +%Y%m%d_%H%M%S).log"

# Global variables
REPO_URL=""
PAT=""
BRANCH="main"
SSH_USER=""
SSH_HOST=""
SSH_KEY=""
APP_PORT=""
REPO_NAME=""
PROJECT_DIR=""

#############################################
# Logging Functions
#############################################

log() {
    local level="$1"
    shift
    local message="$*"
    local timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[${timestamp}] [${level}] ${message}" | tee -a "${LOG_FILE}"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $*" | tee -a "${LOG_FILE}"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $*" | tee -a "${LOG_FILE}"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $*" | tee -a "${LOG_FILE}"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*" | tee -a "${LOG_FILE}"
}

#############################################
# Error Handling
#############################################

error_exit() {
    log_error "$1"
    exit "${2:-1}"
}

trap 'error_exit "Script failed at line $LINENO with exit code $?" $?' ERR

#############################################
# Validation Functions
#############################################

validate_url() {
    local url="$1"
    if [[ ! "$url" =~ ^https?:// ]]; then
        return 1
    fi
    return 0
}

validate_ip() {
    local ip="$1"
    if [[ "$ip" =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        return 0
    fi
    return 1
}

validate_port() {
    local port="$1"
    if [[ "$port" =~ ^[0-9]+$ ]] && [ "$port" -ge 1 ] && [ "$port" -le 65535 ]; then
        return 0
    fi
    return 1
}

#############################################
# User Input Collection
#############################################

collect_parameters() {
    log_info "Collecting deployment parameters..."
    
    # Git Repository URL
    while true; do
        read -p "Enter Git Repository URL: " REPO_URL
        if validate_url "$REPO_URL"; then
            log_success "Valid repository URL provided"
            break
        else
            log_error "Invalid URL format. Please try again."
        fi
    done
    
    # Extract repository name and convert to lowercase for Docker compatibility
    REPO_NAME=$(basename "$REPO_URL" .git)
    DOCKER_IMAGE_NAME=$(echo "$REPO_NAME" | tr '[:upper:]' '[:lower:]')
    log_info "Repository name: $REPO_NAME"
    log_info "Docker image name: $DOCKER_IMAGE_NAME"
    
    # Personal Access Token
    while true; do
        read -sp "Enter Personal Access Token (PAT): " PAT
        echo
        if [ -n "$PAT" ]; then
            log_success "PAT received"
            break
        else
            log_error "PAT cannot be empty"
        fi
    done
    
    # Branch name
    read -p "Enter branch name (default: main): " BRANCH
    BRANCH="${BRANCH:-main}"
    log_info "Using branch: $BRANCH"
    
    # SSH Username
    while true; do
        read -p "Enter SSH username: " SSH_USER
        if [ -n "$SSH_USER" ]; then
            log_success "SSH username: $SSH_USER"
            break
        else
            log_error "Username cannot be empty"
        fi
    done
    
    # SSH Host
    while true; do
        read -p "Enter server IP address: " SSH_HOST
        if validate_ip "$SSH_HOST"; then
            log_success "Valid IP address: $SSH_HOST"
            break
        else
            log_error "Invalid IP address format"
        fi
    done
    
    # SSH Key Path
    while true; do
        read -p "Enter SSH key path: " SSH_KEY
        # Expand tilde and resolve path
        SSH_KEY="${SSH_KEY/#\~/$HOME}"
        SSH_KEY=$(eval echo "$SSH_KEY")
        
        if [ -f "$SSH_KEY" ]; then
            log_success "SSH key found: $SSH_KEY"
            break
        else
            log_error "SSH key file not found at: $SSH_KEY"
            log_info "Current directory: $(pwd)"
            log_info "Tip: Use full absolute path or copy key to current directory"
        fi
    done
    
    # Application Port
    while true; do
        read -p "Enter application port (internal container port): " APP_PORT
        if validate_port "$APP_PORT"; then
            log_success "Application port: $APP_PORT"
            break
        else
            log_error "Invalid port number (1-65535)"
        fi
    done
    
    # Set project directory AFTER all parameters are collected
    PROJECT_DIR="/home/${SSH_USER}/${REPO_NAME}"
    log_info "Project directory: $PROJECT_DIR"
    
    log_success "All parameters collected successfully"
}

#############################################
# Repository Operations
#############################################

clone_repository() {
    log_info "Step 2: Cloning repository..."
    
    local auth_url="${REPO_URL/https:\/\//https://${PAT}@}"
    
    if [ -d "$REPO_NAME" ]; then
        log_warning "Repository already exists. Pulling latest changes..."
        cd "$REPO_NAME"
        git pull origin "$BRANCH" || error_exit "Failed to pull latest changes"
        cd ..
        log_success "Repository updated"
    else
        git clone -b "$BRANCH" "$auth_url" || error_exit "Failed to clone repository"
        log_success "Repository cloned successfully"
    fi
}

verify_docker_files() {
    log_info "Step 3: Verifying Docker configuration files..."
    
    cd "$REPO_NAME"
    
    if [ -f "Dockerfile" ]; then
        log_success "Dockerfile found"
    elif [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
        log_success "docker-compose.yml found"
    else
        error_exit "No Dockerfile or docker-compose.yml found in repository"
    fi
    
    cd ..
}

#############################################
# SSH Operations
#############################################

test_ssh_connection() {
    log_info "Step 4: Testing SSH connection..."
    
    # Try SSH connection with detailed output
    if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 -o BatchMode=yes "${SSH_USER}@${SSH_HOST}" "echo 'SSH connection successful'" 2>&1 | tee -a "${LOG_FILE}"; then
        log_success "SSH connection successful"
    else
        log_error "SSH connection failed. Trying without BatchMode..."
        # Retry without BatchMode in case host key needs to be added
        if ssh -i "$SSH_KEY" -o StrictHostKeyChecking=no -o ConnectTimeout=10 "${SSH_USER}@${SSH_HOST}" "echo 'SSH connection successful'" 2>&1 | tee -a "${LOG_FILE}"; then
            log_success "SSH connection successful (interactive mode)"
        else
            log_error "Please verify:"
            log_error "  1. SSH key permissions: chmod 400 $SSH_KEY"
            log_error "  2. Server is running and accessible"
            log_error "  3. Security group allows SSH (port 22) from your IP"
            log_error "  4. Try manually: ssh -i $SSH_KEY ${SSH_USER}@${SSH_HOST}"
            error_exit "SSH connection failed"
        fi
    fi
    
    # Test connectivity with ping (optional)
    if command -v ping &> /dev/null; then
        if ping -c 2 "$SSH_HOST" >> "${LOG_FILE}" 2>&1; then
            log_success "Server is reachable (ping successful)"
        else
            log_warning "Ping failed, but SSH might still work"
        fi
    fi
}

#############################################
# Remote Server Setup
#############################################

setup_remote_server() {
    log_info "Step 5: Preparing remote environment..."
    
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" bash << 'ENDSSH'
        set -e
        
        # Update system packages
        echo "Updating system packages..."
        sudo apt-get update -y
        
        # Install Docker if not present
        if ! command -v docker &> /dev/null; then
            echo "Installing Docker..."
            sudo apt-get install -y apt-transport-https ca-certificates curl software-properties-common
            curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
            sudo add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
            sudo apt-get update -y
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io
        else
            echo "Docker already installed"
        fi
        
        # Install Docker Compose if not present
        if ! command -v docker-compose &> /dev/null; then
            echo "Installing Docker Compose..."
            sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
            sudo chmod +x /usr/local/bin/docker-compose
        else
            echo "Docker Compose already installed"
        fi
        
        # Install Nginx if not present
        if ! command -v nginx &> /dev/null; then
            echo "Installing Nginx..."
            sudo apt-get install -y nginx
        else
            echo "Nginx already installed"
        fi
        
        # Add user to Docker group
        if ! groups $USER | grep -q docker; then
            echo "Adding user to Docker group..."
            sudo usermod -aG docker $USER
        fi
        
        # Unmask and enable Docker service (in case it's masked)
        sudo systemctl unmask docker 2>/dev/null || true
        
        # Enable and start services
        sudo systemctl enable docker
        sudo systemctl start docker
        sudo systemctl enable nginx
        sudo systemctl start nginx
        
        # Verify installations
        echo "Docker version: $(docker --version)"
        echo "Docker Compose version: $(docker-compose --version)"
        echo "Nginx version: $(nginx -v 2>&1)"
ENDSSH
    
    log_success "Remote server prepared successfully"
}

#############################################
# File Transfer
#############################################

transfer_files() {
    log_info "Step 6: Transferring project files to remote server..."
    
    # Create remote directory first
    log_info "Creating remote directory: $PROJECT_DIR"
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" "mkdir -p ${PROJECT_DIR}" || error_exit "Failed to create remote directory"
    
    # Remove old files in project directory
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" "rm -rf ${PROJECT_DIR}/*" || true
    
    # Transfer files using rsync if available, otherwise use scp
    if command -v rsync &> /dev/null; then
        log_info "Using rsync for file transfer..."
        rsync -avz -e "ssh -i ${SSH_KEY}" "${REPO_NAME}/" "${SSH_USER}@${SSH_HOST}:${PROJECT_DIR}/" || error_exit "File transfer failed"
    else
        log_info "Using scp for file transfer (rsync not available)..."
        # Transfer files using scp with recursive flag
        scp -i "$SSH_KEY" -r "${REPO_NAME}/"* "${SSH_USER}@${SSH_HOST}:${PROJECT_DIR}/" || error_exit "File transfer failed"
    fi
    
    log_success "Files transferred successfully"
}

#############################################
# Docker Deployment
#############################################

deploy_application() {
    log_info "Step 6: Deploying Dockerized application..."
    
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" bash << ENDSSH
        set -e
        
        cd ${PROJECT_DIR}
        
        # Stop and remove old containers
        echo "Cleaning up old containers..."
        docker-compose down 2>/dev/null || true
        docker stop \$(docker ps -q) 2>/dev/null || true
        docker rm \$(docker ps -aq) 2>/dev/null || true
        
        # Remove unused Docker resources
        docker system prune -f
        
        # Build and run containers
        if [ -f "docker-compose.yml" ] || [ -f "docker-compose.yaml" ]; then
            echo "Building and starting containers with docker-compose..."
            docker-compose up -d --build
        else
            echo "Building Docker image..."
            docker build -t ${REPO_NAME}:latest .
            echo "Running container..."
            docker run -d -p ${APP_PORT}:${APP_PORT} --name ${REPO_NAME} ${REPO_NAME}:latest
        fi
        
        # Wait for containers to start
        sleep 5
        
        # Validate container health
        if docker ps | grep -q "${REPO_NAME}"; then
            echo "Container is running"
            docker ps
        else
            echo "Container failed to start"
            docker logs ${REPO_NAME} 2>&1 || docker-compose logs 2>&1
            exit 1
        fi
ENDSSH
    
    log_success "Application deployed successfully"
}

#############################################
# Nginx Configuration
#############################################

configure_nginx() {
    log_info "Step 7: Configuring Nginx reverse proxy..."
    
    local domain="${SSH_HOST}.nip.io"
    
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" bash << ENDSSH
        set -e
        
        # Create Nginx configuration
        sudo tee /etc/nginx/sites-available/${REPO_NAME} > /dev/null << 'EOF'
server {
    listen 80;
    server_name ${domain} ${SSH_HOST};
    
    location / {
        proxy_pass http://localhost:${APP_PORT};
        proxy_http_version 1.1;
        proxy_set_header Upgrade \$http_upgrade;
        proxy_set_header Connection 'upgrade';
        proxy_set_header Host \$host;
        proxy_cache_bypass \$http_upgrade;
        proxy_set_header X-Real-IP \$remote_addr;
        proxy_set_header X-Forwarded-For \$proxy_add_x_forwarded_for;
        proxy_set_header X-Forwarded-Proto \$scheme;
    }
}
EOF
        
        # Enable site
        sudo ln -sf /etc/nginx/sites-available/${REPO_NAME} /etc/nginx/sites-enabled/${REPO_NAME}
        
        # Remove default site if exists
        sudo rm -f /etc/nginx/sites-enabled/default
        
        # Test configuration
        sudo nginx -t
        
        # Reload Nginx
        sudo systemctl reload nginx
        
        echo "Nginx configured successfully"
ENDSSH
    
    log_success "Nginx configured and reloaded"
}

#############################################
# Validation
#############################################

validate_deployment() {
    log_info "Step 8: Validating deployment..."
    
    # Check Docker service
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" bash << ENDSSH
        if systemctl is-active --quiet docker; then
            echo "✓ Docker service is running"
        else
            echo "✗ Docker service is not running"
            exit 1
        fi
        
        # Check container status
        if docker ps | grep -q "Up"; then
            echo "✓ Container is active and healthy"
            docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        else
            echo "✗ No running containers found"
            exit 1
        fi
        
        # Check Nginx
        if systemctl is-active --quiet nginx; then
            echo "✓ Nginx is running"
        else
            echo "✗ Nginx is not running"
            exit 1
        fi
        
        # Test local connectivity
        if curl -f http://localhost:${APP_PORT} &> /dev/null; then
            echo "✓ Application responding on port ${APP_PORT}"
        else
            echo "⚠ Application not responding on port ${APP_PORT}"
        fi
ENDSSH
    
    # Test remote connectivity
    log_info "Testing remote endpoint..."
    sleep 2
    
    if curl -f -s "http://${SSH_HOST}" &> /dev/null; then
        log_success "✓ Application accessible via HTTP on ${SSH_HOST}"
    else
        log_warning "⚠ Application not accessible via HTTP (may take a moment to start)"
    fi
    
    log_success "Deployment validation complete"
}

#############################################
# Cleanup Function
#############################################

cleanup_deployment() {
    log_info "Performing cleanup..."
    
    ssh -i "$SSH_KEY" "${SSH_USER}@${SSH_HOST}" bash << 'ENDSSH'
        # Remove stopped containers
        docker container prune -f
        
        # Remove unused images
        docker image prune -f
        
        # Remove unused networks
        docker network prune -f
        
        echo "Cleanup completed"
ENDSSH
    
    log_success "Cleanup completed"
}

#############################################
# Main Execution
#############################################

main() {
    echo "================================================"
    echo "  Docker Deployment Automation Script"
    echo "================================================"
    echo
    
    log_info "Deployment started at $(date)"
    
    # Step 1: Collect parameters
    collect_parameters
    
    # Step 2: Clone repository
    clone_repository
    
    # Step 3: Verify Docker files
    verify_docker_files
    
    # Step 4: Test SSH connection
    test_ssh_connection
    
    # Step 5: Setup remote server
    setup_remote_server
    
    # Step 6: Transfer files and deploy
    transfer_files
    deploy_application
    
    # Step 7: Configure Nginx
    configure_nginx
    
    # Step 8: Validate deployment
    validate_deployment
    
    # Cleanup
    cleanup_deployment
    
    echo
    echo "================================================"
    log_success "DEPLOYMENT COMPLETED SUCCESSFULLY!"
    echo "================================================"
    echo
    echo "Application Details:"
    echo "  - URL: http://${SSH_HOST}"
    echo "  - Internal Port: ${APP_PORT}"
    echo "  - Project Directory: ${PROJECT_DIR}"
    echo "  - Log File: ${LOG_FILE}"
    echo
    log_info "Deployment finished at $(date)"
}

# Run main function
main "$@"
