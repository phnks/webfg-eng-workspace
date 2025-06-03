#!/bin/bash

# Upgrade Docker Compose to v2 to fix compatibility issues
# This resolves the 'ContainerConfig' error with Docker 27.x

set -e

echo "🔧 Docker Compose Upgrade Script"
echo "================================"
echo ""
echo "Current versions:"
echo "Docker: $(docker --version)"
echo "Docker Compose: $(docker-compose --version)"
echo ""

echo "📋 This script will upgrade Docker Compose to v2+ to fix compatibility issues."
echo ""

# Detect OS
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS=$ID
    VERSION=$VERSION_ID
else
    echo "❌ Cannot detect OS version"
    exit 1
fi

echo "Detected OS: $OS $VERSION"
echo ""

if [ "$OS" = "ubuntu" ] || [ "$OS" = "debian" ]; then
    echo "📦 Installing Docker Compose v2 via docker-compose-plugin..."
    echo ""
    echo "Please run these commands with sudo:"
    echo ""
    echo "sudo apt update"
    echo "sudo apt install -y docker-compose-plugin"
    echo ""
    echo "After installation, Docker Compose v2 will be available as 'docker compose' (without hyphen)"
    echo ""
    echo "To verify installation:"
    echo "docker compose version"
    echo ""
    echo "📝 Note: We'll update our scripts to support both 'docker-compose' and 'docker compose' commands."
else
    echo "⚠️ Automated installation not available for $OS"
    echo ""
    echo "For manual installation, run:"
    echo ""
    echo "# Download latest Docker Compose v2"
    echo "sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64\" -o /usr/local/bin/docker-compose"
    echo "sudo chmod +x /usr/local/bin/docker-compose"
    echo ""
    echo "# Verify installation"
    echo "docker-compose --version"
fi

echo ""
echo "🔧 After upgrading Docker Compose, the container startup should work correctly."