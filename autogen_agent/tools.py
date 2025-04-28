# filename: autogen_agent/tools.py
import os
import subprocess
import re
import shlex
import logging
from pathlib import Path
from typing import List, Tuple, Optional
import glob

# Configure logging
_LOG = logging.getLogger("autogen-tools")
logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")

# Define the home directory based on the environment variable used in the bot
# This assumes the same BOT_USER logic applies or HOME_DIR is passed appropriately.
# For simplicity, using a placeholder. This should be dynamically set based on the bot's context.
# TODO: Find a way to get HOME_DIR dynamically or pass it during initialization/tool call.
# Using os.path.expanduser("~") as a fallback for now.
HOME_DIR = Path(os.getenv("AGENT_HOME") or os.path.expanduser("~"))

def _resolve_path(relative_path: str) -> Path:
    """Resolves a relative path against the defined HOME_DIR."""
    # Security check: Prevent path traversal attacks
    resolved = (HOME_DIR / relative_path).resolve()
    if not str(resolved).startswith(str(HOME_DIR.resolve())):
        raise ValueError(f"Path traversal detected: '{relative_path}' resolves outside the allowed directory '{HOME_DIR}'")
    return resolved

def execute_command(command: str, working_directory: Path = HOME_DIR) -> str:
    """Executes a shell command."""
    _LOG.info(f"Executing command: {command} in {working_directory}")
    try:
        # Use shell=True cautiously, ensure command sanitization if needed elsewhere.
        # Splitting command using shlex for better handling of quotes and spaces.
        # However, complex shell features (pipes, redirects) might require shell=True.
        # For now, let's try without shell=True first for security.
        # If complex commands are needed, consider shell=True or breaking them down.

        # Using subprocess.run for simplicity and capturing output.
        result = subprocess.run(
            command,
            shell=True, # Enabling shell=True to handle complex commands like pipes/redirects easily
            cwd=working_directory,
            capture_output=True,
            text=True,
            check=False, # Don't raise exception on non-zero exit code
            timeout=300 # 5-minute timeout
        )
        output = f"Exit Code: {result.returncode}\n"
        if result.stdout:
            output += f"Stdout:\n{result.stdout.strip()}\n"
        if result.stderr:
            output += f"Stderr:\n{result.stderr.strip()}\n"
        _LOG.info(f"Command finished. Exit Code: {result.returncode}")
        return output.strip()
    except subprocess.TimeoutExpired:
        _LOG.error(f"Command timed out: {command}")
        return "Error: Command timed out after 5 minutes."
    except Exception as e:
        _LOG.error(f"Error executing command '{command}': {e}", exc_info=True)
        return f"Error executing command: {e}"

def read_file(path: str) -> str:
    """Reads the content of a file."""
    try:
        resolved_path = _resolve_path(path)
        _LOG.info(f"Reading file: {resolved_path}")
        if not resolved_path.is_file():
            return f"Error: Path is not a file or does not exist: {path}"
        # Basic text extraction for common types
        if resolved_path.suffix.lower() == ".pdf":
            # Placeholder: Add PDF extraction logic if needed (requires libraries like PyPDF2)
            return f"Error: PDF reading not implemented yet for {path}. Please install PyPDF2 and add logic."
        elif resolved_path.suffix.lower() == ".docx":
            # Placeholder: Add DOCX extraction logic if needed (requires libraries like python-docx)
            return f"Error: DOCX reading not implemented yet for {path}. Please install python-docx and add logic."
        else:
            # Read as text for other file types
            content = resolved_path.read_text(encoding='utf-8', errors='ignore')
            _LOG.info(f"Successfully read file: {resolved_path}")
            return content
    except ValueError as e: # Catch path traversal error
        _LOG.error(f"Path traversal error reading file '{path}': {e}")
        return f"Error: {e}"
    except Exception as e:
        _LOG.error(f"Error reading file '{path}': {e}", exc_info=True)
        return f"Error reading file: {e}"

def write_to_file(path: str, content: str) -> str:
    """Writes content to a file, overwriting if it exists, creating directories if needed."""
    try:
        resolved_path = _resolve_path(path)
        _LOG.info(f"Writing to file: {resolved_path}")
        # Create parent directories if they don't exist
        resolved_path.parent.mkdir(parents=True, exist_ok=True)
        resolved_path.write_text(content, encoding='utf-8')
        _LOG.info(f"Successfully wrote to file: {resolved_path}")
        return f"Successfully wrote content to {path}"
    except ValueError as e: # Catch path traversal error
        _LOG.error(f"Path traversal error writing file '{path}': {e}")
        return f"Error: {e}"
    except Exception as e:
        _LOG.error(f"Error writing to file '{path}': {e}", exc_info=True)
        return f"Error writing to file: {e}"

def replace_in_file(path: str, diff: str) -> str:
    """Replaces sections of a file based on SEARCH/REPLACE blocks."""
    try:
        resolved_path = _resolve_path(path)
        _LOG.info(f"Replacing content in file: {resolved_path}")
        if not resolved_path.is_file():
            return f"Error: File not found: {path}"

        original_content = resolved_path.read_text(encoding='utf-8')
        current_content = original_content
        replacements_made = 0

        # Regex to find all SEARCH/REPLACE blocks
        pattern = re.compile(r'<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE', re.DOTALL)
        blocks = pattern.findall(diff)

        if not blocks:
            return "Error: No valid SEARCH/REPLACE blocks found in the provided diff."

        for search_block, replace_block in blocks:
            # Ensure exact match including potential trailing newline captured by (.*?)
            # Escape regex special characters in search_block for literal matching
            search_pattern = re.escape(search_block)

            # Perform replacement only once per block
            new_content, num_subs = re.subn(search_pattern, replace_block, current_content, count=1, flags=re.DOTALL)

            if num_subs > 0:
                current_content = new_content
                replacements_made += 1
                _LOG.info(f"Applied replacement in {path}")
            else:
                _LOG.warning(f"Search block not found in {path} (or already replaced):\n---\n{search_block}\n---")
                # Return error immediately if a block fails? Or continue and report?
                # Let's continue and report which blocks failed.
                # Consider adding more context to the error message later.
                # For now, just log it.

        if replacements_made > 0:
            resolved_path.write_text(current_content, encoding='utf-8')
            _LOG.info(f"Successfully applied {replacements_made}/{len(blocks)} replacements to {path}")
            if replacements_made < len(blocks):
                 return f"Successfully applied {replacements_made}/{len(blocks)} replacements to {path}. Some search blocks were not found."
            return f"Successfully applied {replacements_made} replacements to {path}"
        else:
            return f"Error: No replacements made. None of the search blocks matched the content in {path}."

    except ValueError as e: # Catch path traversal error
        _LOG.error(f"Path traversal error replacing in file '{path}': {e}")
        return f"Error: {e}"
    except Exception as e:
        _LOG.error(f"Error replacing content in file '{path}': {e}", exc_info=True)
        return f"Error replacing content in file: {e}"

def list_files(path: str, recursive: bool = False) -> str:
    """Lists files and directories."""
    try:
        resolved_path = _resolve_path(path)
        _LOG.info(f"Listing files in: {resolved_path}, Recursive: {recursive}")
        if not resolved_path.is_dir():
            return f"Error: Path is not a directory or does not exist: {path}"

        entries = []
        if recursive:
            for entry in resolved_path.rglob('*'):
                # Add '/' suffix to directories
                suffix = "/" if entry.is_dir() else ""
                entries.append(f"{entry.relative_to(resolved_path)}{suffix}")
        else:
            for entry in resolved_path.iterdir():
                 # Add '/' suffix to directories
                suffix = "/" if entry.is_dir() else ""
                entries.append(f"{entry.name}{suffix}")

        if not entries:
            return f"Directory is empty: {path}"

        # Sort entries for consistent output
        entries.sort()
        return "\n".join(entries)
    except ValueError as e: # Catch path traversal error
        _LOG.error(f"Path traversal error listing files '{path}': {e}")
        return f"Error: {e}"
    except Exception as e:
        _LOG.error(f"Error listing files in '{path}': {e}", exc_info=True)
        return f"Error listing files: {e}"

def search_files(path: str, regex: str, file_pattern: Optional[str] = None) -> str:
    """Searches for a regex pattern in files within a directory."""
    try:
        resolved_path = _resolve_path(path)
        _LOG.info(f"Searching files in: {resolved_path} for regex: '{regex}' with pattern: '{file_pattern}'")
        if not resolved_path.is_dir():
            return f"Error: Search path is not a directory or does not exist: {path}"

        results = []
        search_pattern = file_pattern if file_pattern else '*'

        # Compile regex for efficiency
        try:
            compiled_regex = re.compile(regex)
        except re.error as e:
            return f"Error: Invalid regex pattern: {e}"

        # Iterate through files matching the pattern
        for filepath in resolved_path.rglob(search_pattern):
            if filepath.is_file():
                try:
                    with open(filepath, 'r', encoding='utf-8', errors='ignore') as f:
                        lines = f.readlines()
                        for i, line in enumerate(lines):
                            if compiled_regex.search(line):
                                # Provide context: line number and the line itself
                                # Add more context (e.g., surrounding lines) if needed
                                context_line = f"{filepath.relative_to(resolved_path)}:{i+1}: {line.strip()}"
                                results.append(context_line)
                                # Limit results per file? Or total results? For now, get all.
                except Exception as e:
                    _LOG.warning(f"Could not read or search file {filepath}: {e}")
                    # Optionally add a message to results indicating the file error
                    # results.append(f"Error searching file {filepath.relative_to(resolved_path)}: {e}")

        if not results:
            return f"No matches found for regex '{regex}' in directory '{path}'" + (f" with pattern '{file_pattern}'." if file_pattern else ".")

        # Limit total results to avoid overwhelming output
        MAX_RESULTS = 100
        if len(results) > MAX_RESULTS:
             return "\n".join(results[:MAX_RESULTS]) + f"\n... (truncated {len(results) - MAX_RESULTS} more results)"
        else:
             return "\n".join(results)

    except ValueError as e: # Catch path traversal error
        _LOG.error(f"Path traversal error searching files '{path}': {e}")
        return f"Error: {e}"
    except Exception as e:
        _LOG.error(f"Error searching files in '{path}': {e}", exc_info=True)
        return f"Error searching files: {e}"


def list_code_definition_names(path: str) -> str:
    """Placeholder for listing code definition names."""
    # This is complex and requires language-specific parsing (like tree-sitter).
    # For now, return a placeholder message.
    # TODO: Implement actual code parsing if necessary, potentially using 'ast' for Python
    # or integrating with external tools/libraries.
    _LOG.warning(f"list_code_definition_names called for path '{path}', but is not fully implemented.")
    return "Error: Listing code definitions is not fully implemented in this Python toolset."

# --- Helper functions or classes for tool integration might go here ---