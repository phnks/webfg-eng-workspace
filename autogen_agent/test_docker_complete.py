#!/usr/bin/env python3
"""
Complete Docker Container Startup Test
=====================================

This script tests the complete Docker workflow including the actual container startup
that was failing. It reproduces the exact steps the user would follow and catches
Docker Compose and container runtime issues.

Run with: python3 test_docker_complete.py
"""

import os
import sys
import time
import subprocess
import signal
from pathlib import Path
import json

# Test configuration
TEST_USER = "testclaude"
DOCKER_DIR = Path(__file__).parent.parent / "docker"
TIMEOUT_SECONDS = 120

def run_command(cmd, cwd=None, timeout=30, capture_output=True, use_sudo=False):
    """Run a command and return the result."""
    if use_sudo and not cmd.startswith("sudo"):
        cmd = f"sudo {cmd}"
    
    try:
        if capture_output:
            result = subprocess.run(
                cmd, shell=True, cwd=cwd, timeout=timeout,
                capture_output=True, text=True
            )
            return result.returncode == 0, result.stdout, result.stderr
        else:
            result = subprocess.run(cmd, shell=True, cwd=cwd, timeout=timeout)
            return result.returncode == 0, "", ""
    except subprocess.TimeoutExpired:
        print(f"⏰ Command timed out after {timeout}s: {cmd}")
        return False, "", "Timeout"
    except Exception as e:
        print(f"❌ Command failed: {cmd}, Error: {e}")
        return False, "", str(e)

def check_docker_permissions():
    """Check if we can run Docker commands."""
    print("🔐 Checking Docker permissions...")
    
    # Try without sudo first
    success, stdout, stderr = run_command("docker --version", timeout=5)
    if success:
        # Check if we can actually use docker
        success, stdout, stderr = run_command("docker ps", timeout=10)
        if success:
            print("✅ Docker commands work without sudo")
            return True, False
        else:
            print("⚠️ Docker version works but docker ps fails - need sudo")
    
    # Try with sudo
    success, stdout, stderr = run_command("sudo docker --version", timeout=10)
    if not success:
        print("❌ Docker not available even with sudo")
        return False, False
    
    success, stdout, stderr = run_command("sudo docker ps", timeout=10)
    if success:
        print("✅ Docker commands work with sudo")
        return True, True
    else:
        print("❌ Docker not working even with sudo")
        print(f"Error: {stderr}")
        return False, False

def cleanup_containers(use_sudo=False):
    """Clean up any existing containers for our test user."""
    print(f"🧹 Cleaning up existing containers for {TEST_USER}...")
    
    # Stop and remove containers
    commands = [
        f"docker stop agent-{TEST_USER}",
        f"docker rm agent-{TEST_USER}",
        f"docker network prune -f"
    ]
    
    for cmd in commands:
        success, stdout, stderr = run_command(cmd, use_sudo=use_sudo, timeout=15)
        if not success and "No such container" not in stderr and "Error: No such network" not in stderr:
            print(f"⚠️ Cleanup command failed (may be normal): {cmd}")
    
    print("✅ Cleanup completed")

def test_provision_container(use_sudo=False):
    """Test container provisioning."""
    print(f"📦 Testing container provisioning for {TEST_USER}...")
    
    provision_script = DOCKER_DIR / "scripts" / "provision_container.sh"
    if not provision_script.exists():
        print("❌ provision_container.sh not found")
        return False
    
    # Run provision script
    cmd = f"./scripts/provision_container.sh {TEST_USER} autogen"
    success, stdout, stderr = run_command(cmd, cwd=DOCKER_DIR, timeout=120, use_sudo=use_sudo)
    
    if not success:
        print("❌ Container provisioning failed!")
        print(f"STDOUT: {stdout}")
        print(f"STDERR: {stderr}")
        return False
    
    print("✅ Container provisioning completed")
    return True

def test_container_startup(use_sudo=False):
    """Test the actual container startup that was failing."""
    print(f"🚀 Testing container startup for {TEST_USER}...")
    
    start_script = DOCKER_DIR / "scripts" / "start_container.sh"
    if not start_script.exists():
        print("❌ start_container.sh not found")
        return False
    
    # Test the original start_container.sh script (now with Docker Compose v2 support)
    cmd = f"./scripts/start_container.sh {TEST_USER}"
    success, stdout, stderr = run_command(cmd, cwd=DOCKER_DIR, timeout=60, use_sudo=use_sudo)
    
    if not success:
        print("❌ Container startup failed!")
        print("=" * 50)
        print("STDOUT:")
        print(stdout)
        print("=" * 50)
        print("STDERR:")
        print(stderr)
        print("=" * 50)
        
        # Check if this is the known 'ContainerConfig' error
        if "'ContainerConfig'" in stderr:
            print("\n🚨 DETECTED: 'ContainerConfig' error - Docker Compose version compatibility issue")
            
            # Check docker-compose version
            success2, out2, err2 = run_command("docker-compose --version", use_sudo=use_sudo)
            if success2:
                version = out2.strip()
                print(f"Docker Compose version: {version}")
                if "1." in version:
                    print("🔧 Docker Compose v1.x detected - needs upgrade to v2+")
                    print("\n📋 Please upgrade Docker Compose by running:")
                    print("   sudo apt update")
                    print("   sudo apt install -y docker-compose-plugin")
                    print("\n✅ After upgrade, the script should work correctly.")
                    print("   The updated start_container.sh will automatically detect and use Docker Compose v2.")
        
        # Additional debugging for other errors
        print("\n🔍 Additional debugging info:")
        
        # Check if docker compose v2 is available
        success_v2, out_v2, err_v2 = run_command("docker compose version", use_sudo=use_sudo)
        if success_v2:
            print(f"✅ Docker Compose v2 available: {out_v2.strip()}")
            print("The script should automatically use this version.")
        else:
            print("❌ Docker Compose v2 not available")
            print("Please install with: sudo apt install -y docker-compose-plugin")
        
        # Check if docker-compose.yml is valid
        success3, out3, err3 = run_command("docker-compose config", cwd=DOCKER_DIR, use_sudo=use_sudo)
        if success3:
            print("✅ docker-compose.yml syntax is valid")
        else:
            print(f"❌ docker-compose.yml syntax error: {err3}")
        
        # Check for existing problematic containers
        success4, out4, err4 = run_command("docker ps -a --filter name=agent", use_sudo=use_sudo)
        if success4:
            print(f"Existing containers:\n{out4}")
        
        return False
    
    print("✅ Container startup completed")
    print(f"STDOUT: {stdout}")
    return True

def test_container_logs(use_sudo=False):
    """Test container logs to verify Claude integration."""
    print("📜 Testing container logs...")
    
    # Check if container is running
    success, stdout, stderr = run_command(f"docker ps -q -f name=agent-{TEST_USER}", use_sudo=use_sudo)
    if not success or not stdout.strip():
        print(f"❌ Container agent-{TEST_USER} is not running!")
        
        # Check if it exists but stopped
        success2, stdout2, stderr2 = run_command(f"docker ps -a -q -f name=agent-{TEST_USER}", use_sudo=use_sudo)
        if success2 and stdout2.strip():
            print("Container exists but is stopped. Getting logs anyway...")
        else:
            print("Container doesn't exist at all!")
            return False
    
    # Wait a bit for container to initialize
    print("⏳ Waiting for container to initialize...")
    time.sleep(10)
    
    # Get logs using the logs script
    logs_script = DOCKER_DIR / "scripts" / "logs_container.sh"
    if logs_script.exists():
        success, logs, stderr = run_command(f"./scripts/logs_container.sh {TEST_USER}", cwd=DOCKER_DIR, timeout=30, use_sudo=use_sudo)
    else:
        # Fallback to direct docker logs
        success, logs, stderr = run_command(f"docker logs agent-{TEST_USER}", timeout=30, use_sudo=use_sudo)
    
    if not success:
        print("❌ Failed to get container logs!")
        print(f"STDERR: {stderr}")
        return False
    
    print("📋 Container logs:")
    print("=" * 80)
    print(logs)
    print("=" * 80)
    
    # Analyze logs for success/failure indicators
    success_indicators = [
        "✅ Claude Bedrock client imported",
        "✅ LLM config created for claude",
        "✅ AWS Bedrock client initialized"
    ]
    
    failure_indicators = [
        "❌",
        "ERROR:",
        "Traceback",
        "ImportError",
        "✅ Using OpenAI client (default)",
        "MODEL_PROVIDER=openai"
    ]
    
    found_success = []
    found_failures = []
    
    for indicator in success_indicators:
        if indicator in logs:
            found_success.append(indicator)
    
    for indicator in failure_indicators:
        if indicator in logs:
            found_failures.append(indicator)
    
    print(f"\n📊 Log Analysis:")
    print(f"✅ Success indicators: {len(found_success)}/{len(success_indicators)}")
    for indicator in found_success:
        print(f"   ✅ Found: {indicator}")
    
    if found_failures:
        print(f"❌ Failure indicators: {len(found_failures)}")
        for indicator in found_failures:
            print(f"   ❌ Found: {indicator}")
        return False
    
    missing_success = set(success_indicators) - set(found_success)
    if missing_success:
        print(f"⚠️ Missing success indicators:")
        for indicator in missing_success:
            print(f"   ⚠️ Missing: {indicator}")
        return False
    
    print("\n🎉 All success indicators found! Claude integration working in Docker!")
    return True

def main():
    """Run the complete Docker startup test."""
    print("🔍 Complete Docker Container Startup Test")
    print("=" * 60)
    print(f"Testing with user: {TEST_USER}")
    print(f"Docker directory: {DOCKER_DIR}")
    print()
    
    # Check Docker permissions
    docker_available, use_sudo = check_docker_permissions()
    if not docker_available:
        print("❌ Docker is not available. Please install Docker and ensure you have permissions.")
        return False
    
    try:
        # Test steps in order
        steps = [
            ("Cleanup", lambda: cleanup_containers(use_sudo)),
            ("Provision Container", lambda: test_provision_container(use_sudo)),
            ("Container Startup", lambda: test_container_startup(use_sudo)),
            ("Container Logs", lambda: test_container_logs(use_sudo)),
        ]
        
        for step_name, step_func in steps:
            print(f"\n🧪 {step_name}")
            print("-" * 40)
            
            if not step_func():
                print(f"\n❌ {step_name} FAILED!")
                
                # Show additional debug info for startup failures
                if step_name == "Container Startup":
                    print("\n🔧 Suggested fixes:")
                    print("1. Try removing all containers: sudo docker system prune -a")
                    print("2. Check docker-compose version: docker-compose --version")
                    print("3. Update Docker Compose if < 2.0")
                    print("4. Check for conflicting containers or networks")
                
                return False
            
            print(f"✅ {step_name} PASSED!")
        
        print("\n" + "=" * 60)
        print("🎉 ALL TESTS PASSED!")
        print("✅ Docker container startup working correctly!")
        print("✅ Claude integration working in Docker!")
        print(f"✅ Container agent-{TEST_USER} is running successfully")
        
        print(f"\n📝 Next steps:")
        print(f"1. Test Discord bot interaction")
        print(f"2. Monitor logs: sudo docker logs -f agent-{TEST_USER}")
        print(f"3. When done testing: sudo docker stop agent-{TEST_USER}")
        
        return True
        
    except KeyboardInterrupt:
        print("\n⏹️ Test interrupted by user")
        return False
    
    except Exception as e:
        print(f"\n❌ Unexpected error: {e}")
        import traceback
        traceback.print_exc()
        return False

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)