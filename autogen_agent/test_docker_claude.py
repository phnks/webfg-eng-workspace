#!/usr/bin/env python3
"""
Comprehensive Docker Claude Integration Test
===========================================

This script tests the complete Docker workflow:
1. Builds the Docker image with Claude integration
2. Starts a container using start_container.sh
3. Monitors logs to verify Claude is working
4. Cleans up the container

This simulates exactly what the user experiences when deploying Claude.
"""

import os
import sys
import time
import subprocess
import signal
from pathlib import Path

# Test configuration
TEST_USER = "testclaude"
DOCKER_DIR = Path(__file__).parent.parent / "docker"
TIMEOUT_SECONDS = 120  # 2 minutes max for container startup

def run_command(cmd, cwd=None, timeout=30, capture_output=True):
    """Run a command and return the result."""
    try:
        if capture_output:
            result = subprocess.run(
                cmd, shell=True, cwd=cwd, timeout=timeout,
                capture_output=True, text=True
            )
            return result.returncode == 0, result.stdout, result.stderr
        else:
            # For interactive commands, don't capture output
            result = subprocess.run(cmd, shell=True, cwd=cwd, timeout=timeout)
            return result.returncode == 0, "", ""
    except subprocess.TimeoutExpired:
        print(f"⏰ Command timed out after {timeout}s: {cmd}")
        return False, "", "Timeout"
    except Exception as e:
        print(f"❌ Command failed: {cmd}, Error: {e}")
        return False, "", str(e)

def cleanup_container():
    """Clean up any existing test container."""
    print(f"🧹 Cleaning up existing container agent-{TEST_USER}...")
    run_command(f"docker stop agent-{TEST_USER}", timeout=10)
    run_command(f"docker rm agent-{TEST_USER}", timeout=10)

def test_docker_build():
    """Test Docker image build."""
    print("🏗️ Testing Docker image build...")
    
    success, stdout, stderr = run_command(
        "./scripts/build_image.sh", 
        cwd=DOCKER_DIR, 
        timeout=300  # 5 minutes for build
    )
    
    if not success:
        print("❌ Docker build failed!")
        print(f"STDOUT: {stdout}")
        print(f"STDERR: {stderr}")
        return False
    
    print("✅ Docker image built successfully")
    return True

def test_environment_setup():
    """Test that .env file has Claude configuration."""
    print("📋 Checking Docker .env configuration...")
    
    env_file = DOCKER_DIR / ".env"
    if not env_file.exists():
        print("❌ Docker .env file not found!")
        return False
    
    env_content = env_file.read_text()
    
    required_vars = [
        "MODEL_PROVIDER=claude",
        "BEDROCK_AWS_ACCESS_KEY_ID=",
        "BEDROCK_AWS_SECRET_ACCESS_KEY=",
        "BEDROCK_AWS_REGION="
    ]
    
    missing_vars = []
    for var in required_vars:
        if var not in env_content:
            missing_vars.append(var)
    
    if missing_vars:
        print(f"❌ Missing environment variables in .env: {missing_vars}")
        return False
    
    print("✅ Environment configuration verified")
    return True

def test_container_startup():
    """Test container startup with Claude configuration."""
    print(f"🚀 Starting container agent-{TEST_USER}...")
    
    # Set environment variables for the test user
    env = os.environ.copy()
    env["USERNAME"] = TEST_USER
    env["BOT_TOKEN"] = env.get("BOT_TOKEN_anum", "test-token")  # Use test token
    
    # Start container
    success, stdout, stderr = run_command(
        f"./scripts/start_container.sh {TEST_USER}",
        cwd=DOCKER_DIR,
        timeout=60
    )
    
    if not success:
        print("❌ Container startup failed!")
        print(f"STDOUT: {stdout}")
        print(f"STDERR: {stderr}")
        return False
    
    print("✅ Container started successfully")
    
    # Wait a bit for container to initialize
    print("⏳ Waiting for container to initialize...")
    time.sleep(10)
    
    return True

def test_container_logs():
    """Test container logs to verify Claude integration is working."""
    print("📜 Checking container logs for Claude integration...")
    
    # Check if container is running
    success, stdout, stderr = run_command(f"docker ps -q -f name=agent-{TEST_USER}")
    if not success or not stdout.strip():
        print(f"❌ Container agent-{TEST_USER} is not running!")
        return False
    
    # Get logs
    success, logs, stderr = run_command(
        f"./scripts/logs_container.sh {TEST_USER}",
        cwd=DOCKER_DIR,
        timeout=30
    )
    
    if not success:
        print("❌ Failed to get container logs!")
        print(f"STDERR: {stderr}")
        return False
    
    print("📋 Container logs:")
    print("=" * 50)
    print(logs)
    print("=" * 50)
    
    # Check for success indicators
    success_indicators = [
        "MODEL_PROVIDER=claude",  # Should be using Claude
        "✅ Claude Bedrock client imported",  # Claude client loaded
        "✅ LLM config created for claude",  # Claude config working
        "✅ AWS Bedrock client initialized"  # Bedrock connection OK
    ]
    
    failure_indicators = [
        "ImportError",  # Import errors
        "❌",  # Error indicators
        "Traceback",  # Python exceptions
        "MODEL_PROVIDER=openai",  # Should NOT be using OpenAI
        "✅ Using OpenAI client"  # Should NOT be using OpenAI
    ]
    
    found_success = []
    found_failures = []
    
    for indicator in success_indicators:
        if indicator in logs:
            found_success.append(indicator)
    
    for indicator in failure_indicators:
        if indicator in logs:
            found_failures.append(indicator)
    
    print(f"\n✅ Success indicators found: {len(found_success)}/{len(success_indicators)}")
    for indicator in found_success:
        print(f"   ✅ {indicator}")
    
    if found_failures:
        print(f"\n❌ Failure indicators found: {len(found_failures)}")
        for indicator in found_failures:
            print(f"   ❌ {indicator}")
        return False
    
    if len(found_success) < len(success_indicators):
        print(f"\n⚠️ Only found {len(found_success)}/{len(success_indicators)} success indicators")
        missing = set(success_indicators) - set(found_success)
        print(f"Missing: {missing}")
        return False
    
    print("\n🎉 All success indicators found! Claude integration is working in Docker!")
    return True

def main():
    """Run the complete Docker Claude integration test."""
    print("🔍 Docker Claude Integration Test")
    print("=" * 50)
    
    # Check if we can run docker commands
    success, _, _ = run_command("docker --version")
    if not success:
        print("❌ Docker is not available. Make sure Docker is installed and you have permissions.")
        print("Try: sudo usermod -aG docker $USER && newgrp docker")
        return False
    
    try:
        # Test steps
        steps = [
            ("Environment Setup", test_environment_setup),
            ("Docker Build", test_docker_build),
            ("Container Startup", test_container_startup),
            ("Container Logs", test_container_logs),
        ]
        
        for step_name, step_func in steps:
            print(f"\n🧪 {step_name}")
            print("-" * 30)
            
            if not step_func():
                print(f"\n❌ {step_name} failed!")
                return False
            
            print(f"✅ {step_name} passed!")
        
        print("\n" + "=" * 50)
        print("🎉 ALL TESTS PASSED!")
        print("✅ Claude integration is working correctly in Docker!")
        print(f"✅ Container agent-{TEST_USER} is running with Claude")
        print("\n📝 Next steps:")
        print(f"1. Check Discord for bot activity")
        print(f"2. Test actual conversations with the Claude bot")
        print(f"3. Clean up: docker stop agent-{TEST_USER}")
        
        return True
        
    except KeyboardInterrupt:
        print("\n⏹️ Test interrupted by user")
        return False
    
    finally:
        # Optional cleanup - comment out to leave container running for further testing
        # print(f"\n🧹 Cleaning up test container...")
        # cleanup_container()
        pass

if __name__ == "__main__":
    success = main()
    sys.exit(0 if success else 1)