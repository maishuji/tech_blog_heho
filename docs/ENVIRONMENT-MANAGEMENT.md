# Environment Variables Management Guide 🔐

This guide explains how to properly manage environment variables and secrets in this project.

## 📁 File Structure

```
.env.example          # ✅ Template for local development (COMMIT THIS)
.env.pi.example       # ✅ Template for Pi deployment (COMMIT THIS)  
.env.prod.example     # ✅ Template for production (COMMIT THIS)

.env                  # ❌ Local dev with real values (DO NOT COMMIT)
.env.pi.deploy        # ❌ Pi deployment with real values (DO NOT COMMIT)
.env.prod             # ❌ Production with real values (DO NOT COMMIT)
```

## 🔐 Security Principle

**GOLDEN RULE: Never commit files containing real secrets to Git!**

- ✅ **Templates** (`.example` files) → Safe to commit
- ❌ **Real values** (no `.example` suffix) → Never commit

## 🚀 Quick Setup

### Option 1: Automated Setup
```bash
./setup-env.sh
```

### Option 2: Manual Setup
```bash
# Local development
cp .env.example .env
# Edit .env with your values

# Pi deployment  
cp .env.pi.example .env.pi.deploy
# Edit .env.pi.deploy with your values

# Production
cp .env.prod.example .env.prod
# Edit .env.prod with your values
```

## 🎯 Environment Types

### 1. Local Development (`.env`)
**Purpose:** Running the app locally on your computer

**Key Variables:**
```bash
PI_HOST=192.168.1.100
PI_USER=pi
PI_SSH_KEY_PATH=~/.ssh/id_rsa
DJANGO_DEBUG=True
DJANGO_SECRET_KEY=local-dev-key
```

### 2. Raspberry Pi (`.env.pi.deploy`)  
**Purpose:** Deploying to your Raspberry Pi

**Key Variables:**
```bash
DJANGO_SECRET_KEY=pi-specific-secret-key
DJANGO_ALLOWED_HOSTS=localhost,127.0.0.1,192.168.1.100
DJANGO_TRUSTED_ORIGINS=http://localhost,http://192.168.1.100
DB_NAME=blog_pi_db
DB_USER=blog_user
DB_PASSWORD=secure_pi_password
COMPOSE_PROJECT_NAME=blog_pi
```

### 3. Production (`.env.prod`)
**Purpose:** Production server deployment

**Key Variables:**
```bash
DJANGO_SECRET_KEY=super-secure-production-key
DJANGO_DEBUG=False
DJANGO_ALLOWED_HOSTS=yourdomain.com,www.yourdomain.com
DB_PASSWORD=very-secure-production-password
EMAIL_HOST_USER=your-email@domain.com
COMPOSE_PROJECT_NAME=blog_prod
```

## 🔧 Usage with Make Commands

The Makefile automatically loads environment variables:

```bash
# Loads from .env if it exists
make deploypi

# Override with environment variables
PI_HOST=192.168.1.200 make deploypi

# Check what's loaded
make check-pi-config
```

## 🛡️ Security Best Practices

### ✅ DO:
- Use strong, unique passwords for each environment
- Generate random Django secret keys for each environment
- Store production secrets in a password manager
- Regularly rotate passwords and keys
- Use different database users for each environment
- Set appropriate `ALLOWED_HOSTS` for each environment

### ❌ DON'T:
- Commit real secrets to Git
- Use the same passwords across environments
- Use simple or default passwords
- Share production credentials via email/chat
- Use production secrets in development

## 🔑 Generating Secrets

### Django Secret Keys
```bash
# Generate a secure secret key
python3 -c "import secrets; print(secrets.token_urlsafe(50))"

# Or use the setup script
./setup-env.sh
```

### Database Passwords
```bash
# Generate a secure password
python3 -c "import secrets; print(secrets.token_urlsafe(32))"
```

## 🚨 If Secrets Are Accidentally Committed

If you accidentally commit real secrets:

1. **Immediately change all compromised secrets**
2. **Remove from Git history:**
   ```bash
   git filter-branch --force --index-filter 'git rm --cached --ignore-unmatch .env.pi.deploy' --prune-empty --tag-name-filter cat -- --all
   ```
3. **Force push** (if working with others, coordinate first)
4. **Regenerate all secrets**

## 🎛️ Environment Loading Order

The application loads variables in this order (later overrides earlier):

1. System environment variables
2. `.env` file (if exists)  
3. Command-line overrides

## 📋 Checklist for New Environments

When setting up a new environment:

- [ ] Copy from appropriate `.example` template
- [ ] Generate unique Django secret key
- [ ] Set strong database password
- [ ] Configure correct hostnames/IPs
- [ ] Set appropriate `DJANGO_DEBUG` value
- [ ] Configure email settings (if needed)
- [ ] Test the configuration
- [ ] Verify `.gitignore` excludes the file

## 🔍 Troubleshooting

### "Environment variable not found"
1. Check if `.env` file exists
2. Verify variable name spelling
3. Check file permissions
4. Try loading manually: `source .env`

### "Configuration not loading"
1. Check file format (no spaces around `=`)
2. Verify `.env` file location
3. Check for syntax errors
4. Test with `make check-pi-config`

### "Secrets in Git history"
1. Follow the secret leak procedure above
2. Use `git log --follow filename` to track history
3. Consider using BFG Repo-Cleaner for complex cases

## 📚 Related Documentation

- [Pi Deployment Guide](README-PI-DEPLOYMENT.md)
- [Deploy from Computer Guide](DEPLOY-FROM-COMPUTER.md)
- [Django Settings Documentation](https://docs.djangoproject.com/en/stable/topics/settings/)
- [Docker Compose Environment Variables](https://docs.docker.com/compose/environment-variables/)

---

**Remember: When in doubt, keep it secret! 🔐**