#!/bin/bash

# Compound Community Backend Deployment Script
# This script helps deploy the backend with Docker Compose and Caddy

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if Docker is installed
check_docker() {
    if ! command -v docker &> /dev/null; then
        log_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command -v docker-compose &> /dev/null; then
        log_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    log_success "Docker and Docker Compose are installed"
}

# Check if .env file exists
check_env() {
    if [ ! -f ".env" ]; then
        log_error ".env file not found. Please ensure your .env file exists in the backend directory."
        log_info "The .env file should contain your blockchain, OpenAI, and AgentKit configuration."
        if [ -f "env.example" ]; then
            log_info "You can reference env.example for the required format."
        fi
        exit 1
    fi
    
    log_success ".env file exists"
}

# Validate environment variables
validate_env() {
    log_info "Validating environment variables..."
    
    required_vars=("ETHEREUM_RPC_URL" "PRIVATE_KEY" "OPENAI_API_KEY" "NETWORK_ID")
    missing_vars=()
    
    for var in "${required_vars[@]}"; do
        if grep -q "^${var}=your_" .env || ! grep -q "^${var}=" .env; then
            missing_vars+=("$var")
        fi
    done
    
    if [ ${#missing_vars[@]} -ne 0 ]; then
        log_error "Missing or incomplete environment variables:"
        for var in "${missing_vars[@]}"; do
            echo "  - $var"
        done
        log_error "Please update your .env file with actual values"
        exit 1
    fi
    
    log_success "Environment variables validated"
}

# Create required volumes
create_volumes() {
    log_info "Creating Docker volumes..."
    
    if ! docker volume ls | grep -q "caddy_data"; then
        docker volume create caddy_data
        log_success "Created caddy_data volume"
    else
        log_info "caddy_data volume already exists"
    fi
}

# Build and start services
deploy() {
    log_info "Building and starting services..."
    
    # Pull latest images
    log_info "Pulling latest images..."
    docker-compose pull
    
    # Build backend
    log_info "Building backend service..."
    docker-compose build --no-cache backend
    
    # Start services
    log_info "Starting services..."
    docker-compose up -d
    
    log_success "Services started successfully"
}

# Check service health
check_health() {
    log_info "Checking service health..."
    
    # Wait for services to start
    sleep 10
    
    # Check if containers are running
    if docker-compose ps | grep -q "Up"; then
        log_success "Containers are running"
    else
        log_error "Some containers are not running properly"
        docker-compose ps
        return 1
    fi
    
    # Check backend health (might take a moment to start)
    log_info "Waiting for backend to be ready..."
    for i in {1..30}; do
        if curl -f -s http://localhost:8000/healthy > /dev/null 2>&1; then
            log_success "Backend is responding on port 8000"
            break
        fi
        if [ $i -eq 30 ]; then
            log_error "Backend is not responding after 30 attempts"
            return 1
        fi
        sleep 2
    done
}

# Show logs
show_logs() {
    log_info "Showing service logs..."
    docker-compose logs --tail=50
}

# Show status
show_status() {
    log_info "Service status:"
    docker-compose ps
    
    echo ""
    log_info "Service URLs:"
    echo "  - WebSocket: wss://api.compcomm.club/ws/chat"
    echo "  - Health Check: https://api.compcomm.club/healthy"
    
    echo ""
    log_info "Useful commands:"
    echo "  - View logs: docker-compose logs -f"
    echo "  - Restart: docker-compose restart"
    echo "  - Stop: docker-compose down"
    echo "  - Update: ./deploy.sh update"
}

# Update deployment
update() {
    log_info "Updating deployment..."
    
    # Pull latest code (if using git)
    if [ -d ".git" ]; then
        log_info "Pulling latest code..."
        git pull
    fi
    
    # Rebuild and restart
    docker-compose build --no-cache
    docker-compose up -d --force-recreate
    
    log_success "Update completed"
}

# Backup function
backup() {
    log_info "Creating backup..."
    
    backup_dir="backups/$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir"
    
    # Backup environment file
    cp .env "$backup_dir/env.backup"
    
    # Backup logs
    docker-compose logs --no-color > "$backup_dir/logs.txt"
    
    # Backup Caddy certificates
    docker run --rm -v caddy_data:/data -v $(pwd)/$backup_dir:/backup alpine tar czf /backup/caddy-certs.tar.gz -C /data .
    
    log_success "Backup created in $backup_dir"
}

# Main script
main() {
    log_info "Compound Community Backend Deployment Script"
    echo ""
    
    case "${1:-deploy}" in
        "deploy")
            check_docker
            check_env
            validate_env
            create_volumes
            deploy
            check_health
            show_status
            ;;
        "update")
            check_docker
            update
            check_health
            show_status
            ;;
        "status")
            show_status
            ;;
        "logs")
            show_logs
            ;;
        "backup")
            backup
            ;;
        "stop")
            log_info "Stopping services..."
            docker-compose down
            log_success "Services stopped"
            ;;
        "restart")
            log_info "Restarting services..."
            docker-compose restart
            check_health
            show_status
            ;;
        "help"|"-h"|"--help")
            echo "Usage: $0 [command]"
            echo ""
            echo "Commands:"
            echo "  deploy   - Deploy the application (default)"
            echo "  update   - Update and restart the application"
            echo "  status   - Show service status and URLs"
            echo "  logs     - Show service logs"
            echo "  backup   - Create a backup"
            echo "  stop     - Stop all services"
            echo "  restart  - Restart all services"
            echo "  help     - Show this help message"
            ;;
        *)
            log_error "Unknown command: $1"
            echo "Use '$0 help' for usage information"
            exit 1
            ;;
    esac
}

# Run main function
main "$@"
