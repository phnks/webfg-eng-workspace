#!/usr/bin/env python3
"""
Quick validation test for AWS Knowledge Base MCP Server setup
"""

import os
import json

def test_structure():
    """Test that all required files and directories exist."""
    print("Testing project structure...")
    
    required_items = [
        "awslabs/",
        "infrastructure/knowledge-base-stack.yaml",
        "scripts/deploy.sh",
        "scripts/destroy.sh",
        "mock-data/documents/",
        "pyproject.toml"
    ]
    
    all_good = True
    for item in required_items:
        if os.path.exists(item):
            print(f"✓ {item}")
        else:
            print(f"✗ {item}")
            all_good = False
    
    return all_good

def test_mock_data():
    """Test mock data files."""
    print("\nTesting mock data files...")
    
    mock_dir = "mock-data/documents"
    if not os.path.exists(mock_dir):
        print("✗ Mock data directory missing")
        return False
    
    files = [f for f in os.listdir(mock_dir) if f.endswith('.txt')]
    total_size = 0
    
    for file in files:
        path = os.path.join(mock_dir, file)
        size = os.path.getsize(path)
        total_size += size
        print(f"✓ {file}: {size} bytes")
    
    print(f"Total: {len(files)} files, {total_size} bytes")
    return len(files) > 0 and total_size > 1000

def test_scripts():
    """Test deployment scripts."""
    print("\nTesting deployment scripts...")
    
    scripts = ["scripts/deploy.sh", "scripts/destroy.sh"]
    all_good = True
    
    for script in scripts:
        if os.path.exists(script) and os.access(script, os.X_OK):
            print(f"✓ {script} (executable)")
        else:
            print(f"✗ {script}")
            all_good = False
    
    return all_good

def main():
    print("AWS Knowledge Base MCP Server - Quick Validation")
    print("=" * 50)
    
    tests = [test_structure, test_mock_data, test_scripts]
    results = []
    
    for test in tests:
        results.append(test())
    
    print("\n" + "=" * 50)
    passed = sum(results)
    total = len(results)
    
    print(f"Tests passed: {passed}/{total}")
    
    if passed == total:
        print("✓ Setup validation successful!")
        print("\nNext steps:")
        print("1. Install dependencies: pip install boto3 loguru mcp pydantic")
        print("2. Configure AWS CLI: aws configure")
        print("3. Deploy infrastructure: ./scripts/deploy.sh")
        return 0
    else:
        print("✗ Some validation checks failed")
        return 1

if __name__ == "__main__":
    exit(main())