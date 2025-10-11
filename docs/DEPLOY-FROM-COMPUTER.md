# Deploy from Your Computer to Raspberry Pi

Yes! You can easily deploy directly from your development computer to your Raspberry Pi. Here are several ways to do it:

## Quick Start

### Option 1: Interactive Script (Recommended)
The easiest way is to use the interactive deployment script:

```bash
./deploy-to-pi.sh
```

This script will:
- Guide you through the configuration
- Test your SSH connection
- Give you deployment options (full, quick, code-only)
- Show real-time status and health checks

### Option 2: Makefile Commands
For developers who prefer command-line tools:

```bash
# Set your Pi details (replace with your actual values)
export PI_HOST=192.168.1.100
export PI_USER=pi
export PI_SSH_KEY_PATH=~/.ssh/id_rsa

# Full deployment (with backup)
make deploypi

# Quick deployment (no backup)
make deploypi-quick

# Code-only deployment (no image rebuild)
make deploypi-code

# Health check
make healthpi

# Monitor Pi status
make monitorpi

# View logs
make logspi

# Stop deployment
make stoppi-remote
```

## Setup

### 1. Configure Your Pi Connection

Create a `.env.pi` file in your project root:

```bash
cp .env.pi.example .env.pi
```

Edit `.env.pi` with your Pi details:

```bash
PI_HOST=192.168.1.100          # Your Pi's IP
PI_USER=pi                     # SSH username
PI_SSH_KEY_PATH=~/.ssh/id_rsa  # Path to SSH key
```

### 2. Ensure SSH Access

Make sure you can SSH into your Pi without a password:

```bash
# Test SSH connection
ssh pi@your-pi-ip

# If password required, copy your SSH key
ssh-copy-id pi@your-pi-ip
```

### 3. Prepare Your Raspberry Pi

Run the setup script on your Pi (one time only):

```bash
# Copy setup script to Pi
scp setup-pi.sh pi@your-pi-ip:~/

# SSH into Pi and run setup
ssh pi@your-pi-ip
chmod +x ~/setup-pi.sh
./setup-pi.sh
sudo reboot
```

## 🎮 Deployment Options

### Full Deployment
Includes backup, image build, file transfer, and service startup:
```bash
./deploy-to-pi.sh  # Option 1
# or
make deploypi
```

### Quick Deployment
Skips backup for faster deployment:
```bash
./deploy-to-pi.sh  # Option 2
# or
make deploypi-quick
```

### Code-Only Deployment
Only updates code files, doesn't rebuild Docker image:
```bash
./deploy-to-pi.sh  # Option 3
# or
make deploypi-code
```

## Monitoring & Management

### Check Deployment Health
```bash
./deploy-to-pi.sh  # Option 4
# or
make healthpi
```

### Monitor Pi Resources
```bash
./deploy-to-pi.sh  # Option 5
# or  
make monitorpi
```

### View Application Logs
```bash
./deploy-to-pi.sh  # Option 6
# or
make logspi
```

### Stop Deployment
```bash
./deploy-to-pi.sh  # Option 7
# or
make stoppi-remote
```

## Development Workflow

Here's a typical development workflow:

1. **Make changes** to your code
2. **Test locally** with `make startdocker`
3. **Deploy to Pi** with `./deploy-to-pi.sh` (option 3 for code-only)
4. **Test on Pi** and check logs if needed
5. **Repeat** as necessary

## Advanced Usage

### Environment Variables
You can override settings with environment variables:

```bash
PI_HOST=192.168.1.200 PI_USER=ubuntu make deploypi
```

### Custom SSH Keys
```bash
PI_SSH_KEY_PATH=/path/to/custom/key make deploypi
```

### Multiple Pi Environments
Create different config files:

```bash
# Development Pi
cp .env.pi .env.pi.dev
# Edit .env.pi.dev with dev Pi details

# Production Pi  
cp .env.pi .env.pi.prod
# Edit .env.pi.prod with prod Pi details

# Deploy to specific environment
ln -sf .env.pi.dev .env.pi && make deploypi
ln -sf .env.pi.prod .env.pi && make deploypi
```

## Troubleshooting

### Common Issues

**SSH Connection Failed:**
```bash
# Check if Pi is reachable
ping your-pi-ip

# Test SSH manually
ssh -i ~/.ssh/id_rsa pi@your-pi-ip

# Check SSH key permissions
chmod 600 ~/.ssh/id_rsa
```

**Docker Build Failed:**
```bash
# Check Docker buildx
docker buildx ls

# Clean and rebuild
docker system prune -f
make buildpi
```

**Deployment Stuck:**
```bash
# Check Pi resources
make monitorpi

# Restart Docker on Pi
ssh pi@your-pi-ip 'sudo systemctl restart docker'
```

**Services Not Starting:**
```bash
# Check logs
make logspi

# SSH into Pi and debug
ssh pi@your-pi-ip
cd ~/blog-deploy
docker-compose ps
docker-compose logs
```

##  What Gets Deployed

The deployment includes:
-  **Docker Image**: ARM64-compatible Django application
-  **Application Files**: All your Django code
-  **Configuration**: Docker Compose, Nginx config
-  **Database**: PostgreSQL with persistent storage
-  **Web Server**: Nginx reverse proxy
-  **Monitoring**: Health checks and logging

##  Security Notes

- Uses SSH key authentication (no passwords)
- Isolated Docker containers
- Nginx with security headers
- Rate limiting enabled
- Resource limits to prevent resource exhaustion

##  Tips

- Use **code-only deployment** for quick iterations
- Always **backup** before major changes
- **Monitor resources** on older Pi models
- **Clean up** old deployments regularly
- Use **health checks** to verify deployments

Happy deploying! 🎉