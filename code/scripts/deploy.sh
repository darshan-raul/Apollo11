#!/bin/bash

# Apollo 11 Astronaut Onboarding Deployment Script
# This script helps deploy the application using Docker Compose or Kubernetes

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check prerequisites
check_prerequisites() {
    print_status "Checking prerequisites..."
    
    if ! command_exists docker; then
        print_error "Docker is not installed. Please install Docker first."
        exit 1
    fi
    
    if ! command_exists docker-compose; then
        print_error "Docker Compose is not installed. Please install Docker Compose first."
        exit 1
    fi
    
    # Check for uv (optional for local development)
    if ! command_exists uv; then
        print_warning "uv is not installed. Consider installing it for faster Python package management:"
        print_warning "curl -LsSf https://astral.sh/uv/install.sh | sh"
    else
        print_success "uv package manager found"
    fi
    
    print_success "Prerequisites check passed"
}

# Function to build Docker images
build_images() {
    print_status "Building Docker images..."
    
    # Build frontend
    print_status "Building frontend image..."
    docker build -t apollo11-frontend ./frontend
    
    # Build core-api
    print_status "Building core-api image..."
    docker build -t apollo11-core-api ./core-api
    
    # Build simulator
    print_status "Building simulator image..."
    docker build -t apollo11-simulator ./simulator
    
    # Build admin-dashboard
    print_status "Building admin-dashboard image..."
    docker build -t apollo11-admin-dashboard ./admin-dashboard
    
    print_success "All images built successfully"
}

# Function to deploy with Docker Compose
deploy_docker_compose() {
    print_status "Deploying with Docker Compose..."
    
    # Stop existing containers
    print_status "Stopping existing containers..."
    docker-compose down
    
    # Start services
    print_status "Starting services..."
    docker-compose up -d
    
    # Wait for services to be ready
    print_status "Waiting for services to be ready..."
    sleep 30
    
    # Check service health
    check_services_health
    
    print_success "Docker Compose deployment completed"
    print_status "Access the application at:"
    print_status "  Frontend: http://localhost:8000"
    print_status "  Admin Dashboard: http://localhost:8501"
    print_status "  Core API Health: http://localhost:8080/health"
}

# Function to check services health
check_services_health() {
    print_status "Checking services health..."
    
    # Check Core API
    if curl -f http://localhost:8080/health >/dev/null 2>&1; then
        print_success "Core API is healthy"
    else
        print_warning "Core API health check failed"
    fi
    
    # Check Frontend
    if curl -f http://localhost:8000/ >/dev/null 2>&1; then
        print_success "Frontend is healthy"
    else
        print_warning "Frontend health check failed"
    fi
    
    # Check Admin Dashboard
    if curl -f http://localhost:8501/ >/dev/null 2>&1; then
        print_success "Admin Dashboard is healthy"
    else
        print_warning "Admin Dashboard health check failed"
    fi
}

# Function to deploy with Kubernetes
deploy_kubernetes() {
    print_status "Deploying with Kubernetes..."
    
    if ! command_exists kubectl; then
        print_error "kubectl is not installed. Please install kubectl first."
        exit 1
    fi
    
    # Apply Kubernetes manifests
    print_status "Applying Kubernetes manifests..."
    kubectl apply -k ./k8s
    
    # Wait for deployments to be ready
    print_status "Waiting for deployments to be ready..."
    kubectl wait --for=condition=available --timeout=300s deployment/core-api -n apollo11
    kubectl wait --for=condition=available --timeout=300s deployment/frontend -n apollo11
    kubectl wait --for=condition=available --timeout=300s deployment/admin-dashboard -n apollo11
    
    print_success "Kubernetes deployment completed"
    print_status "To access the application, use port-forwarding:"
    print_status "  kubectl port-forward -n apollo11 service/frontend 8000:8000"
    print_status "  kubectl port-forward -n apollo11 service/admin-dashboard 8501:8501"
}

# Function to show logs
show_logs() {
    local service=$1
    
    if [ -z "$service" ]; then
        print_status "Showing logs for all services..."
        docker-compose logs -f
    else
        print_status "Showing logs for $service..."
        docker-compose logs -f "$service"
    fi
}

# Function to stop services
stop_services() {
    print_status "Stopping services..."
    
    if [ "$DEPLOYMENT_TYPE" = "k8s" ]; then
        kubectl delete -k ./k8s
        print_success "Kubernetes services stopped"
    else
        docker-compose down
        print_success "Docker Compose services stopped"
    fi
}

# Function to set up development environment
setup_dev_environment() {
    print_status "Setting up local development environment with uv..."
    
    if ! command_exists uv; then
        print_error "uv is not installed. Please install it first:"
        print_error "curl -LsSf https://astral.sh/uv/install.sh | sh"
        exit 1
    fi
    
    # Set up each Python service
    services=("frontend" "simulator" "admin-dashboard" "shared")
    
    for service in "${services[@]}"; do
        if [ -d "$service" ]; then
            print_status "Setting up $service..."
            cd "$service"
            
            # Install dependencies
            uv sync --dev
            
            # Generate lock file
            uv lock
            
            print_success "$service setup completed"
            cd ..
        else
            print_warning "Service directory $service not found"
        fi
    done
    
    print_success "Development environment setup completed"
    print_status "To run individual services:"
    print_status "  cd frontend && uv run python main.py"
    print_status "  cd simulator && uv run python main.py"
    print_status "  cd admin-dashboard && uv run streamlit run main.py"
}

# Function to show help
show_help() {
    echo "Apollo 11 Astronaut Onboarding Deployment Script"
    echo ""
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo ""
    echo "Commands:"
    echo "  build                 Build Docker images"
    echo "  deploy                Deploy the application (default: docker-compose)"
    echo "  deploy-docker         Deploy using Docker Compose"
    echo "  deploy-k8s            Deploy using Kubernetes"
    echo "  logs [service]        Show logs (all services or specific service)"
    echo "  stop                  Stop all services"
    echo "  health                Check services health"
    echo "  dev-setup             Set up local development environment with uv"
    echo "  help                  Show this help message"
    echo ""
    echo "Options:"
    echo "  --no-build            Skip building images (for deploy commands)"
    echo ""
    echo "Examples:"
    echo "  $0 build                    # Build all Docker images"
    echo "  $0 deploy                   # Deploy with Docker Compose"
    echo "  $0 deploy-k8s               # Deploy with Kubernetes"
    echo "  $0 logs frontend            # Show frontend logs"
    echo "  $0 stop                     # Stop all services"
    echo "  $0 dev-setup                # Set up local development with uv"
    echo ""
    echo "Local Development with uv:"
    echo "  Install uv: curl -LsSf https://astral.sh/uv/install.sh | sh"
    echo "  cd frontend && uv sync --dev"
    echo "  uv run python main.py"
}

# Main script logic
main() {
    local command=${1:-deploy}
    local skip_build=false
    
    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case $1 in
            --no-build)
                skip_build=true
                shift
                ;;
            *)
                command=$1
                shift
                ;;
        esac
    done
    
    case $command in
        build)
            check_prerequisites
            build_images
            ;;
        deploy|deploy-docker)
            check_prerequisites
            if [ "$skip_build" = false ]; then
                build_images
            fi
            deploy_docker_compose
            ;;
        deploy-k8s)
            check_prerequisites
            if [ "$skip_build" = false ]; then
                build_images
            fi
            deploy_kubernetes
            ;;
        logs)
            show_logs "$2"
            ;;
        stop)
            stop_services
            ;;
        health)
            check_services_health
            ;;
        dev-setup)
            setup_dev_environment
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Unknown command: $command"
            show_help
            exit 1
            ;;
    esac
}

# Run main function with all arguments
main "$@"
