import json
import boto3
import os
import re
from datetime import datetime

# Function to extract parameter from request
def extract_parameter(event, param_name):
    """Extract a parameter from the event."""
    try:
        body = json.loads(event.get('body', '{}'))
        parameters = body.get('parameters', {})
        return parameters.get(param_name, '')
    except Exception as e:
        print(f"Error extracting parameter {param_name}: {str(e)}")
        return ''

# Function to wrap the response
def wrap_response(status, content):
    """Wrap the response in a consistent format."""
    return {
        'statusCode': status,
        'body': json.dumps({
            'response': content
        }),
        'headers': {
            'Content-Type': 'application/json'
        }
    }

def lambda_handler(event, context):
    """
    Search documentation and resources for relevant content.
    
    Parameters:
    - query: The search query
    - doc_type: Optional documentation type filter
    - max_results: Maximum number of results to return (default: 5)
    
    Returns:
    - List of relevant documentation snippets and references
    """
    try:
        # Extract parameters
        query = extract_parameter(event, 'query')
        doc_type = extract_parameter(event, 'doc_type')
        max_results = extract_parameter(event, 'max_results')
        
        if not query:
            return wrap_response(400, {
                'status': 'error',
                'message': 'Query parameter is required'
            })
        
        # Validate parameters to prevent command injection
        if query and not re.match(r'^[a-zA-Z0-9_\-\.\s\,\'\"\:\;\(\)\[\]\{\}\+\*\?\|\^\$\\\!\/]+$', query):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid query format'
            })
            
        if doc_type and not re.match(r'^[a-zA-Z0-9_\-\.]+$', doc_type):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid doc_type format'
            })
        
        # Set default max results
        if not max_results:
            max_results = 5
        else:
            try:
                max_results = int(max_results)
                if max_results <= 0 or max_results > 20:
                    max_results = 5
            except:
                max_results = 5
        
        # Get knowledge base ID from environment variable
        knowledge_base_id = os.environ.get('KNOWLEDGE_BASE_ID')
        if not knowledge_base_id:
            # Fallback to searching documentation directories if no Knowledge Base is configured
            return search_local_docs(query, doc_type, max_results)
        
        # Search the knowledge base using Bedrock
        try:
            bedrock_kb = boto3.client('bedrock-agent-runtime')
            
            kb_response = bedrock_kb.retrieve(
                knowledgeBaseId=knowledge_base_id,
                retrievalQuery={
                    'text': query
                },
                maxResults=max_results
            )
            
            # Process the search results
            results = []
            for retrieval_result in kb_response.get('retrievalResults', []):
                result_content = retrieval_result.get('content', {}).get('text', '')
                metadata = retrieval_result.get('metadata', {})
                
                source_info = {}
                source_attributes = metadata.get('attributes', [])
                
                for attr in source_attributes:
                    if attr.get('key') == 'source':
                        source_info['source'] = attr.get('value')
                    elif attr.get('key') == 'title':
                        source_info['title'] = attr.get('value')
                    elif attr.get('key') == 'document_type':
                        source_info['document_type'] = attr.get('value')
                
                # Filter by doc_type if specified
                if doc_type and source_info.get('document_type') != doc_type:
                    continue
                
                results.append({
                    'content': result_content,
                    'source': source_info.get('source', 'Unknown'),
                    'title': source_info.get('title', 'Untitled'),
                    'document_type': source_info.get('document_type', 'Unknown'),
                    'relevance_score': retrieval_result.get('score', 0)
                })
            
            return wrap_response(200, {
                'status': 'success',
                'query': query,
                'doc_type': doc_type,
                'result_count': len(results),
                'results': results
            })
            
        except Exception as e:
            print(f"Error searching knowledge base: {str(e)}")
            # Fallback to local search if KB search fails
            return search_local_docs(query, doc_type, max_results)
            
    except Exception as e:
        print(f"Error searching documentation: {str(e)}")
        return wrap_response(500, {
            'status': 'error',
            'message': f"Internal server error: {str(e)}"
        })

def search_local_docs(query, doc_type, max_results):
    """
    Fallback function to search local documentation directories.
    """
    try:
        # Define common documentation directories to search
        doc_dirs = [
            './docs',
            './documentation',
            './README.md',
            './CONTRIBUTING.md',
            './ARCHITECTURE.md'
        ]
        
        # Build grep command to search for the query
        grep_cmd = f"grep -r --include=\"*.md\" --include=\"*.txt\" -l \"{query}\" " + " ".join(doc_dirs)
        
        matching_files = []
        try:
            import subprocess
            result = subprocess.run(
                grep_cmd,
                shell=True,
                capture_output=True,
                text=True,
                timeout=15
            )
            
            if result.returncode == 0 and result.stdout:
                matching_files = result.stdout.strip().split('\n')
        except:
            # If grep fails, proceed with empty results
            pass
        
        # Process found files
        results = []
        for file_path in matching_files[:max_results]:
            file_name = os.path.basename(file_path)
            doc_title = file_name
            
            # Try to determine document type from file path
            if '/api/' in file_path or 'api-' in file_name:
                document_type = 'api-documentation'
            elif '/guides/' in file_path or 'guide-' in file_name:
                document_type = 'user-guide'
            elif '/architecture/' in file_path:
                document_type = 'architecture'
            elif 'README' in file_name:
                document_type = 'readme'
            elif 'CONTRIBUTING' in file_name:
                document_type = 'contributing'
            else:
                document_type = 'general'
                
            # Skip if doc_type filter is applied and doesn't match
            if doc_type and document_type != doc_type:
                continue
                
            # Try to read file content
            try:
                with open(file_path, 'r') as f:
                    content = f.read()
                    
                # Find relevant snippet containing the query
                lines = content.splitlines()
                for i, line in enumerate(lines):
                    if query.lower() in line.lower():
                        start = max(0, i - 3)
                        end = min(len(lines), i + 4)
                        context = '\n'.join(lines[start:end])
                        break
                else:
                    # If query not found in content, use the beginning of the file
                    context = '\n'.join(lines[:7]) if lines else ''
                
                # Extract title from markdown if possible
                title_match = re.search(r'^#\s+(.+)$', content, re.MULTILINE)
                if title_match:
                    doc_title = title_match.group(1)
                    
                results.append({
                    'content': context,
                    'source': file_path,
                    'title': doc_title,
                    'document_type': document_type,
                    'relevance_score': 1.0  # Local search doesn't have scores
                })
            except:
                # Skip files that can't be read
                continue
                
        return wrap_response(200, {
            'status': 'success',
            'query': query,
            'result_count': len(results),
            'results': results,
            'search_method': 'local'  # Indicate this was a local search
        })
            
    except Exception as e:
        print(f"Error in local documentation search: {str(e)}")
        return wrap_response(500, {
            'status': 'error',
            'message': f"Error searching local documentation: {str(e)}"
        })