SSH_KEY_PATH = .private/ssh_access.pem
EC2_USER = "ubuntu"
EC2_IP ?= $(EC2_SERVER_IP)

# Environment Configuration
# Load .env file if it exists (for local development and Pi connection settings)
ifneq (,$(wildcard .env))
    include .env
    export
endif

# Raspberry Pi Configuration
# Load from .env.pi if it exists (alternative Pi-specific config)
ifneq (,$(wildcard .env.pi))
    include .env.pi
    export
endif

# Strip whitespace from environment variables to avoid issues
PI_SSH_KEY_PATH := $(strip $(PI_SSH_KEY_PATH))
PI_USER := $(strip $(PI_USER))
PI_HOST := $(strip $(PI_HOST))

# Set defaults if not provided
PI_SSH_KEY_PATH ?= .private/pi_ssh.pem
PI_USER ?= pi
PI_HOST ?= $(PI_SERVER_IP)

## Local Development Targets ##

# Run Django development server locally (without Docker)
runlocal:
	python3 blog_heho/manage.py runserver

# Run pylint to check code quality in the blog app
lint:
	pylint blog_heho/blog

## Local Docker Development Targets ##

# Start local development environment using Docker Compose
startdocker: 
	docker compose -f docker-compose.yml -f docker-compose.dev.yml up -d

# Stop local Docker development environment
stopdocker:
	docker compose -f docker-compose.yml -f docker-compose.dev.yml down

## Raspberry Pi Targets (Local Operations) ##

# Start Pi configuration locally (for testing Pi setup on your machine)
# Raspberry Pi targets (local operations)
startpi:
	docker compose -f docker-compose.yml -f docker-compose.pi.yml up -d

# Stop local Pi configuration
stoppi:
	docker compose -f docker-compose.yml -f docker-compose.pi.yml down

# Build ARM64 Docker image for Raspberry Pi using buildx
buildpi:
	@echo "🏗️ Building ARM64 image for Raspberry Pi..."
	docker buildx create --use --name pi-builder || true
	docker buildx build --platform linux/arm64 -f Dockerfile.prod -t blog_tech_django:pi --load .

# Build and test Pi deployment locally before deploying to actual Pi
testpi-local: buildpi
	@echo "🧪 Testing Pi deployment locally..."
	docker compose -f docker-compose.yml -f docker-compose.pi.yml up -d
	sleep 30
	curl -f http://localhost/health/ && echo "✅ Pi deployment healthy" || echo "❌ Health check failed"
	docker compose -f docker-compose.yml -f docker-compose.pi.yml down

## Raspberry Pi Remote Deployment Targets ##

# Verify Pi configuration (SSH key, host, user) before deployment
# Raspberry Pi deployment targets (deploy from computer to Pi)
check-pi-config:
	@echo "🔍 Checking Pi configuration..."
	@if [ -z "$(PI_HOST)" ]; then echo "❌ PI_HOST not set. Use: make deploypi PI_HOST=your-pi-ip"; exit 1; fi
	@SSH_KEY_EXPANDED=$$(echo "$(PI_SSH_KEY_PATH)" | sed "s|^~|$$HOME|"); \
	if [ ! -f "$$SSH_KEY_EXPANDED" ]; then echo "❌ SSH key not found at $$SSH_KEY_EXPANDED"; exit 1; fi
	@echo "✅ Configuration OK"
	@echo "   Host: $(PI_HOST)"
	@echo "   User: $(PI_USER)"
	@echo "   SSH Key: $(PI_SSH_KEY_PATH)"

# Create necessary directories on Pi for deployment
prepare-pi: check-pi-config
	@echo "📦 Preparing Raspberry Pi for deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		mkdir -p ~/blog-deploy && \
		mkdir -p ~/blog-deploy/backups && \
		echo "✅ Directories created"'

# Create timestamped backup of current Pi deployment before updating
backup-pi: check-pi-config
	@echo "💾 Creating backup of current deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		mkdir -p ~/blog-deploy/backups && \
		cd ~/blog-deploy && \
		if [ -f docker-compose.yml ]; then \
			BACKUP_NAME="backup-$(shell date +%Y%m%d-%H%M%S)" && \
			mkdir -p backups/$$BACKUP_NAME && \
			docker compose -f docker-compose.yml -f docker-compose.pi.yml down && \
			cp -r * backups/$$BACKUP_NAME/ 2>/dev/null || true && \
			echo "✅ Backup created: $$BACKUP_NAME"; \
		else \
			echo "ℹ️ No existing deployment to backup (first-time deployment)"; \
		fi'

# Upload source files and configurations to Pi (Django code, templates, configs, env files)
# Use when: Code changes, config updates, or env variable changes (no image rebuild needed)
# Deploy source files and configurations to Pi
# This uploads Django code, templates, docker compose configs, nginx config, and environment files
# Use this when: You've made code changes, updated configs, or changed environment variables
# Fast: Only transfers text files, no Docker image rebuild required
deploy-files: check-pi-config prepare-pi
	@echo "📤 Uploading files to Raspberry Pi..."
	scp -r -i "$(PI_SSH_KEY_PATH)" \
		blog_heho \
		docker-compose.yml \
		docker-compose.pi.yml \
		nginx.pi.conf \
		Dockerfile.prod \
		requirements.prod.txt \
		wait-for-it.sh \
		.env.pi.deploy \
		$(PI_USER)@$(PI_HOST):~/blog-deploy/
	@echo "✅ Files uploaded successfully"

# Build ARM64 image and transfer it to Pi (use when dependencies or Dockerfile changed)
deploy-image: buildpi check-pi-config
	@echo "🚀 Deploying Docker image to Raspberry Pi..."
	@echo "   This may take a few minutes..."
	docker save blog_tech_django:pi | gzip | ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		echo "📥 Loading Docker image..." && \
		docker load && \
		echo "✅ Image loaded successfully"'

# Start/restart services on Pi using uploaded files and images
deploy-start: check-pi-config
	@echo "🎬 Starting services on Raspberry Pi..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		echo "🛑 Stopping existing services..." && \
		docker compose -f docker-compose.yml -f docker-compose.pi.yml down --remove-orphans || true && \
		echo "🔧 Setting up environment..." && \
		cp .env.pi.deploy .env || echo "No .env.pi.deploy found, using defaults" && \
		echo "🚀 Starting new deployment..." && \
		docker compose -f docker-compose.yml -f docker-compose.pi.yml --env-file .env up -d && \
		echo "⏳ Waiting for services to start..." && \
		sleep 30 && \
		echo "📊 Service status:" && \
		docker compose -f docker-compose.yml -f docker-compose.pi.yml ps'

# Full deployment: backup, upload files, build/transfer image, and start services
deploypi: backup-pi deploy-files deploy-image deploy-start
	@echo "🎉 Full deployment completed!"
	@echo "🔗 Access your app at: http://$(PI_HOST)"
	@ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		NGINX_PORT=$$(docker compose port nginx 80 | cut -d: -f2) && \
		echo "🌐 Full URL: http://$(PI_HOST):$$NGINX_PORT"'

# Quick deployment without backup (faster, but riskier - use for testing)
# Quick deploy (skip backup for faster deployment)
deploypi-quick: deploy-files deploy-image deploy-start
	@echo "⚡ Quick deployment completed!"

# Deploy only code/config changes without rebuilding Docker image (fastest)
# Deploy only code changes (no image rebuild)
deploypi-code: deploy-files deploy-start
	@echo "📝 Code deployment completed!"

## Raspberry Pi Management Targets ##

# Check if Pi deployment is running and healthy
# Health check on Pi
healthpi: check-pi-config
	@echo "🏥 Checking Pi deployment health..."
	@ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		if docker compose --env-file .env ps | grep -q "Up"; then \
			echo "✅ Services are running" && \
			if curl -f http://localhost/health/ >/dev/null 2>&1; then \
				echo "✅ Health check passed - Application is healthy"; \
			elif curl -f http://localhost/ >/dev/null 2>&1; then \
				echo "✅ Application is responding (health endpoint may not exist)"; \
			else \
				echo "❌ Application is not responding"; \
			fi; \
		else \
			echo "❌ Services are not running"; \
		fi'

# Stop all services on Pi remotely
# Stop Pi deployment
stoppi-remote: check-pi-config
	@echo "🛑 Stopping Pi deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker compose -f docker-compose.yml -f docker-compose.pi.yml down && \
		echo "✅ Services stopped"'

# View last 50 lines of logs from Pi deployment
# View Pi logs
logspi: check-pi-config
	@echo "📋 Fetching Pi deployment logs..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker compose -f docker-compose.yml -f docker-compose.pi.yml logs --tail=50'

# Monitor Pi system resources (memory, disk, Docker usage, running containers)
# Monitor Pi resources
monitorpi: check-pi-config
	@echo "📊 Pi system status:"
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		echo "Memory Usage:" && free -h && \
		echo "" && \
		echo "Disk Usage:" && df -h / && \
		echo "" && \
		echo "Docker Usage:" && docker system df && \
		echo "" && \
		echo "Running Containers:" && \
		cd ~/blog-deploy && docker compose ps'

## Blog Content Management Targets ##

# Import articles from GitHub repository to Pi
import-articles-pi: check-pi-config
	@echo "📚 Importing articles from GitHub repository..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker exec blog_pi-django-1 python blog_heho/manage.py import_articles'

# Import articles with update flag (overwrites existing)
import-articles-pi-update: check-pi-config
	@echo "📚 Importing/updating articles from GitHub repository..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker exec blog_pi-django-1 python blog_heho/manage.py import_articles --update'

# Create Django superuser on Pi
createsuper-pi: check-pi-config
	@echo "👤 Creating Django superuser on Pi..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker exec -it blog_pi-django-1 python blog_heho/manage.py createsuperuser'

## SSH Access Targets ##

# SSH into EC2 server
ssh:
	ssh -i "$(SSH_KEY_PATH)" $(EC2_USER)@$(EC2_IP)

# SSH into Raspberry Pi
sshpi:
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST)