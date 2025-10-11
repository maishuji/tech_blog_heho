SSH_KEY_PATH = .private/ssh_access.pem
EC2_USER = "ubuntu"
EC2_IP ?= $(EC2_SERVER_IP)

# Raspberry Pi Configuration
# Load from .env.pi if it exists
ifneq (,$(wildcard .env.pi))
    include .env.pi
    export
endif

PI_SSH_KEY_PATH ?= .private/pi_ssh.pem
PI_USER ?= pi
PI_HOST ?= $(PI_SERVER_IP)

runlocal:
	python3 blog_heho/manage.py runserver

lint:
	pylint blog_heho/blog

startdocker: 
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml up -d

stopdocker:
	docker-compose -f docker-compose.yml -f docker-compose.dev.yml down

# Raspberry Pi targets (local operations)
startpi:
	docker-compose -f docker-compose.yml -f docker-compose.pi.yml up -d

stoppi:
	docker-compose -f docker-compose.yml -f docker-compose.pi.yml down

buildpi:
	@echo "🏗️ Building ARM64 image for Raspberry Pi..."
	docker buildx create --use --name pi-builder || true
	docker buildx build --platform linux/arm64 -f Dockerfile.prod -t blog_tech_django:pi --load .

testpi-local: buildpi
	@echo "🧪 Testing Pi deployment locally..."
	docker-compose -f docker-compose.yml -f docker-compose.pi.yml up -d
	sleep 30
	curl -f http://localhost/health/ && echo "✅ Pi deployment healthy" || echo "❌ Health check failed"
	docker-compose -f docker-compose.yml -f docker-compose.pi.yml down

# Raspberry Pi deployment targets (deploy from computer to Pi)
check-pi-config:
	@echo "🔍 Checking Pi configuration..."
	@if [ -z "$(PI_HOST)" ]; then echo "❌ PI_HOST not set. Use: make deploypi PI_HOST=your-pi-ip"; exit 1; fi
	@if [ ! -f "$(PI_SSH_KEY_PATH)" ]; then echo "❌ SSH key not found at $(PI_SSH_KEY_PATH)"; exit 1; fi
	@echo "✅ Configuration OK"
	@echo "   Host: $(PI_HOST)"
	@echo "   User: $(PI_USER)"
	@echo "   SSH Key: $(PI_SSH_KEY_PATH)"

prepare-pi: check-pi-config
	@echo "📦 Preparing Raspberry Pi for deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		mkdir -p ~/blog-deploy && \
		mkdir -p ~/blog-deploy/backups && \
		echo "✅ Directories created"'

backup-pi: check-pi-config
	@echo "💾 Creating backup of current deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		mkdir -p ~/blog-deploy/backups && \
		cd ~/blog-deploy && \
		if [ -f docker-compose.yml ]; then \
			BACKUP_NAME="backup-$(shell date +%Y%m%d-%H%M%S)" && \
			mkdir -p backups/$$BACKUP_NAME && \
			docker-compose -f docker-compose.yml -f docker-compose.pi.yml down && \
			cp -r * backups/$$BACKUP_NAME/ 2>/dev/null || true && \
			echo "✅ Backup created: $$BACKUP_NAME"; \
		else \
			echo "ℹ️ No existing deployment to backup (first-time deployment)"; \
		fi'

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

deploy-image: buildpi check-pi-config
	@echo "🚀 Deploying Docker image to Raspberry Pi..."
	@echo "   This may take a few minutes..."
	docker save blog_tech_django:pi | gzip | ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		echo "📥 Loading Docker image..." && \
		docker load && \
		echo "✅ Image loaded successfully"'

deploy-start: check-pi-config
	@echo "🎬 Starting services on Raspberry Pi..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		echo "🛑 Stopping existing services..." && \
		docker-compose -f docker-compose.yml -f docker-compose.pi.yml down --remove-orphans || true && \
		echo "� Setting up environment..." && \
		cp .env.pi.deploy .env || echo "No .env.pi.deploy found, using defaults" && \
		echo "🚀 Starting new deployment..." && \
		docker-compose -f docker-compose.yml -f docker-compose.pi.yml --env-file .env up -d && \
		echo "⏳ Waiting for services to start..." && \
		sleep 30 && \
		echo "📊 Service status:" && \
		docker-compose -f docker-compose.yml -f docker-compose.pi.yml ps'

deploypi: backup-pi deploy-files deploy-image deploy-start
	@echo "🎉 Full deployment completed!"
	@echo "🔗 Access your app at: http://$(PI_HOST)"
	@ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		NGINX_PORT=$$(docker-compose port nginx 80 | cut -d: -f2) && \
		echo "🌐 Full URL: http://$(PI_HOST):$$NGINX_PORT"'

# Quick deploy (skip backup for faster deployment)
deploypi-quick: deploy-files deploy-image deploy-start
	@echo "⚡ Quick deployment completed!"

# Deploy only code changes (no image rebuild)
deploypi-code: deploy-files deploy-start
	@echo "📝 Code deployment completed!"

# Health check on Pi
healthpi: check-pi-config
	@echo "🏥 Checking Pi deployment health..."
	@ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		if docker-compose --env-file .env ps | grep -q "Up"; then \
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

# Stop Pi deployment
stoppi-remote: check-pi-config
	@echo "🛑 Stopping Pi deployment..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker-compose -f docker-compose.yml -f docker-compose.pi.yml down && \
		echo "✅ Services stopped"'

# View Pi logs
logspi: check-pi-config
	@echo "📋 Fetching Pi deployment logs..."
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST) '\
		cd ~/blog-deploy && \
		docker-compose -f docker-compose.yml -f docker-compose.pi.yml logs --tail=50'

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
		cd ~/blog-deploy && docker-compose ps'

ssh:
	ssh -i "$(SSH_KEY_PATH)" $(EC2_USER)@$(EC2_IP)

sshpi:
	ssh -i "$(PI_SSH_KEY_PATH)" $(PI_USER)@$(PI_HOST)