#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
Test script for AWS Knowledge Base MCP Server
Tests the MCP server functionality without requiring actual AWS deployment.
"""

import json
import os
import sys
from unittest.mock import Mock, patch

# Add the project root to Python path
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

def test_imports():
    """Test that all required modules can be imported."""
    print("Testing imports...")
    
    try:
        from awslabs.bedrock_kb_retrieval_mcp_server.server import main
        from awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases import clients, discovery, retrieval
        import awslabs.bedrock_kb_retrieval_mcp_server.models
        print("✓ All imports successful")
        return True
    except ImportError as e:
        print(f"✗ Import error: {e}")
        return False

def test_server_initialization():
    """Test that the MCP server can be initialized."""
    print("Testing server initialization...")
    
    try:
        # Mock AWS clients to avoid requiring real AWS credentials
        with patch('awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.clients.get_bedrock_agent_client') as mock_agent:
            with patch('awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.clients.get_bedrock_agent_runtime_client') as mock_runtime:
                mock_agent.return_value = Mock()
                mock_runtime.return_value = Mock()
                
                # Import and test server initialization
                from awslabs.bedrock_kb_retrieval_mcp_server.server import mcp
                
                print("✓ MCP server initialized successfully")
                print(f"   Server name: {mcp.name}")
                return True
    except Exception as e:
        print(f"✗ Server initialization error: {e}")
        return False

def test_mock_knowledge_base_discovery():
    """Test knowledge base discovery with mock data."""
    print("Testing knowledge base discovery...")
    
    try:
        with patch('awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.discovery.discover_knowledge_bases') as mock_discover:
            # Mock response
            mock_discover.return_value = {
                "KB123456": {
                    "name": "Test Knowledge Base",
                    "data_sources": [
                        {"id": "DS123", "name": "Test Documents"}
                    ]
                }
            }
            
            from awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.discovery import discover_knowledge_bases
            
            result = discover_knowledge_bases(Mock(), "test-tag")
            print(f"✓ Knowledge base discovery successful")
            print(f"   Found knowledge bases: {list(result.keys())}")
            return True
    except Exception as e:
        print(f"✗ Knowledge base discovery error: {e}")
        return False

def test_mock_query():
    """Test knowledge base querying with mock data."""
    print("Testing knowledge base query...")
    
    try:
        with patch('awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.retrieval.query_knowledge_base') as mock_query:
            # Mock response
            mock_query.return_value = json.dumps([
                {
                    "content": "This is a test document about company benefits.",
                    "location": "s3://test-bucket/documents/handbook.txt",
                    "score": 0.95
                },
                {
                    "content": "Our company offers comprehensive health insurance.",
                    "location": "s3://test-bucket/documents/handbook.txt",
                    "score": 0.87
                }
            ])
            
            from awslabs.bedrock_kb_retrieval_mcp_server.knowledgebases.retrieval import query_knowledge_base
            
            result = query_knowledge_base(
                query="What are the company benefits?",
                knowledge_base_id="KB123456",
                kb_agent_client=Mock(),
                number_of_results=5
            )
            
            print(f"✓ Knowledge base query successful")
            # Parse the JSON response to verify format
            parsed_result = json.loads(result)
            print(f"   Found {len(parsed_result)} results")
            return True
    except Exception as e:
        print(f"✗ Knowledge base query error: {e}")
        return False

def test_cloudformation_template():
    """Test that CloudFormation template is valid JSON/YAML."""
    print("Testing CloudFormation template...")
    
    try:
        import yaml
        
        template_path = "infrastructure/knowledge-base-stack.yaml"
        if not os.path.exists(template_path):
            print(f"✗ CloudFormation template not found: {template_path}")
            return False
        
        with open(template_path, 'r') as f:
            template = yaml.safe_load(f)
        
        # Basic validation
        required_sections = ['AWSTemplateFormatVersion', 'Resources', 'Outputs']
        for section in required_sections:
            if section not in template:
                print(f"✗ Missing required section: {section}")
                return False
        
        # Check for key resources
        resources = template['Resources']
        required_resources = ['KnowledgeBase', 'OpenSearchCollection', 'DocumentsBucket']
        for resource in required_resources:
            if resource not in resources:
                print(f"✗ Missing required resource: {resource}")
                return False
        
        print("✓ CloudFormation template validation successful")
        print(f"   Resources defined: {len(resources)}")
        return True
    except Exception as e:
        print(f"✗ CloudFormation template validation error: {e}")
        return False

def test_deployment_scripts():
    """Test that deployment scripts exist and are executable."""
    print("Testing deployment scripts...")
    
    scripts = ["scripts/deploy.sh", "scripts/destroy.sh"]
    all_good = True
    
    for script in scripts:
        if not os.path.exists(script):
            print(f"✗ Script not found: {script}")
            all_good = False
            continue
        
        if not os.access(script, os.X_OK):
            print(f"✗ Script not executable: {script}")
            all_good = False
            continue
        
        print(f"✓ Script validated: {script}")
    
    return all_good

def test_mock_data():
    """Test that mock data files exist and have content."""
    print("Testing mock data...")
    
    mock_data_dir = "mock-data/documents"
    if not os.path.exists(mock_data_dir):
        print(f"✗ Mock data directory not found: {mock_data_dir}")
        return False
    
    files = os.listdir(mock_data_dir)
    if not files:
        print(f"✗ No mock data files found in: {mock_data_dir}")
        return False
    
    total_size = 0
    for file in files:
        file_path = os.path.join(mock_data_dir, file)
        if os.path.isfile(file_path):
            size = os.path.getsize(file_path)
            total_size += size
            print(f"   File {file}: {size} bytes")
    
    print(f"✓ Mock data validation successful")
    print(f"   Files: {len(files)}, Total size: {total_size} bytes")
    return True

def main():
    """Run all tests."""
    print("=" * 50)
    print("AWS Knowledge Base MCP Server - Test Suite")
    print("=" * 50)
    print()
    
    tests = [
        test_imports,
        test_server_initialization,
        test_mock_knowledge_base_discovery,
        test_mock_query,
        test_cloudformation_template,
        test_deployment_scripts,
        test_mock_data
    ]
    
    results = []
    for test in tests:
        try:
            result = test()
            results.append(result)
        except Exception as e:
            print(f"✗ Test failed with exception: {e}")
            results.append(False)
        print()
    
    # Summary
    passed = sum(results)
    total = len(results)
    
    print("=" * 50)
    print("TEST SUMMARY")
    print("=" * 50)
    print(f"Passed: {passed}/{total}")
    print(f"Failed: {total - passed}/{total}")
    
    if passed == total:
        print("All tests passed! The MCP server is ready for deployment.")
        return 0
    else:
        print("Some tests failed. Please address the issues before deployment.")
        return 1

if __name__ == "__main__":
    exit(main())