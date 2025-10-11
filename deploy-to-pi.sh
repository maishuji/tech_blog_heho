#!/bin/bash

# Interactive Raspberry Pi Deployment Script
# Deploy your Django blog to Raspberry Pi from your computer

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DEFAULT_PI_USER="pi"
DEFAULT_SSH_KEY="~/.ssh/id_rsa"
DEPLOYMENT_DIR="~/blog-deploy"

# Helper functions
print_header() {
    echo -e "${BLUE}
╔══════════════════════════════════════════════════════════════╗
║                   Raspberry Pi Deployment Tool               ║
╚══════════════════════════════════════════════════════════════╝${NC}"
}

print_step() {
    echo -e "${YELLOW}▶ $1${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
    exit 1
}

print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# Get user input
get_pi_config() {
    echo -e "${BLUE}Please provide your Raspberry Pi connection details:${NC}"
    echo ""
    
    read -p "Raspberry Pi IP/hostname: " PI_HOST
    if [[ -z "$PI_HOST" ]]; then
        print_error "Pi hostname/IP is required"
    fi
    
    read -p "SSH username [$DEFAULT_PI_USER]: " PI_USER
    PI_USER=${PI_USER:-$DEFAULT_PI_USER}
    
    read -p "SSH key path [$DEFAULT_SSH_KEY]: " SSH_KEY
    SSH_KEY=${SSH_KEY:-$DEFAULT_SSH_KEY}
    SSH_KEY=$(eval echo $SSH_KEY)  # Expand ~ to home directory
    
    if [[ ! -f "$SSH_KEY" ]]; then
        print_error "SSH key not found at $SSH_KEY"
    fi
    
    echo ""
    echo -e "${GREEN}Configuration:${NC}"
    echo "  Host: $PI_HOST"
    echo "  User: $PI_USER"
    echo "  SSH Key: $SSH_KEY"
    echo ""
}

# Test SSH connection
test_ssh_connection() {
    print_step "Testing SSH connection to $PI_HOST..."
    
    if ssh -i "$SSH_KEY" -o ConnectTimeout=10 -o BatchMode=yes "$PI_USER@$PI_HOST" 'echo "SSH connection successful"' >/dev/null 2>&1; then
        print_success "SSH connection successful"
    else
        print_error "Cannot connect to $PI_HOST. Please check your configuration."
    fi
}

# Check Pi requirements
check_pi_requirements() {
    print_step "Checking Raspberry Pi requirements..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" '
        # Check if Docker is installed
        if ! command -v docker &> /dev/null; then
            echo "ERROR: Docker is not installed"
            exit 1
        fi
        
        # Check if Docker Compose is installed
        if ! command -v docker-compose &> /dev/null; then
            echo "ERROR: Docker Compose is not installed"
            exit 1
        fi
        
        # Check Docker daemon
        if ! docker info &> /dev/null; then
            echo "ERROR: Docker daemon is not running"
            exit 1
        fi
        
        echo "✅ All requirements met"
        echo "Docker version: $(docker --version)"
        echo "Docker Compose version: $(docker-compose --version)"
    '
    
    if [[ $? -eq 0 ]]; then
        print_success "Pi requirements check passed"
    else
        print_error "Pi requirements check failed. Run setup-pi.sh on your Pi first."
    fi
}

# Show deployment menu
show_deployment_menu() {
    echo -e "${BLUE}Choose deployment type:${NC}"
    echo ""
    echo "1. 🚀 Full deployment (backup + build + deploy)"
    echo "2. ⚡ Quick deployment (no backup)"
    echo "3. 📝 Code-only deployment (no image rebuild)"
    echo "4. 🏥 Health check only"
    echo "5. 📊 Monitor Pi status"
    echo "6. 📋 View logs"
    echo "7. 🛑 Stop deployment"
    echo "8. 💾 Backup current deployment"
    echo "9. 🧹 Cleanup old resources"
    echo "0. ❌ Exit"
    echo ""
}

# Build Docker image for ARM
build_arm_image() {
    print_step "Building ARM64 Docker image..."
    
    # Setup buildx if not exists
    docker buildx create --use --name pi-builder 2>/dev/null || true
    
    # Build the image
    if docker buildx build --platform linux/arm64 -f Dockerfile.prod -t blog_tech_django:pi --load .; then
        print_success "ARM64 image built successfully"
    else
        print_error "Failed to build ARM64 image"
    fi
}

# Deploy files to Pi
deploy_files() {
    print_step "Uploading files to Raspberry Pi..."
    
    # Create deployment directory
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "mkdir -p $DEPLOYMENT_DIR"
    
    # Upload files
    if scp -i "$SSH_KEY" -r \
        blog_heho \
        docker-compose.yml \
        docker-compose.pi.yml \
        nginx.pi.conf \
        Dockerfile.prod \
        requirements.prod.txt \
        wait-for-it.sh \
        "$PI_USER@$PI_HOST:$DEPLOYMENT_DIR/"; then
        print_success "Files uploaded successfully"
    else
        print_error "Failed to upload files"
    fi
}

# Deploy Docker image
deploy_image() {
    print_step "Transferring Docker image to Pi (this may take a few minutes)..."
    
    if docker save blog_tech_django:pi | gzip | ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR && 
        echo 'Loading Docker image...' && 
        docker load
    "; then
        print_success "Docker image transferred successfully"
    else
        print_error "Failed to transfer Docker image"
    fi
}

# Start services on Pi
start_services() {
    print_step "Starting services on Raspberry Pi..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR
        echo 'Stopping existing services...'
        docker-compose -f docker-compose.yml -f docker-compose.pi.yml down --remove-orphans || true
        echo 'Starting new deployment...'
        docker-compose -f docker-compose.yml -f docker-compose.pi.yml up -d
        echo 'Waiting for services to start...'
        sleep 30
    "
    
    if [[ $? -eq 0 ]]; then
        print_success "Services started successfully"
        
        # Get the URL
        URL=$(ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
            cd $DEPLOYMENT_DIR
            NGINX_PORT=\$(docker-compose port nginx 80 2>/dev/null | cut -d: -f2)
            if [[ ! -z \"\$NGINX_PORT\" ]]; then
                echo \"http://$PI_HOST:\$NGINX_PORT\"
            else
                echo \"http://$PI_HOST:80\"
            fi
        ")
        
        echo ""
        print_success "🎉 Deployment completed!"
        echo -e "${GREEN}🔗 Access your app at: $URL${NC}"
        echo ""
    else
        print_error "Failed to start services"
    fi
}

# Backup current deployment
backup_deployment() {
    print_step "Creating backup of current deployment..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR
        if [[ -f docker-compose.yml ]]; then
            BACKUP_NAME=\"backup-\$(date +%Y%m%d-%H%M%S)\"
            mkdir -p backups/\$BACKUP_NAME
            docker-compose -f docker-compose.yml -f docker-compose.pi.yml down || true
            cp -r * backups/\$BACKUP_NAME/ 2>/dev/null || true
            echo \"Backup created: \$BACKUP_NAME\"
        else
            echo \"No existing deployment to backup\"
        fi
    "
    
    print_success "Backup completed"
}

# Health check
health_check() {
    print_step "Performing health check..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR
        if docker-compose ps | grep -q 'Up'; then
            NGINX_PORT=\$(docker-compose port nginx 80 2>/dev/null | cut -d: -f2)
            if [[ ! -z \"\$NGINX_PORT\" ]]; then
                if curl -f -s http://localhost:\$NGINX_PORT/health/ >/dev/null; then
                    echo '✅ Deployment is healthy'
                    echo \"🔗 URL: http://$PI_HOST:\$NGINX_PORT\"
                else
                    echo '❌ Health check failed'
                    exit 1
                fi
            else
                echo '⚠️ Nginx port not found'
                exit 1
            fi
        else
            echo '❌ Services are not running'
            exit 1
        fi
    "
    
    if [[ $? -eq 0 ]]; then
        print_success "Health check passed"
    else
        print_error "Health check failed"
    fi
}

# Monitor Pi status
monitor_status() {
    print_step "Fetching Pi status..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        echo '📊 System Status:'
        echo '================'
        echo ''
        echo '💾 Memory Usage:'
        free -h
        echo ''
        echo '💿 Disk Usage:'
        df -h /
        echo ''
        echo '🐳 Docker Usage:'
        docker system df
        echo ''
        echo '📦 Running Containers:'
        cd $DEPLOYMENT_DIR 2>/dev/null && docker-compose ps || echo 'No deployment found'
    "
}

# View logs
view_logs() {
    print_step "Fetching deployment logs..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR
        if [[ -f docker-compose.yml ]]; then
            docker-compose -f docker-compose.yml -f docker-compose.pi.yml logs --tail=50
        else
            echo 'No deployment found'
        fi
    "
}

# Stop deployment
stop_deployment() {
    print_step "Stopping deployment..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        cd $DEPLOYMENT_DIR
        docker-compose -f docker-compose.yml -f docker-compose.pi.yml down --remove-orphans
    "
    
    print_success "Deployment stopped"
}

# Cleanup resources
cleanup_resources() {
    print_step "Cleaning up old resources..."
    
    ssh -i "$SSH_KEY" "$PI_USER@$PI_HOST" "
        echo 'Removing unused Docker resources...'
        docker system prune -f
        docker volume prune -f
        echo 'Cleaning up old backups (keeping last 5)...'
        cd $DEPLOYMENT_DIR/backups 2>/dev/null && ls -t | tail -n +6 | xargs rm -rf || true
    "
    
    print_success "Cleanup completed"
}

# Main deployment function
perform_deployment() {
    case $1 in
        1)
            backup_deployment
            build_arm_image
            deploy_files
            deploy_image
            start_services
            health_check
            ;;
        2)
            build_arm_image
            deploy_files
            deploy_image
            start_services
            health_check
            ;;
        3)
            deploy_files
            start_services
            health_check
            ;;
        4)
            health_check
            ;;
        5)
            monitor_status
            ;;
        6)
            view_logs
            ;;
        7)
            stop_deployment
            ;;
        8)
            backup_deployment
            ;;
        9)
            cleanup_resources
            ;;
        0)
            echo "Goodbye!"
            exit 0
            ;;
        *)
            print_error "Invalid option"
            ;;
    esac
}

# Main script
main() {
    print_header
    
    # Check if we're in the right directory
    if [[ ! -f "docker-compose.pi.yml" ]]; then
        print_error "docker-compose.pi.yml not found. Please run this script from the project root."
    fi
    
    # Check local Docker
    if ! command -v docker &> /dev/null; then
        print_error "Docker is not installed on your computer"
    fi
    
    # Get Pi configuration
    get_pi_config
    
    # Test connection
    test_ssh_connection
    
    # Check Pi requirements
    check_pi_requirements
    
    # Main loop
    while true; do
        echo ""
        show_deployment_menu
        read -p "Select option [1-9, 0]: " choice
        echo ""
        
        perform_deployment "$choice"
        
        if [[ "$choice" != "0" ]]; then
            echo ""
            read -p "Press Enter to continue..."
        fi
    done
}

# Run the script
main "$@"