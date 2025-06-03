#!/bin/bash
"""
Fix Docker Compose Compatibility Issues
======================================

This script addresses the 'ContainerConfig' error that occurs with older 
Docker Compose versions (like 1.29.2) when trying to start containers.

The error happens because older Docker Compose versions can't properly 
handle container metadata from newer Docker versions.
"""

set -e

echo "🔧 Docker Compose Compatibility Fix"
echo "===================================="

# Check current Docker Compose version
echo "📋 Current Docker Compose version:"
docker-compose --version

# Check Docker version
echo "📋 Current Docker version:"
docker --version

echo ""
echo "🚨 The 'ContainerConfig' error you encountered is a known issue"
echo "   with Docker Compose version 1.x when used with newer Docker versions."
echo ""

# Offer solutions
echo "🔧 Suggested fixes (choose one):"
echo ""

echo "1. 🎯 RECOMMENDED: Clean up and restart (easiest fix)"
echo "   - Removes potentially corrupted container metadata"
echo "   - Uses 'docker run' instead of 'docker-compose' for better compatibility"
echo ""

echo "2. ⬆️ ALTERNATIVE: Upgrade Docker Compose to v2+"
echo "   - More modern and compatible"
echo "   - Requires system package manager or manual install"
echo ""

read -p "Which fix would you like to try? (1/2): " choice

case $choice in
    1)
        echo "🧹 Applying Fix 1: Clean up and restart with docker run"
        echo "=================================================="
        
        # Get username
        read -p "Enter username (e.g., anum): " username
        
        echo "🛑 Stopping and removing existing containers..."
        sudo docker stop agent-$username 2>/dev/null || echo "No container to stop"
        sudo docker rm agent-$username 2>/dev/null || echo "No container to remove"
        
        echo "🔥 Cleaning up Docker system..."
        sudo docker system prune -f
        
        echo "✅ Cleanup complete!"
        echo ""
        echo "📝 Next step: Try starting container again"
        echo "   cd docker && ./scripts/start_container.sh $username"
        ;;
        
    2)
        echo "⬆️ Applying Fix 2: Upgrade Docker Compose"
        echo "========================================"
        
        echo "🔍 Checking if Docker Compose v2+ is available..."
        
        # Check if docker compose (v2) is available
        if docker compose version &>/dev/null; then
            echo "✅ Docker Compose v2+ is already available!"
            echo "📋 Version:"
            docker compose version
            echo ""
            echo "🔧 You can use 'docker compose' instead of 'docker-compose'"
            echo "   But we'll need to update the scripts to use the new command."
            
            read -p "Create a docker-compose-v2 alias? (y/n): " create_alias
            if [[ $create_alias == "y" ]]; then
                echo "alias docker-compose='docker compose'" >> ~/.bashrc
                echo "✅ Alias created! Run 'source ~/.bashrc' or restart terminal"
            fi
        else
            echo "ℹ️ Docker Compose v2+ not found. Installation options:"
            echo ""
            echo "Ubuntu/Debian:"
            echo "  sudo apt update"
            echo "  sudo apt install docker-compose-plugin"
            echo ""
            echo "Manual install:"
            echo "  sudo curl -L \"https://github.com/docker/compose/releases/latest/download/docker-compose-linux-x86_64\" -o /usr/local/bin/docker-compose"
            echo "  sudo chmod +x /usr/local/bin/docker-compose"
        fi
        ;;
        
    *)
        echo "❌ Invalid choice. Please run the script again."
        exit 1
        ;;
esac

echo ""
echo "🎯 After applying the fix, test with:"
echo "   cd docker"
echo "   ./scripts/start_container.sh $username"
echo "   ./scripts/logs_container.sh $username"