#!/bin/bash

# Environment Setup Script
# This script helps you set up environment files from templates

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}🔧 Environment Setup Script${NC}"
echo -e "${GREEN}==============================${NC}"
echo ""

# Function to create env file from template
create_env_file() {
    local template_file="$1"
    local target_file="$2" 
    local description="$3"
    
    echo -e "${YELLOW}Setting up $description...${NC}"
    
    if [[ ! -f "$template_file" ]]; then
        echo -e "${RED}❌ Template file $template_file not found!${NC}"
        return 1
    fi
    
    if [[ -f "$target_file" ]]; then
        echo -e "${YELLOW}⚠️  $target_file already exists. Backup and recreate? (y/N)${NC}"
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            cp "$target_file" "$target_file.backup.$(date +%Y%m%d-%H%M%S)"
            echo -e "${GREEN}✅ Backup created${NC}"
        else
            echo -e "${YELLOW}ℹ️  Skipping $target_file${NC}"
            return 0
        fi
    fi
    
    cp "$template_file" "$target_file"
    echo -e "${GREEN}✅ Created $target_file from template${NC}"
    echo -e "${YELLOW}📝 Please edit $target_file with your actual values${NC}"
    echo ""
}

# Function to generate Django secret key
generate_secret_key() {
    python3 -c "import secrets; print(secrets.token_urlsafe(50))"
}

echo "This script will help you set up environment files from templates."
echo "You'll need to edit them with your actual values after creation."
echo ""

# Ask which environments to set up
echo "Which environments would you like to set up?"
echo "1. Local development (.env)"
echo "2. Raspberry Pi deployment (.env.pi.deploy)" 
echo "3. Production (.env.prod)"
echo "4. All of the above"
echo ""
read -p "Enter your choice (1-4): " choice

case $choice in
    1)
        create_env_file ".env.example" ".env" "Local Development Environment"
        ;;
    2) 
        create_env_file ".env.pi.example" ".env.pi.deploy" "Raspberry Pi Deployment Environment"
        ;;
    3)
        create_env_file ".env.prod.example" ".env.prod" "Production Environment" 
        ;;
    4)
        create_env_file ".env.example" ".env" "Local Development Environment"
        create_env_file ".env.pi.example" ".env.pi.deploy" "Raspberry Pi Deployment Environment"
        create_env_file ".env.prod.example" ".env.prod" "Production Environment"
        ;;
    *)
        echo -e "${RED}❌ Invalid choice${NC}"
        exit 1
        ;;
esac

# Generate Django secret keys
echo -e "${GREEN}🔑 Security Setup${NC}"
echo -e "${GREEN}=================${NC}"
echo ""
echo "Here are some generated Django secret keys you can use:"
echo ""
echo -e "${YELLOW}Local Development Key:${NC}"
generate_secret_key
echo ""
echo -e "${YELLOW}Pi Deployment Key:${NC}"
generate_secret_key
echo ""
echo -e "${YELLOW}Production Key:${NC}"
generate_secret_key
echo ""

echo -e "${GREEN}✅ Environment setup complete!${NC}"
echo ""
echo -e "${YELLOW}📋 Next Steps:${NC}"
echo "1. Edit the created .env files with your actual values"
echo "2. Replace placeholder secret keys with the generated ones above"
echo "3. Update IP addresses, hostnames, and credentials"
echo "4. Test your configuration"
echo ""
echo -e "${RED}⚠️  IMPORTANT SECURITY NOTES:${NC}"
echo "- Never commit .env files with real secrets to Git"
echo "- Use strong, unique passwords for each environment"
echo "- Store production secrets in a secure password manager"
echo "- Regularly rotate secrets and passwords"
echo ""
echo -e "${GREEN}🚀 Happy coding!${NC}"