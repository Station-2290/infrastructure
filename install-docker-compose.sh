#!/bin/bash

# Install Docker Compose on Ubuntu VPS
echo "🐳 Installing Docker Compose..."

# Check if Docker is installed
if ! command -v docker &> /dev/null; then
    echo "❌ Docker is not installed. Installing Docker first..."
    
    # Update package index
    sudo apt-get update
    
    # Install prerequisites
    sudo apt-get install -y apt-transport-https ca-certificates curl gnupg lsb-release
    
    # Add Docker's official GPG key
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg
    
    # Set up stable repository
    echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
    
    # Install Docker Engine
    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io
    
    # Add user to docker group
    sudo usermod -aG docker $USER
    
    echo "✅ Docker installed successfully"
else
    echo "✅ Docker is already installed"
fi

# Install Docker Compose V2 (newer syntax: docker compose)
echo "Installing Docker Compose V2..."

# Download and install Docker Compose V2
DOCKER_COMPOSE_VERSION="2.24.6"
sudo curl -L "https://github.com/docker/compose/releases/download/v${DOCKER_COMPOSE_VERSION}/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose

# Make it executable
sudo chmod +x /usr/local/bin/docker-compose

# Create symlink for docker-compose command
sudo ln -sf /usr/local/bin/docker-compose /usr/bin/docker-compose

# Verify installation
echo "Verifying Docker Compose installation..."
docker-compose --version

if command -v docker-compose &> /dev/null; then
    echo "✅ Docker Compose installed successfully"
else
    echo "❌ Docker Compose installation failed"
    exit 1
fi

# Also install Docker Compose Plugin (for 'docker compose' syntax)
echo "Installing Docker Compose Plugin..."
sudo apt-get update
sudo apt-get install -y docker-compose-plugin

echo "🎉 Installation complete!"
echo "You can now use:"
echo "  - docker-compose (traditional syntax)"
echo "  - docker compose (newer syntax)"

# Test both syntaxes
echo "Testing Docker Compose..."
docker-compose version
echo "---"
docker compose version