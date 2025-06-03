import json
import os
import re
import subprocess
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
    Analyze code to provide insights about its structure, quality, and potential issues.
    
    Parameters:
    - file_path: Path to the file to analyze (can be absolute or relative)
    - language: Language of the code (e.g., python, javascript)
    - analysis_type: Type of analysis to perform (structure, quality, security)
    
    Returns:
    - Analysis results including structure, metrics, and potential issues
    """
    try:
        # Extract parameters
        file_path = extract_parameter(event, 'file_path')
        language = extract_parameter(event, 'language')
        analysis_type = extract_parameter(event, 'analysis_type')
        
        if not file_path:
            return wrap_response(400, {
                'status': 'error',
                'message': 'file_path parameter is required'
            })
        
        # Validate parameters to prevent command injection
        if file_path and not re.match(r'^[a-zA-Z0-9_\-\./]+$', file_path):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid file_path format'
            })
            
        if language and not re.match(r'^[a-zA-Z0-9_\-]+$', language):
            return wrap_response(400, {
                'status': 'error',
                'message': 'Invalid language format'
            })
            
        if analysis_type and analysis_type not in ['structure', 'quality', 'security', 'all']:
            analysis_type = 'all'
        elif not analysis_type:
            analysis_type = 'all'
        
        # Check if the file exists
        try:
            if not os.path.isfile(file_path):
                return wrap_response(404, {
                    'status': 'error',
                    'message': f"File not found: {file_path}",
                    'file_path': file_path
                })
        except Exception as e:
            return wrap_response(500, {
                'status': 'error',
                'message': f"Error checking file: {str(e)}",
                'file_path': file_path
            })
            
        # Read the file content
        try:
            with open(file_path, 'r') as f:
                file_content = f.read()
                
            # Limit content size
            if len(file_content) > 50000:
                file_content = file_content[:50000] + "\n... (content truncated)"
                
        except Exception as e:
            return wrap_response(500, {
                'status': 'error',
                'message': f"Error reading file: {str(e)}",
                'file_path': file_path
            })
            
        # Try to detect language if not provided
        if not language:
            if file_path.endswith('.py'):
                language = 'python'
            elif file_path.endswith('.js'):
                language = 'javascript'
            elif file_path.endswith('.ts'):
                language = 'typescript'
            elif file_path.endswith('.go'):
                language = 'go'
            elif file_path.endswith('.java'):
                language = 'java'
            elif file_path.endswith('.sh'):
                language = 'bash'
            else:
                language = 'unknown'
        
        # Perform the analysis
        analysis_results = {}
        
        # File info
        analysis_results['file_info'] = {
            'file_path': file_path,
            'language': language,
            'size_bytes': len(file_content),
            'line_count': len(file_content.splitlines())
        }
        
        # Structure analysis
        if analysis_type in ['structure', 'all']:
            structure_analysis = analyze_structure(file_content, language)
            if structure_analysis:
                analysis_results['structure'] = structure_analysis
        
        # Quality analysis
        if analysis_type in ['quality', 'all']:
            quality_analysis = analyze_quality(file_content, language, file_path)
            if quality_analysis:
                analysis_results['quality'] = quality_analysis
                
        # Security analysis
        if analysis_type in ['security', 'all']:
            security_analysis = analyze_security(file_content, language)
            if security_analysis:
                analysis_results['security'] = security_analysis
        
        return wrap_response(200, {
            'status': 'success',
            'language_detected': language,
            'analysis_results': analysis_results,
            'content_preview': file_content[:500] + ("..." if len(file_content) > 500 else "")
        })
            
    except Exception as e:
        print(f"Error analyzing code: {str(e)}")
        return wrap_response(500, {
            'status': 'error',
            'message': f"Internal server error: {str(e)}"
        })

def analyze_structure(content, language):
    """Analyze the structure of the code."""
    try:
        # Count indentation levels to estimate nesting
        lines = content.splitlines()
        indentation_levels = []
        
        for line in lines:
            if line.strip() == "":
                continue
                
            # Count leading whitespace
            leading_space = len(line) - len(line.lstrip())
            indentation_levels.append(leading_space)
        
        # Calculate average and max nesting levels
        avg_indentation = sum(indentation_levels) / max(len(indentation_levels), 1)
        max_indentation = max(indentation_levels) if indentation_levels else 0
        
        # Basic language-specific structure analysis
        structure = {
            'avg_indentation': avg_indentation,
            'max_indentation': max_indentation
        }
        
        # Language-specific structure detection
        if language == 'python':
            # Count functions and classes
            class_count = len(re.findall(r'^\s*class\s+\w+', content, re.MULTILINE))
            function_count = len(re.findall(r'^\s*def\s+\w+', content, re.MULTILINE))
            
            structure['class_count'] = class_count
            structure['function_count'] = function_count
            
        elif language in ['javascript', 'typescript']:
            # Count functions and classes
            class_count = len(re.findall(r'^\s*class\s+\w+', content, re.MULTILINE))
            class_count += len(re.findall(r'^\s*export\s+class\s+\w+', content, re.MULTILINE))
            
            function_count = len(re.findall(r'^\s*function\s+\w+', content, re.MULTILINE))
            function_count += len(re.findall(r'^\s*const\s+\w+\s*=\s*\(.*\)\s*=>', content, re.MULTILINE))
            function_count += len(re.findall(r'^\s*export\s+function\s+\w+', content, re.MULTILINE))
            
            structure['class_count'] = class_count
            structure['function_count'] = function_count
            
        elif language == 'go':
            # Count functions and structs
            function_count = len(re.findall(r'^\s*func\s+\w+', content, re.MULTILINE))
            struct_count = len(re.findall(r'^\s*type\s+\w+\s+struct', content, re.MULTILINE))
            
            structure['function_count'] = function_count
            structure['struct_count'] = struct_count
            
        elif language == 'java':
            # Count classes and methods
            class_count = len(re.findall(r'^\s*(?:public|private|protected)?\s*class\s+\w+', content, re.MULTILINE))
            method_count = len(re.findall(r'^\s*(?:public|private|protected)?\s*(?:static)?\s*\w+\s+\w+\s*\(', content, re.MULTILINE))
            
            structure['class_count'] = class_count
            structure['method_count'] = method_count
            
        # Common language-agnostic analysis
        comments = len(re.findall(r'^\s*(?://|#|/\*)', content, re.MULTILINE))
        structure['comment_count'] = comments
        
        return structure
    except Exception as e:
        print(f"Error in structure analysis: {str(e)}")
        return {'error': str(e)}

def analyze_quality(content, language, file_path):
    """Analyze the quality of the code."""
    try:
        quality = {}
        
        # Calculate cyclomatic complexity approximation
        # This is a very simple approximation
        decision_points = 0
        
        if language == 'python':
            decision_points += len(re.findall(r'\s+if\s+', content))
            decision_points += len(re.findall(r'\s+elif\s+', content))
            decision_points += len(re.findall(r'\s+for\s+', content))
            decision_points += len(re.findall(r'\s+while\s+', content))
            decision_points += len(re.findall(r'\s+except\s+', content))
            
        elif language in ['javascript', 'typescript', 'java']:
            decision_points += len(re.findall(r'\s+if\s*\(', content))
            decision_points += len(re.findall(r'\s+else if\s*\(', content))
            decision_points += len(re.findall(r'\s+for\s*\(', content))
            decision_points += len(re.findall(r'\s+while\s*\(', content))
            decision_points += len(re.findall(r'\s+catch\s*\(', content))
            decision_points += len(re.findall(r'\s+\?\s+', content))  # Ternary operators
            
        elif language == 'go':
            decision_points += len(re.findall(r'\s+if\s+', content))
            decision_points += len(re.findall(r'\s+else if\s+', content))
            decision_points += len(re.findall(r'\s+for\s+', content))
            decision_points += len(re.findall(r'\s+switch\s+', content))
            
        quality['complexity_score'] = decision_points
        
        # Calculate maintainability metrics
        lines = content.splitlines()
        non_empty_lines = [line for line in lines if line.strip()]
        avg_line_length = sum(len(line) for line in non_empty_lines) / max(len(non_empty_lines), 1)
        max_line_length = max((len(line) for line in non_empty_lines), default=0)
        
        quality['avg_line_length'] = avg_line_length
        quality['max_line_length'] = max_line_length
        
        # Try to run linting if possible
        linting_results = run_linting(file_path, language)
        if linting_results:
            quality['linting'] = linting_results
            
        return quality
    except Exception as e:
        print(f"Error in quality analysis: {str(e)}")
        return {'error': str(e)}

def analyze_security(content, language):
    """Analyze the code for security issues."""
    try:
        security = {}
        
        # Check for common security issues
        security_issues = []
        
        # Hardcoded secrets
        secret_patterns = [
            r'password\s*=\s*["\'](?!\$\{)[^\'"]+["\']',
            r'api[_\s]*key\s*=\s*["\'](?!\$\{)[^\'"]+["\']',
            r'secret\s*=\s*["\'](?!\$\{)[^\'"]+["\']',
            r'token\s*=\s*["\'](?!\$\{)[^\'"]+["\']',
            r'aws_access_key_id\s*=\s*["\'](?!\$\{)[^\'"]+["\']',
            r'aws_secret_access_key\s*=\s*["\'](?!\$\{)[^\'"]+["\']'
        ]
        
        for pattern in secret_patterns:
            matches = re.findall(pattern, content, re.IGNORECASE)
            if matches:
                security_issues.append({
                    'type': 'hardcoded_secret',
                    'severity': 'high',
                    'description': 'Potential hardcoded secret detected',
                    'count': len(matches)
                })
        
        # Check for input validation issues
        if language == 'python':
            if 'eval(' in content:
                security_issues.append({
                    'type': 'unsafe_code_execution',
                    'severity': 'high',
                    'description': 'Use of eval() can lead to code injection',
                    'count': content.count('eval(')
                })
                
            if 'exec(' in content:
                security_issues.append({
                    'type': 'unsafe_code_execution',
                    'severity': 'high',
                    'description': 'Use of exec() can lead to code injection',
                    'count': content.count('exec(')
                })
                
        elif language in ['javascript', 'typescript']:
            if 'eval(' in content:
                security_issues.append({
                    'type': 'unsafe_code_execution',
                    'severity': 'high',
                    'description': 'Use of eval() can lead to code injection',
                    'count': content.count('eval(')
                })
                
            if 'innerHTML' in content:
                security_issues.append({
                    'type': 'xss',
                    'severity': 'medium',
                    'description': 'Use of innerHTML can lead to XSS vulnerabilities',
                    'count': content.count('innerHTML')
                })
                
        # SQL injection patterns
        sql_injection_patterns = [
            r'execute\s*\(\s*["\'][^"\']*\s*\+',
            r'query\s*\(\s*["\'][^"\']*\s*\+',
            r'executeQuery\s*\(\s*["\'][^"\']*\s*\+',
        ]
        
        for pattern in sql_injection_patterns:
            matches = re.findall(pattern, content)
            if matches:
                security_issues.append({
                    'type': 'sql_injection',
                    'severity': 'high',
                    'description': 'Potential SQL injection vulnerability detected',
                    'count': len(matches)
                })
        
        security['issues'] = security_issues
        security['issue_count'] = len(security_issues)
        
        return security
    except Exception as e:
        print(f"Error in security analysis: {str(e)}")
        return {'error': str(e)}

def run_linting(file_path, language):
    """Run language-specific linting if available."""
    try:
        linting_results = []
        
        if language == 'python':
            # Try to run flake8 if available
            try:
                result = subprocess.run(
                    f"flake8 --max-line-length=100 --format=json {file_path}",
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.stdout:
                    try:
                        flake8_results = json.loads(result.stdout)
                        for issue in flake8_results:
                            linting_results.append({
                                'line': issue.get('line_number'),
                                'column': issue.get('column_number'),
                                'message': issue.get('text'),
                                'code': issue.get('code')
                            })
                    except:
                        pass
            except:
                pass
                
        elif language in ['javascript', 'typescript']:
            # Try to run eslint if available
            try:
                result = subprocess.run(
                    f"eslint -f json {file_path}",
                    shell=True,
                    capture_output=True,
                    text=True,
                    timeout=10
                )
                
                if result.stdout:
                    try:
                        eslint_results = json.loads(result.stdout)
                        for file_result in eslint_results:
                            for message in file_result.get('messages', []):
                                linting_results.append({
                                    'line': message.get('line'),
                                    'column': message.get('column'),
                                    'message': message.get('message'),
                                    'rule': message.get('ruleId')
                                })
                    except:
                        pass
            except:
                pass
        
        # Limit the number of results returned
        if len(linting_results) > 20:
            linting_results = linting_results[:20]
            
        return linting_results
    except Exception as e:
        print(f"Error running linting: {str(e)}")
        return []