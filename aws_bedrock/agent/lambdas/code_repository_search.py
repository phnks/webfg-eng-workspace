import json
import subprocess
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
    Search code repositories for specific patterns or files.
    
    Parameters:
    - query: The search query (e.g., function name, pattern)
    - repo_path: Optional path to narrow the search
    - language: Optional language filter (e.g., python, javascript)
    - max_results: Maximum number of results to return (default: 10)
    
    Returns:
    - List of matching files with content snippets
    """
    try:
        # Extract parameters
        query = extract_parameter(event, 'query')
        repo_path = extract_parameter(event, 'repo_path')
        language = extract_parameter(event, 'language')
        max_results = extract_parameter(event, 'max_results')
        
        if not query:
            return wrap_response(400, {
                'status': 'error',
                'message': 'Query parameter is required'
            })
        
        # Validate parameters to prevent command injection
        if query and not re.match(r'^[a-zA-Z0-9_\-\.\s\*\+\?\[\]\(\)\{\}\|\\\^\$]+$', query):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid query format'
            })
            
        if repo_path and not re.match(r'^[a-zA-Z0-9_\-\./]+$', repo_path):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid repo_path format'
            })
            
        if language and not re.match(r'^[a-zA-Z0-9_\-]+$', language):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid language format'
            })
            
        # Set defaults
        if not max_results:
            max_results = 10
        else:
            try:
                max_results = int(max_results)
                if max_results <= 0 or max_results > 50:
                    max_results = 10
            except:
                max_results = 10
        
        # Build the search command
        cmd = "rg --json"
        
        if language:
            cmd += f" -t {language}"
        
        # Add repo path if provided, otherwise search in common directories
        search_path = repo_path if repo_path else "."
        
        # Add the query and path
        cmd += f" \"{query}\" {search_path}"
        
        # Execute search
        try:
            result = subprocess.run(
                cmd, 
                shell=True, 
                capture_output=True, 
                text=True,
                timeout=30  # Set a reasonable timeout
            )
            
            # Parse results
            matches = []
            result_count = 0
            
            # ripgrep JSON output format is one JSON object per line
            for line in result.stdout.splitlines():
                if result_count >= max_results:
                    break
                    
                try:
                    match_data = json.loads(line)
                    if match_data.get('type') == 'match':
                        file_path = match_data.get('data', {}).get('path', {}).get('text', '')
                        line_number = match_data.get('data', {}).get('line_number')
                        line_text = match_data.get('data', {}).get('lines', {}).get('text', '')
                        
                        # Clean up the line text (remove extra whitespace, limit length)
                        if line_text:
                            line_text = line_text.strip()
                            if len(line_text) > 300:
                                line_text = line_text[:297] + "..."
                        
                        matches.append({
                            'file_path': file_path,
                            'line_number': line_number,
                            'line_text': line_text
                        })
                        
                        result_count += 1
                except:
                    continue
            
            # Group results by file for better organization
            files = {}
            for match in matches:
                file_path = match['file_path']
                if file_path not in files:
                    files[file_path] = []
                    
                files[file_path].append({
                    'line_number': match['line_number'],
                    'line_text': match['line_text']
                })
            
            file_results = []
            for file_path, lines in files.items():
                file_results.append({
                    'file_path': file_path,
                    'matches': sorted(lines, key=lambda x: x['line_number'])
                })
                
            return wrap_response(200, {
                'status': 'success',
                'query': query,
                'repo_path': repo_path,
                'language': language,
                'total_matches': len(matches),
                'files': file_results
            })
            
        except subprocess.TimeoutExpired:
            return wrap_response(504, {
                'status': 'error',
                'message': 'Search execution timed out',
                'query': query
            })
        
        except subprocess.SubprocessError as e:
            return wrap_response(500, {
                'status': 'error',
                'message': f"Error executing search command: {str(e)}",
                'query': query
            })
            
    except Exception as e:
        print(f"Error searching code repository: {str(e)}")
        return wrap_response(500, {
            'status': 'error',
            'message': f"Internal server error: {str(e)}"
        })