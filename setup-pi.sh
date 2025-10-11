#!/bin/bash

# Raspberry Pi Setup Script for Docker Deployment
# Run this script on your Raspberry Pi to prepare it for deployments

set -e

echo "Setting up Raspberry Pi for Docker deployments..."

# Update system packages
echo "📦 Updating system packages..."
sudo apt-get update && sudo apt-get upgrade -y

# Install Docker if not already installed
if ! command -v docker &> /dev/null; then
    echo "Installing Docker..."
    curl -fsSL https://get.docker.com -o get-docker.sh
    sudo sh get-docker.sh
    sudo usermod -aG docker $USER
    rm get-docker.sh
else
    echo "✅ Docker is already installed"
fi

# Install Docker Compose if not already installed
if ! command -v docker-compose &> /dev/null; then
    echo "📋 Installing Docker Compose..."
    sudo apt-get install -y docker-compose
else
    echo "✅ Docker Compose is already installed"
fi

# Create deployment directories
echo "📁 Creating deployment directories..."
mkdir -p ~/deployments
mkdir -p ~/blog-deploy
mkdir -p ~/.ssh

# Set proper permissions
chmod 700 ~/.ssh
chmod 755 ~/deployments
chmod 755 ~/blog-deploy

# Configure Docker daemon for better performance on Pi
echo "⚙️ Configuring Docker for Raspberry Pi..."
sudo tee /etc/docker/daemon.json > /dev/null <<EOF
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  },
  "storage-driver": "overlay2",
  "experimental": false,
  "default-ulimits": {
    "nofile": {
      "Name": "nofile",
      "Hard": 1024,
      "Soft": 1024
    }
  }
}
EOF

# Restart Docker service
echo "🔄 Restarting Docker service..."
sudo systemctl restart docker
sudo systemctl enable docker

# Install system monitoring tools
echo "📊 Installing monitoring tools..."
sudo apt-get install -y htop iotop

# Create a cleanup script for old deployments
echo "🧹 Creating cleanup script..."
cat > ~/cleanup-old-deployments.sh <<'EOF'
#!/bin/bash
# Cleanup script for old PR deployments

echo "🧹 Cleaning up old deployments..."

# Remove deployments older than 7 days
find ~/deployments -maxdepth 1 -type d -name "pr-*" -mtime +7 -exec rm -rf {} \;

# Clean up unused Docker resources
docker system prune -f --filter "until=168h"  # 7 days
docker volume prune -f
docker image prune -a -f --filter "until=168h"

echo "✅ Cleanup completed"
EOF

chmod +x ~/cleanup-old-deployments.sh

# Add cleanup to cron (runs daily at 2 AM)
(crontab -l 2>/dev/null; echo "0 2 * * * ~/cleanup-old-deployments.sh >> ~/cleanup.log 2>&1") | crontab -

# Display system information
echo "📊 System Information:"
echo "   OS: $(lsb_release -d | cut -f2)"
echo "   Architecture: $(uname -m)"
echo "   Memory: $(free -h | awk '/^Mem:/ {print $2}')"
echo "   Disk Space: $(df -h / | awk 'NR==2 {print $4}') available"
echo "   Docker Version: $(docker --version)"
echo "   Docker Compose Version: $(docker-compose --version)"

# Test Docker installation
echo "🧪 Testing Docker installation..."
if docker run --rm hello-world > /dev/null 2>&1; then
    echo "✅ Docker is working correctly"
else
    echo "❌ Docker test failed"
    exit 1
fi

echo ""
echo "🎉 Raspberry Pi setup completed successfully!"
echo ""
echo "Next steps:"
echo "1. Add your SSH public key to ~/.ssh/authorized_keys"
echo "2. Configure the following GitHub Secrets:"
echo "   - PI_SSH_PRIVATE_KEY: Your private SSH key"
echo "   - PI_HOST: Your Raspberry Pi's IP address or hostname"
echo "   - PI_USER: Your username (default: $USER)"
echo "   - DJANGO_SECRET_KEY: Django secret key"
echo "   - DB_NAME, DB_USER, DB_PASSWORD: Database credentials"
echo ""
echo "3. Test the deployment pipeline by creating a pull request"
echo ""
echo "⚠️  Note: Please reboot your Raspberry Pi to ensure all changes take effect:"
echo "   sudo reboot"