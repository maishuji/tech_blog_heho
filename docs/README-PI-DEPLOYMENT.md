# Raspberry Pi Deployment Setup

This document explains how to set up automated deployments to your Raspberry Pi when pull requests are created.

## Raspberry Pi Setup

### Prerequisites
- Raspberry Pi 4 (recommended) with Raspberry Pi OS
- At least 4GB RAM recommended
- SSH enabled on the Raspberry Pi
- Static IP address or dynamic DNS configured

### 1. Prepare Your Raspberry Pi

Run the setup script on your Raspberry Pi:

```bash
# Copy the setup script to your Pi
scp setup-pi.sh pi@your-pi-ip:~/
ssh pi@your-pi-ip

# Run the setup script
chmod +x ~/setup-pi.sh
./setup-pi.sh

# Reboot to ensure all changes take effect
sudo reboot
```

### 2. Configure SSH Access

Generate an SSH key pair for GitHub Actions:

```bash
# On your development machine
ssh-keygen -t rsa -b 4096 -f ~/.ssh/pi_deploy_key
```

Add the public key to your Raspberry Pi:

```bash
# Copy the public key to your Pi
ssh-copy-id -i ~/.ssh/pi_deploy_key.pub pi@your-pi-ip
```

### 3. Configure GitHub Secrets

Add the following secrets to your GitHub repository:

| Secret Name | Description | Example |
|-------------|-------------|---------|
| `PI_SSH_PRIVATE_KEY` | Contents of your private SSH key | `-----BEGIN RSA PRIVATE KEY-----...` |
| `PI_HOST` | Your Raspberry Pi's IP or hostname | `192.168.1.100` or `mypi.local` |
| `PI_USER` | SSH username for your Pi | `pi` |
| `DJANGO_SECRET_KEY` | Django secret key | `your-secret-key` |
| `DB_NAME` | Database name (optional) | `blog_db` |
| `DB_USER` | Database username (optional) | `blog_user` |
| `DB_PASSWORD` | Database password (optional) | `secure_password` |

## 🚀 How It Works

### Automatic Deployment on Pull Requests

When you create or update a pull request:

1. **Build**: GitHub Actions builds an ARM-compatible Docker image
2. **Deploy**: The image and configuration files are transferred to your Pi
3. **Start**: Docker Compose starts the services with a unique project name
4. **Test**: Health checks ensure the deployment is working
5. **Comment**: A comment is added to the PR with the deployment URL

### Deployment Features

- **Isolated Deployments**: Each PR gets its own containers and database
- **Resource Limits**: Optimized for Raspberry Pi hardware constraints
- **Auto Cleanup**: Deployments are automatically removed when PRs close
- **Health Monitoring**: Built-in health checks and monitoring
- **Nginx Reverse Proxy**: Optimized for Pi performance

### Accessing Your Deployment

After a successful deployment, you can access your application at:
```
http://your-pi-ip:port
```

The port will be dynamically assigned and shown in the GitHub Actions logs and PR comment.

## 🛠️ Local Development

### Build and Test for Pi Locally

```bash
# Build ARM image for Pi
make buildpi

# Test Pi deployment locally (requires ARM emulation)
make testpi

# Deploy to your Pi manually
make deploypi
```

### Manual Commands

```bash
# Start Pi services
make startpi

# Stop Pi services
make stoppi

# SSH into your Pi
make sshpi
```

## 📊 Monitoring and Maintenance

### Resource Monitoring

SSH into your Pi and monitor resources:

```bash
# CPU and memory usage
htop

# Docker container stats
docker stats

# Disk usage
df -h
```

### Log Management

```bash
# View deployment logs
docker-compose -f docker-compose.yml -f docker-compose.pi.yml logs

# View specific service logs
docker-compose -f docker-compose.yml -f docker-compose.pi.yml logs django

# Follow logs in real-time
docker-compose -f docker-compose.yml -f docker-compose.pi.yml logs -f
```

### Cleanup Old Deployments

The system automatically cleans up old deployments, but you can also run manual cleanup:

```bash
# Run the cleanup script
~/cleanup-old-deployments.sh

# Or clean up Docker manually
docker system prune -f
docker volume prune -f
```

## 🔧 Configuration

### Environment Variables

Create a `.env.pi` file for custom configuration:

```env
DJANGO_SECRET_KEY=your-secret-key
DJANGO_ALLOWED_HOSTS=localhost,192.168.1.100,mypi.local
DB_NAME=blog_db
DB_USER=blog_user
DB_PASSWORD=secure_password
```

### Nginx Configuration

The `nginx.pi.conf` file is optimized for Raspberry Pi. You can customize:

- Worker connections (default: 512)
- Client max body size (default: 10M)
- Keepalive timeout (default: 30s)
- Rate limiting (default: 10 requests per minute)

### Resource Limits

Docker Compose resource limits are set for Raspberry Pi 4:

- **Django**: 512M limit, 256M reserved
- **PostgreSQL**: 256M limit, 128M reserved

Adjust these in `docker-compose.pi.yml` based on your Pi model.

## 🐛 Troubleshooting

### Common Issues

1. **Out of Memory**: Reduce resource limits or close other applications
2. **Slow Performance**: Enable swap or upgrade to Pi 4 with more RAM
3. **Connection Issues**: Check firewall settings and network configuration
4. **Build Failures**: Ensure Docker BuildKit is enabled for ARM builds

### Debug Commands

```bash
# Check Pi system resources
free -h
df -h

# View Docker logs
docker-compose logs

# Check service status
docker-compose ps

# Restart services
docker-compose restart
```

## 📝 Notes

- Deployments are temporary and meant for testing PRs
- Production deployments should use the existing EC2 workflow
- Each PR deployment uses separate databases to avoid conflicts
- Automatic cleanup runs daily at 2 AM to remove old deployments
- The setup supports Raspberry Pi 3B+ and 4, but Pi 4 is recommended for better performance