#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

PROJECT_NAME="super_ai_agent_project"
PYTHON_SCRIPT_NAME="main_agent.py"
VENV_DIR=".venv"

echo "--- Super AI Agent Project Setup ---"

# 1. Create Project Directory
if [ -d "$PROJECT_NAME" ]; then
    echo "Project directory '$PROJECT_NAME' already exists."
    read -p "Do you want to remove it and start fresh? (yes/no): " choice
    if [[ "$choice" == "yes" ]]; then
        echo "Removing existing directory: $PROJECT_NAME"
        rm -rf "$PROJECT_NAME"
    else
        echo "Using existing directory. Some files might be overwritten."
    fi
fi
mkdir -p "$PROJECT_NAME"
cd "$PROJECT_NAME"
echo "Changed directory to $(pwd)"

# 2. Check for Python 3 and Create Virtual Environment
if ! command -v python3 &> /dev/null; then
    echo "ERROR: Python 3 is not installed. Please install Python 3 and try again."
    exit 1
fi

if [ -d "$VENV_DIR" ]; then
    echo "Virtual environment '$VENV_DIR' already exists. Re-using it."
else
    echo "Creating Python virtual environment in '$VENV_DIR'..."
    python3 -m venv "$VENV_DIR"
fi

echo "Activating virtual environment..."
source "$VENV_DIR/bin/activate"
echo "Python version in venv: $(python --version)"

# 3. Install Dependencies
echo "Installing Python dependencies..."
pip install google-generativeai python-dotenv requests

# 4. Create the Python Agent Script
echo "Creating Python agent script: $PYTHON_SCRIPT_NAME..."
cat <<'EOF' > "$PYTHON_SCRIPT_NAME"
import requests
import os
import subprocess
import json
from pathlib import Path
import logging
import venv
import sys
import re
import shutil
import zipfile
import signal
from datetime import datetime
import hashlib
from dotenv import load_dotenv # For .env file

# Attempt to import Gemini SDK
try:
    import google.generativeai as genai
    from google.generativeai.types import HarmCategory, HarmBlockThreshold, Part, Content, FunctionCall, FunctionResponse
except ImportError:
    print("Google Generative AI SDK not installed. Please install it: pip install google-generativeai")
    sys.exit(1)

# Configure logging
logging.basicConfig(
    filename='agent.log',
    level=logging.INFO, # Set to logging.DEBUG for more verbose output
    format='%(asctime)s - %(levelname)s - %(filename)s:%(lineno)d - %(message)s'
)

class SuperAIAgent:
    def __init__(self, gemini_api_key, xai_api_key):
        self.gemini_api_key = gemini_api_key
        self.xai_api_key = xai_api_key
        self.api_key = None
        self.api_url = None
        self.api_model_name = None # e.g., 'gemini' or 'grok'
        self.gemini_model_instance = None
        self.gemini_chat_session = None

        self.project_root = None
        self.language = "python"
        self.venv_path = None
        self.task_results = {} # For Grok's list of tasks
        self.created_files = []
        self.installed_deps = []
        self.linting_results = []
        self.test_results = []
        self.features = []
        self.task_history = [] # Will store more structured data for Gemini
        self.file_hashes = {}
        self.current_iteration = 0
        self.state_file = Path("agent_state.json")
        self.context_file = Path("context_summary.json")
        self.command = None

        self.action_definitions = {
            "create_directory": {"description": "Creates a new directory.", "params": {"path": {"type": "STRING", "description": "Path for the new directory.", "required": True}}},
            "create_venv": {"description": "Creates a Python virtual environment.", "params": {"path": {"type": "STRING", "description": "Directory to create venv in.", "required": True}, "name": {"type": "STRING", "description": "Name of the venv directory (e.g., .venv)."}}},
            "set_language": {"description": "Sets the primary programming language for the project.", "params": {"language": {"type": "STRING", "description": "Language to set (python or nodejs).", "required": True}}},
            "create_file": {"description": "Creates a new file with content.", "params": {"path": {"type": "STRING", "description": "Full path for the new file.", "required": True}, "content": {"type": "STRING", "description": "Content of the file.", "required": True}, "feature": {"type": "STRING", "description": "Associated feature name."}}},
            "modify_file": {"description": "Modifies an existing file with new content.", "params": {"path": {"type": "STRING", "description": "Full path of the file to modify.", "required": True}, "content": {"type": "STRING", "description": "New content for the file.", "required": True}, "feature": {"type": "STRING", "description": "Associated feature name."}}},
            "delete_file": {"description": "Deletes a file.", "params": {"path": {"type": "STRING", "description": "Path of the file to delete.", "required": True}}},
            "install_dependency": {"description": "Installs a project dependency.", "params": {"package": {"type": "STRING", "description": "Name of the package.", "required": True}, "version": {"type": "STRING", "description": "Version of the package (optional)."}, "feature": {"type": "STRING", "description": "Associated feature name."}}},
            "init_git": {"description": "Initializes a Git repository in the specified path.", "params": {"path": {"type": "STRING", "description": "Path to initialize git in.", "required": True}}},
            "git_commit": {"description": "Commits changes to the Git repository.", "params": {"path": {"type": "STRING", "description": "Path of the git repository.", "required": True}, "message": {"type": "STRING", "description": "Commit message.", "required": True}}},
            "run_script": {"description": "Runs a script.", "params": {"path": {"type": "STRING", "description": "Path to the script to run.", "required": True}}},
            "create_test": {"description": "Creates a test file.", "params": {"path": {"type": "STRING", "description": "Path for the new test file.", "required": True}, "content": {"type": "STRING", "description": "Content of the test file.", "required": True}, "feature": {"type": "STRING", "description": "Associated feature name."}}},
            "run_test": {"description": "Runs tests for a specific file or directory.", "params": {"path": {"type": "STRING", "description": "Path to the test file or directory."}}},
            "run_lint": {"description": "Runs a linter on a file or directory.", "params": {"path": {"type": "STRING", "description": "Path to lint.", "required": True}, "tool": {"type": "STRING", "description": "Linter tool (flake8 or eslint).", "required": True}, "fix": {"type": "BOOLEAN", "description": "Attempt to auto-fix issues."}}},
            "generate_docs": {"description": "Generates documentation content for a file.", "params": {"path": {"type": "STRING", "description": "Path for the documentation file.", "required": True}, "content": {"type": "STRING", "description": "Documentation content.", "required": True}, "feature": {"type": "STRING", "description": "Associated feature name."}}},
            "user_clarification_needed": {"description": "Ask the user for clarification if the next step is ambiguous or more information is needed.", "params": {"question": {"type": "STRING", "description": "The question to ask the user for clarification.", "required": True}}}
        }
        self.supported_actions = set(self.action_definitions.keys())
        self.gemini_tools = None

        self.supported_linters = {"python": "flake8", "nodejs": "eslint"}
        self.required_tools_os = {"python": "python3", "git": "git"}
        signal.signal(signal.SIGINT, self.save_state_and_exit)

    def _initialize_gemini_tools(self):
        function_declarations = []
        for action_name, details in self.action_definitions.items():
            params_schema = {}
            required_params = []
            for param_name, param_def in details["params"].items():
                param_type_str = param_def["type"].upper()
                try:
                    gemini_param_type = getattr(genai.types.Type, param_type_str)
                except AttributeError:
                    logging.warning(f"Unsupported Gemini param type '{param_type_str}' for {action_name}.{param_name}. Defaulting to STRING.")
                    gemini_param_type = genai.types.Type.STRING

                params_schema[param_name] = genai.types.Schema(
                    type=gemini_param_type,
                    description=param_def.get("description")
                )
                if param_def.get("required"):
                    required_params.append(param_name)
            
            function_declarations.append(
                genai.types.FunctionDeclaration(
                    name=action_name,
                    description=details["description"],
                    parameters={
                        "type_": genai.types.Type.OBJECT,
                        "properties": params_schema,
                        "required": required_params if required_params else None
                    }
                )
            )
        self.gemini_tools = [genai.types.Tool(function_declarations=function_declarations)]
        logging.info(f"Initialized Gemini tools with {len(function_declarations)} functions.")


    def select_api(self, model_choice):
        model_choice = model_choice.lower().strip()
        if model_choice == "grok":
            if not self.xai_api_key or self.xai_api_key == "DISABLED":
                raise ValueError("XAI_API_KEY (for Grok) is not configured or disabled.")
            self.api_model_name = "grok"
            self.api_key = self.xai_api_key
            self.api_url = "https://api.x.ai/v1/chat/completions" # Verify this URL from Grok docs
            self.gemini_model_instance = None
            self.gemini_chat_session = None
        elif model_choice == "gemini":
            if not self.gemini_api_key or self.gemini_api_key == "DISABLED":
                raise ValueError("GEMINI_API_KEY is not configured or disabled.")
            self.api_model_name = "gemini"
            self.api_key = self.gemini_api_key
            genai.configure(api_key=self.gemini_api_key)
            self._initialize_gemini_tools()
            self.gemini_model_instance = genai.GenerativeModel(
                model_name="gemini-1.5-pro-latest",
                tools=self.gemini_tools,
                safety_settings={ 
                    HarmCategory.HARM_CATEGORY_HARASSMENT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_HATE_SPEECH: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_SEXUALLY_EXPLICIT: HarmBlockThreshold.BLOCK_NONE,
                    HarmCategory.HARM_CATEGORY_DANGEROUS_CONTENT: HarmBlockThreshold.BLOCK_NONE,
                }
            )
            self.gemini_chat_session = self.gemini_model_instance.start_chat(history=[])
            logging.info("Initialized Gemini chat session.")
        else:
            raise ValueError(f"Invalid model choice: {model_choice}. Use 'gemini' or 'grok'.")
        logging.info(f"Selected API model: {self.api_model_name}")


    def save_state_and_exit(self, signum, frame):
        print(f"\nInterrupt received. Saving state...")
        self.save_state()
        print(f"Work paused at {datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')}. State saved. Resume by re-running.")
        sys.exit(0)

    def save_state(self):
        # Ensure project_root and venv_path are strings for JSON
        project_root_str = str(self.project_root) if self.project_root else None
        venv_path_str = str(self.venv_path) if self.venv_path else None

        gemini_history_serializable = []
        if self.api_model_name == "gemini" and self.gemini_chat_session and hasattr(self.gemini_chat_session, 'history'):
            try:
                gemini_history_serializable = [SuperAIAgent._convert_gemini_content_to_json_serializable(c) for c in self.gemini_chat_session.history]
            except Exception as e:
                logging.error(f"Error serializing Gemini history: {e}", exc_info=True)
                gemini_history_serializable = [] # Fallback to empty list

        state = {
            "project_root": project_root_str,
            "language": self.language,
            "venv_path": venv_path_str,
            "task_results": self.task_results,
            "created_files": self.created_files,
            "installed_deps": self.installed_deps,
            "linting_results": self.linting_results,
            "test_results": self.test_results,
            "features": self.features,
            "task_history": self.task_history,
            "file_hashes": self.file_hashes,
            "current_iteration": self.current_iteration,
            "command": self.command,
            "api_model_name": self.api_model_name,
            "last_updated": datetime.now().isoformat(),
            "gemini_chat_history": gemini_history_serializable
        }
        try:
            with open(self.state_file, 'w') as f:
                json.dump(state, f, indent=2)
            logging.info(f"Saved state to {self.state_file}")
            context = self.get_context_summary() # Generate fresh context summary
            with open(self.context_file, 'w') as f:
                json.dump(context, f, indent=2)
            logging.info(f"Saved context summary to {self.context_file}")
        except Exception as e:
            logging.error(f"Error during save_state file operations: {e}", exc_info=True)


    @staticmethod
    def _convert_gemini_content_to_json_serializable(content_obj):
        parts_serializable = []
        for part in content_obj.parts:
            part_dict = {}
            if hasattr(part, 'text') and part.text: # Check if text attribute exists and is not empty
                part_dict["text"] = part.text
            if hasattr(part, 'function_call') and part.function_call and part.function_call.name:
                 part_dict["function_call"] = {"name": part.function_call.name, "args": dict(part.function_call.args)}
            if hasattr(part, 'function_response') and part.function_response and part.function_response.name:
                # Ensure response is a dict for JSON
                response_data = part.function_response.response
                if not isinstance(response_data, dict):
                    response_data = {"result": str(response_data)} # Convert non-dict to a dict
                part_dict["function_response"] = {"name": part.function_response.name, "response": response_data}
            if part_dict: 
                 parts_serializable.append(part_dict)
        return {"role": content_obj.role, "parts": parts_serializable}

    @staticmethod
    def _reconstruct_gemini_history_from_state(history_json_list):
        history_obj_list = []
        for item_json in history_json_list:
            reconstructed_parts = []
            for part_json in item_json.get("parts", []):
                if "text" in part_json:
                    reconstructed_parts.append(Part(text=part_json["text"]))
                elif "function_call" in part_json:
                    fc_data = part_json["function_call"]
                    reconstructed_parts.append(Part(function_call=FunctionCall(name=fc_data["name"], args=fc_data["args"])))
                elif "function_response" in part_json:
                    fr_data = part_json["function_response"]
                    # Ensure response part is correctly formed for the SDK
                    response_content = fr_data["response"]
                    if not isinstance(response_content, dict): # SDK expects a dict here
                        response_content = {"data": response_content} # Wrap if not a dict
                    reconstructed_parts.append(Part(function_response=FunctionResponse(name=fr_data["name"], response=response_content)))
            if reconstructed_parts: # Only add if parts were reconstructed
                history_obj_list.append(Content(role=item_json["role"], parts=reconstructed_parts))
        return history_obj_list


    def load_state(self):
        if not self.state_file.exists():
            return False
        try:
            with open(self.state_file, 'r') as f:
                state = json.load(f)
            
            project_root_str = state.get("project_root")
            self.project_root = Path(project_root_str) if project_root_str else None
            
            self.language = state.get("language", "python")
            
            venv_path_str = state.get("venv_path")
            self.venv_path = Path(venv_path_str) if venv_path_str else None
            
            self.task_results = state.get("task_results", {})
            self.created_files = state.get("created_files", [])
            self.installed_deps = state.get("installed_deps", [])
            self.linting_results = state.get("linting_results", [])
            self.test_results = state.get("test_results", [])
            self.features = state.get("features", [])
            self.task_history = state.get("task_history", [])
            self.file_hashes = state.get("file_hashes", {})
            self.current_iteration = state.get("current_iteration", 0)
            self.command = state.get("command")
            loaded_api_model_name = state.get("api_model_name")

            if loaded_api_model_name:
                try:
                    self.select_api(loaded_api_model_name) # This will set up Gemini model and tools
                except ValueError as e:
                    logging.warning(f"Failed to re-initialize API model '{loaded_api_model_name}' from state: {e}. User might need to re-select.")
                    self.api_model_name = None # Mark as unselected
            
            if self.api_model_name == "gemini" and self.gemini_model_instance:
                gemini_chat_history_json = state.get("gemini_chat_history", [])
                if gemini_chat_history_json: # Only reconstruct if there's history
                    reconstructed_history = SuperAIAgent._reconstruct_gemini_history_from_state(gemini_chat_history_json)
                    self.gemini_chat_session = self.gemini_model_instance.start_chat(history=reconstructed_history)
                    logging.info(f"Reconstructed Gemini chat history with {len(reconstructed_history)} items.")
                else: # No history, start fresh chat session
                    self.gemini_chat_session = self.gemini_model_instance.start_chat(history=[])
                    logging.info("No Gemini chat history in state, started fresh chat session.")


            if self.project_root and not self.project_root.exists():
                logging.warning(f"Project root {self.project_root} from state does not exist.")
            logging.info(f"Loaded state from {self.state_file}")
            return True
        except Exception as e:
            logging.error(f"Failed to load state: {e}", exc_info=True)
            # Optionally, clear broken state or offer to start fresh
            # self.clear_state() 
            return False

    def clear_state(self):
        if self.state_file.exists():
            try: self.state_file.unlink()
            except OSError as e: logging.error(f"Error removing state file: {e}")
            logging.info("State file cleared")
        if self.context_file.exists():
            try: self.context_file.unlink()
            except OSError as e: logging.error(f"Error removing context file: {e}")
            logging.info("Context summary file cleared")

    def get_file_summary(self, file_path_str):
        try:
            # Ensure project_root is a Path object if it exists
            proj_root_path = Path(self.project_root) if self.project_root else Path.cwd()
            
            # Resolve the file_path_str relative to project_root if it's not absolute
            path_obj = Path(file_path_str)
            if not path_obj.is_absolute():
                path_obj = (proj_root_path / path_obj).resolve()
            else:
                path_obj = path_obj.resolve()


            if not path_obj.is_file():
                return {"path": str(path_obj), "summary": "File not found or is a directory"}
            
            with open(path_obj, 'r', encoding='utf-8', errors='ignore') as f:
                content = f.read()
            
            file_hash = hashlib.md5(content.encode('utf-8')).hexdigest()
            # Use resolved, absolute path string for file_hashes dictionary key
            self.file_hashes[str(path_obj)] = file_hash

            if len(content) < 1000:
                return {"path": str(path_obj), "content_preview": content[:500] + ("..." if len(content)>500 else ""), "hash": file_hash}

            lines = content.splitlines()
            summary = f"File Path: {path_obj}\n"
            summary += "First 5 lines:\n" + "\n".join(lines[:5]) + "\n"
            if len(lines) > 10:
                 summary += "...\nLast 5 lines:\n" + "\n".join(lines[-5:]) + "\n"

            signatures = [line.strip() for line in lines if line.strip().startswith(("def ", "class ", "function ", "const ", "var ", "let "))]
            if signatures:
                summary += "Key definitions preview (up to 5):\n" + "\n".join(signatures[:5]) + "\n"
            return {"path": str(path_obj), "summary": summary, "hash": file_hash}
        except Exception as e:
            logging.error(f"Failed to summarize file {file_path_str} (resolved: {path_obj if 'path_obj' in locals() else 'N/A'}): {e}", exc_info=True)
            return {"path": str(file_path_str), "summary": f"Error summarizing file: {e}"}


    def get_context_summary(self):
        completeness = self.assess_project_completeness()
        
        key_files_paths_to_summarize = []
        if self.project_root and self.project_root.exists():
            # Get all files, then filter
            all_project_files = [str(f.resolve()) for f in self.project_root.rglob("*") if f.is_file() and ".git" not in f.parts and VENV_DIR not in f.parts] # Exclude .git and venv
            
            # Prioritize main application files and tests
            priority_patterns = ["app.", "main.", "index.", "server.", "test_", "spec."]
            readme_patterns = ["README.md", "PROJECT_SUMMARY.md"]

            priority_files = [f for f in all_project_files if any(p in Path(f).name for p in priority_patterns) or Path(f).name in readme_patterns]
            
            # Add other recently created/modified files if space allows, preferring those tracked by the agent
            other_tracked_files = [str(Path(self.project_root / f).resolve()) for f in self.created_files if Path(self.project_root / f).exists()]
            
            # Combine and unique, then sort by modification time (most recent first)
            # Be careful with Path(f).stat() if f could be non-existent due to state/reality mismatch
            combined_files = list(set(priority_files + other_tracked_files))
            
            def get_mtime_safe(f_path_str):
                try:
                    return Path(f_path_str).stat().st_mtime
                except FileNotFoundError:
                    return 0 # Oldest if not found

            combined_files.sort(key=get_mtime_safe, reverse=True)
            key_files_paths_to_summarize = combined_files[:10] # Max 10 file summaries
        else: # Fallback if project_root is not properly set
            key_files_paths_to_summarize = sorted(
                list(set(self.created_files)),
                key=lambda x: Path(x).stat().st_mtime if Path(x).exists() else 0,
                reverse=True
            )[:5]

        file_summaries = [self.get_file_summary(f) for f in key_files_paths_to_summarize]

        recent_actions_for_summary = []
        for task_entry in self.task_history[-5:]:
            entry_summary = {"action": task_entry.get("action"), "success": task_entry.get("success")}
            # Handle both dict 'task' (old format) and direct 'args' (new format)
            task_details = task_entry.get("task", task_entry.get("args", {}))
            if isinstance(task_details, dict) and task_details.get("path"):
                entry_summary["path"] = task_details.get("path")
            if not task_entry.get("success"):
                entry_summary["error"] = str(task_entry.get("error"))[:200] # Truncate error
            recent_actions_for_summary.append(entry_summary)

        project_structure_preview = []
        if self.project_root and self.project_root.exists():
            count = 0
            for item in self.project_root.rglob('*'):
                if ".git" in item.parts or VENV_DIR in item.parts: continue # Skip .git and venv
                if count >= 20: project_structure_preview.append("... (and more)"); break
                
                rel_path = item.relative_to(self.project_root)
                if item.is_dir():
                    project_structure_preview.append(f"DIR : {rel_path}/")
                else:
                    project_structure_preview.append(f"FILE: {rel_path}")
                count +=1
        
        return {
            "metadata": {
                "project_root": str(self.project_root) if self.project_root else "Not set",
                "language": self.language,
                "features_implemented": self.features,
                "dependencies_installed": self.installed_deps,
                "current_iteration": self.current_iteration,
                "original_user_command": self.command,
                "current_datetime": datetime.now().isoformat()
            },
            "project_completeness_assessment": completeness,
            "project_directory_structure_preview": project_structure_preview,
            "key_file_summaries": file_summaries,
            "recent_actions_history": recent_actions_for_summary,
            "outstanding_issues": completeness["issues"],
            "suggested_next_features": completeness["missing_features"]
        }

    def assess_project_completeness(self):
        score = 0
        issues = []
        if not self.project_root or not self.project_root.exists():
            issues.append("Project root directory not found or not created.")
            return {"score": 0, "issues": issues, "is_complete": False, "missing_features": ["project_setup"]}

        main_script_found = False
        main_patterns_py = ["app.py", "main.py", "server.py"]
        main_patterns_js = ["app.js", "main.js", "index.js", "server.js"]
        for item in self.project_root.iterdir(): # Check only top level for main script
            if item.is_file():
                if self.language == "python" and item.name in main_patterns_py: main_script_found = True; break
                if self.language == "nodejs" and item.name in main_patterns_js: main_script_found = True; break
        if main_script_found: score += 20
        else: issues.append(f"No main application script (e.g., {'/'.join(main_patterns_py if self.language=='python' else main_patterns_js)}) found in project root.")

        test_files_found = False
        for item in self.project_root.rglob('*'): # Search recursively for tests
            if item.is_file():
                if self.language == "python" and (item.name.startswith("test_") and item.name.endswith(".py")): test_files_found = True; break
                if self.language == "nodejs" and (item.name.endswith(".test.js") or item.name.endswith(".spec.js")): test_files_found = True; break
        if test_files_found: score += 20
        else: issues.append("No test files found in the project.")
        
        passing_tests = sum(1 for result_str in self.test_results if isinstance(result_str, str) and ("passed" in result_str.lower() or "0 failures" in result_str or "ok" in result_str.lower()))
        if passing_tests > 0 and test_files_found: score += 20
        elif test_files_found and not self.test_results: issues.append("Test files exist, but no test results recorded. Run tests.")
        elif test_files_found and passing_tests == 0 : issues.append("Tests exist but none are passing or results are unclear/unavailable.")


        linting_passed = all(isinstance(r, str) and ("passed" in r.lower() or "fixed" in r.lower() or "no issues found" in r.lower() or "0 errors" in r.lower()) for r in self.linting_results)
        if self.linting_results and linting_passed : score += 10
        elif self.linting_results and not linting_passed: issues.append("Linting issues detected in last run.")
        # else: issues.append("Linting has not been run or results are unavailable.")

        production_features_checklist = {
            "authentication": 10, "database_integration": 10, "error_handling_logging": 5,
            "configuration_management": 5, "api_documentation": 5 
        }
        implemented_score = 0; missing_features_list = []
        for feat, points in production_features_checklist.items():
            if feat in self.features: implemented_score += points
            else: missing_features_list.append(feat)
        score += implemented_score

        if not (self.project_root / ".git").exists(): issues.append("Project is not under Git version control.")
        else: score += 5
        
        return {"score": min(score, 100), "issues": issues, "is_complete": score >= 80 and not issues, "missing_features": missing_features_list}

    def validate_environment(self):
        missing_tools = []
        for tool_key, cmd_executable_name in self.required_tools_os.items():
            if not shutil.which(cmd_executable_name):
                missing_tools.append(tool_key)
        if self.language == "nodejs" and not shutil.which("node"): # npm is usually with node
            missing_tools.append("node/npm")
        if missing_tools:
            logging.error(f"Missing OS tools: {', '.join(missing_tools)}. Please install them and add to PATH.")
            return False
        return True

    def _validate_action_params(self, action_name, args):
        if action_name not in self.action_definitions:
            logging.error(f"Unknown action: {action_name}")
            return False
        
        action_def_params = self.action_definitions[action_name]["params"]
        required_params_defined = {k for k, v in action_def_params.items() if v.get("required")}
        
        for req_param in required_params_defined:
            if req_param not in args or args[req_param] is None or (isinstance(args[req_param], str) and not args[req_param].strip()):
                logging.error(f"Missing or empty required parameter '{req_param}' for action '{action_name}'. Provided args: {args}")
                return False

        for param_name, param_value in args.items():
            if param_name in action_def_params:
                expected_type_str = action_def_params[param_name]["type"].upper()
                
                type_mismatch = False
                if expected_type_str == "STRING" and not isinstance(param_value, str): type_mismatch = True
                elif expected_type_str == "BOOLEAN" and not isinstance(param_value, bool): type_mismatch = True
                elif expected_type_str == "NUMBER" and not isinstance(param_value, (int, float)): type_mismatch = True
                # Add ARRAY, OBJECT checks if needed, e.g. isinstance(param_value, list) for ARRAY

                if type_mismatch:
                    logging.warning(f"Type mismatch for parameter '{param_name}' in action '{action_name}'. Expected {expected_type_str}, got {type(param_value).__name__}. Value: '{param_value}'")
                    # Allow execution for now, but this might be a source of errors. Could convert or fail.
                    # For example, if boolean is expected but string "true" is given by LLM.

        path_arg_value = args.get("path")
        if path_arg_value and isinstance(path_arg_value, str):
            # Basic check for obviously problematic paths. Normalization happens in action handlers.
            if ".." in path_arg_value.split(os.sep): # Disallow ".." for path traversal attempts in relative paths
                # More robust checks happen in action handlers using project_root
                logging.warning(f"Path parameter '{path_arg_value}' for action '{action_name}' contains '..'. This will be resolved against project root but proceed with caution.")
            if re.search(r'[<>:"|?*\x00-\x1F]', path_arg_value):
                logging.error(f"Invalid characters in path parameter '{path_arg_value}' for action '{action_name}'")
                return False
        return True


    def install_linter(self, tool_name):
        if not self.project_root:
            logging.error("Cannot install linter: project root not set.")
            return False
        try:
            cmd_list = []
            if tool_name == "flake8" and self.language == "python":
                cmd_list = [self.get_venv_python(), "-m", "pip", "install", "flake8", "autopep8"]
            elif tool_name == "eslint" and self.language == "nodejs":
                cmd_list = ["npm", "install", "--save-dev", "eslint"] # Install locally
            else:
                logging.warning(f"Linter {tool_name} not supported for language {self.language} or unknown.")
                return False

            logging.info(f"Attempting to install linter: {' '.join(cmd_list)} in {self.project_root}")
            result = subprocess.run(cmd_list, cwd=self.project_root, capture_output=True, text=True, check=False)

            if result.returncode != 0:
                err_msg = f"Failed to install {tool_name}. RC: {result.returncode}\nStdout: {result.stdout}\nStderr: {result.stderr}"
                logging.error(err_msg)
                raise RuntimeError(err_msg)
            
            logging.info(f"Successfully installed/verified linter: {tool_name}")
            return True
        except Exception as e:
            logging.error(f"Exception during linter installation for {tool_name}: {e}", exc_info=True)
            return False


    def send_to_api(self, user_message_content, is_retry=False, failed_task_context=None):
        context_summary = self.get_context_summary()
        logging.info(f"Preparing to send to {self.api_model_name}. Iteration: {self.current_iteration}.")
        
        if self.api_model_name == "gemini":
            if not self.gemini_chat_session:
                logging.error("Gemini chat session not initialized.")
                return "Error: Gemini session not ready."

            # System prompt (can be set once at chat start, or reinforced)
            # For this model, let's ensure it's part of the context for each significant turn
            # if not self.gemini_chat_session.history or self.gemini_chat_session.history[0].role != "system": # A bit hacky check
            #    # This SDK version might not directly support a "system" role in history.
            #    # It's often part of the initial model configuration or the first user message.
            #    pass # System instructions are part of the model config or first user message.


            # Construct a user message with context hints
            gemini_user_prompt = (
                f"Current user request: \"{user_message_content}\"\n"
                f"Overall project goal: \"{self.command}\"\n"
                f"Project language: {self.language}. Project root: {self.project_root}.\n"
                f"Consider the following project context:\n"
                f"Key Issues: {context_summary['outstanding_issues']}\n"
                f"Missing Features: {context_summary['suggested_next_features']}\n"
                f"Recent Actions: {context_summary['recent_actions_history']}\n"
                # f"File Summaries (abbreviated): {json.dumps(context_summary['key_file_summaries'], indent=2)[:1000]}\n" # Can be very verbose
            )
            if is_retry:
                gemini_user_prompt += "This is a retry. Please analyze the previous attempt and provide a corrected course of action.\n"
            if failed_task_context:
                gemini_user_prompt += f"A previous action failed: {json.dumps(failed_task_context)}\nPlease try to recover or suggest an alternative.\n"

            gemini_user_prompt += (
                "\nBased on the above and our conversation history, decide the best next single action "
                "(tool to call) to progress towards the goal. If the goal seems met or you need more info, "
                "use the 'user_clarification_needed' tool or provide a textual summary."
            )
            
            logging.info(f"Sending to Gemini (prompt starts with): {gemini_user_prompt[:300]}...")
            logging.debug(f"Full Gemini prompt for this turn:\n{gemini_user_prompt}\n---End of Gemini Prompt---")


            try:
                # The history is managed by the chat_session object
                response = self.gemini_chat_session.send_message(gemini_user_prompt)
                logging.debug(f"Raw Gemini response object: {response}")
                if not response.candidates:
                    logging.warning(f"Gemini response has no candidates. Feedback: {response.prompt_feedback if hasattr(response, 'prompt_feedback') else 'N/A'}")
                    return f"Error: Gemini response blocked or empty. Feedback: {response.prompt_feedback if hasattr(response, 'prompt_feedback') else 'No details'}"
                return response
            except Exception as e:
                logging.error(f"Gemini API request failed: {e}", exc_info=True)
                # Try to get feedback if available from the exception (some SDK errors might have it)
                feedback = "No specific feedback available."
                if hasattr(e, 'args') and e.args:
                    try:
                        # Example: google.api_core.exceptions.InvalidArgument: 400 Request contains an invalid argument.
                        # Sometimes details are in e.args[0] if it's a custom exception string.
                        # Or if it's a google.generativeai.client. generazione_error. générationsError (or similar)
                        # it might have more structured info. This is a bit of guesswork.
                        if "prompt_feedback" in str(e.args[0]).lower(): # Very rough check
                             feedback = str(e.args[0])
                    except: pass
                return f"Error: Gemini API call failed. {e}. Feedback: {feedback}"


        elif self.api_model_name == "grok":
            grok_system_prompt = """
You are an expert coder AI. Your goal is to help build a software project based on user commands and provided context.
You must respond with a JSON object containing a list of "tasks". Each task should have an "action" (from the supported list)
and "parameters" (a dictionary of arguments for that action). Stick to the provided actions and parameter names.
Prioritize addressing issues and missing features from the context.
Example Task: { "action": "create_file", "parameters": {"path": "app/main.py", "content": "print('hello')", "feature": "core_logic" }}
"""
            grok_user_prompt = f"""
User Command: '{user_message_content}'
Overall Project Goal: '{self.command}'
Current Iteration: {self.current_iteration}
Project Context Summary:
{json.dumps(context_summary, indent=2)}

Supported Actions and their parameters (use these exact names):
{json.dumps({name: details['params'] for name, details in self.action_definitions.items()}, indent=2)}
"""
            if is_retry: grok_user_prompt += "\nThis is a retry. Please provide a corrected list of tasks, carefully considering the previous failure."
            if failed_task_context: grok_user_prompt += f"\nA previous task failed: {json.dumps(failed_task_context)}. Plan tasks to recover or work around this."
            grok_user_prompt += "\nNow, generate the JSON response with the list of tasks:"

            try:
                payload = {
                    "model": "mixtral-8x7b-32768", # Or "grok-1" if you have access
                    "messages": [
                        {"role": "system", "content": grok_system_prompt},
                        {"role": "user", "content": grok_user_prompt}
                    ],
                    "temperature": 0.2, # Low temperature for more deterministic tasks
                    "response_format": {"type": "json_object"} # Request JSON output if Grok API supports it
                }
                headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json", "X-API-Key": self.api_key} # Some APIs use X-API-Key
                
                logging.info(f"Sending to Grok API URL: {self.api_url}")
                logging.debug(f"Grok request payload (user prompt part): {grok_user_prompt[:300]}...")

                api_response = requests.post(self.api_url, json=payload, headers=headers, timeout=180)
                api_response.raise_for_status() # Will raise HTTPError for bad responses (4xx or 5xx)
                
                result_json = api_response.json()
                logging.debug(f"Grok raw response: {json.dumps(result_json, indent=2)}")

                tasks_json_str = result_json.get("choices", [{}])[0].get("message", {}).get("content", "")
                if not tasks_json_str:
                    logging.error("Grok response missing expected content for tasks.")
                    return {"tasks": []} 

                parsed_tasks_outer = json.loads(tasks_json_str) # Expects {"tasks": [...]}
                if "tasks" not in parsed_tasks_outer or not isinstance(parsed_tasks_outer["tasks"], list):
                    logging.error(f"Grok response JSON does not contain a 'tasks' list. Got: {tasks_json_str}")
                    return {"tasks": []}
                return parsed_tasks_outer # Return the dict { "tasks": [...] }
            except requests.RequestException as e:
                logging.error(f"Grok API request failed: {e}", exc_info=True)
                if hasattr(e, 'response') and e.response is not None: logging.error(f"Grok error response content: {e.response.text}")
                return {"tasks": []} 
            except (KeyError, IndexError, json.JSONDecodeError) as e:
                logging.error(f"Failed to parse Grok response: {e}. Response text: {tasks_json_str if 'tasks_json_str' in locals() else 'N/A'}", exc_info=True)
                return {"tasks": []}
        else:
            logging.error(f"API model '{self.api_model_name}' not supported in send_to_api.")
            return None

    def get_venv_python(self):
        if self.venv_path and self.venv_path.exists():
            python_exe = "python.exe" if sys.platform == "win32" else "python"
            scripts_dir = "Scripts" if sys.platform == "win32" else "bin"
            venv_python_path = self.venv_path / scripts_dir / python_exe
            if venv_python_path.exists():
                return str(venv_python_path)
        logging.warning("Virtual environment Python not found or venv not set, using system Python.")
        return sys.executable 

    def _resolve_path(self, path_str):
        """Resolves a path string relative to project_root if not absolute."""
        if not self.project_root:
            # If project_root is not set, this is problematic. Default to CWD for now.
            # This should ideally be caught earlier or project_root ensured.
            logging.warning("Project root not set. Resolving path relative to current working directory.")
            base_path = Path.cwd()
        else:
            base_path = self.project_root

        p = Path(path_str)
        if p.is_absolute():
            # If absolute, ensure it's within project_root for safety
            if self.project_root and not str(p.resolve()).startswith(str(self.project_root.resolve())):
                 raise ValueError(f"Path {p} is absolute and outside project root {self.project_root}")
            return p.resolve()
        return (base_path / p).resolve()


    def _action_create_directory(self, path, **kwargs):
        full_path = self._resolve_path(path)
        full_path.mkdir(parents=True, exist_ok=True)
        return f"Directory {full_path} created/ensured."

    def _action_create_venv(self, path, name=".venv", **kwargs):
        # 'path' here is the parent directory for the venv
        parent_dir_for_venv = self._resolve_path(path)
        venv_actual_path = parent_dir_for_venv / name
        
        parent_dir_for_venv.mkdir(parents=True, exist_ok=True)
        venv.create(venv_actual_path, with_pip=True)
        self.venv_path = venv_actual_path.resolve()
        return f"Virtual environment created at {self.venv_path}."

    def _action_set_language(self, language, **kwargs):
        lang = language.lower()
        if lang not in ["python", "nodejs"]:
            raise ValueError("Unsupported language. Choose 'python' or 'nodejs'.")
        self.language = lang
        return f"Project language set to {self.language}."

    def _action_create_file(self, path, content, feature=None, **kwargs):
        full_path = self._resolve_path(path)
        full_path.parent.mkdir(parents=True, exist_ok=True)
        with open(full_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        # Use string representation of resolved path for consistency in lists/dicts
        path_str_resolved = str(full_path)
        if path_str_resolved not in self.created_files: self.created_files.append(path_str_resolved)
        if feature and feature not in self.features: self.features.append(feature)
        self.file_hashes[path_str_resolved] = hashlib.md5(content.encode('utf-8')).hexdigest()
        return f"File {full_path} created (feature: {feature or 'N/A'})."

    def _action_modify_file(self, path, content, feature=None, **kwargs):
        full_path = self._resolve_path(path)
        if not full_path.exists():
            logging.warning(f"File {full_path} to modify does not exist, creating it instead.")
            # Fall through to write, effectively creating it.
        
        full_path.parent.mkdir(parents=True, exist_ok=True) # Ensure parent exists
        with open(full_path, 'w', encoding='utf-8') as f:
            f.write(content)
        
        path_str_resolved = str(full_path)
        if path_str_resolved not in self.created_files: self.created_files.append(path_str_resolved)
        if feature and feature not in self.features: self.features.append(feature)
        self.file_hashes[path_str_resolved] = hashlib.md5(content.encode('utf-8')).hexdigest()
        return f"File {full_path} modified (feature: {feature or 'N/A'})."

    def _action_delete_file(self, path, **kwargs):
        full_path = self._resolve_path(path)
        path_str_resolved = str(full_path)
        if full_path.exists() and full_path.is_file():
            full_path.unlink()
            self.created_files = [f for f in self.created_files if f != path_str_resolved]
            if path_str_resolved in self.file_hashes: del self.file_hashes[path_str_resolved]
            return f"File {full_path} deleted."
        return f"File {full_path} not found or not a file, nothing to delete."

    def _action_install_dependency(self, package, version=None, feature=None, **kwargs):
        if not self.project_root: raise ValueError("Project root not set for dependency installation.")
        
        cmd_list = []; dep_str = ""
        if self.language == "python":
            cmd_list = [self.get_venv_python(), "-m", "pip", "install"]
            dep_str = f"{package}=={version}" if version else package
            cmd_list.append(dep_str)
        elif self.language == "nodejs":
            cmd_list = ["npm", "install", "--save-dev" if "test" in package or "lint" in package else "--save"]
            dep_str = f"{package}@{version}" if version else package
            cmd_list.append(dep_str)
        else:
            raise ValueError(f"Unsupported language for dependency install: {self.language}")

        result = subprocess.run(cmd_list, cwd=self.project_root, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            if dep_str not in self.installed_deps: self.installed_deps.append(dep_str)
            if feature and feature not in self.features: self.features.append(feature)
            return f"Installed {dep_str} (feature: {feature or 'N/A'}). Output: {result.stdout[:200]}"
        else:
            raise RuntimeError(f"Failed to install {dep_str}. Error: {result.stderr or result.stdout}")

    def _action_init_git(self, path=".", **kwargs): # Default path to project root
        repo_path = self._resolve_path(path) # path is relative to project_root or absolute
        if not repo_path.exists(): repo_path.mkdir(parents=True, exist_ok=True)
        
        # Check if already a git repo
        if (repo_path / ".git").exists():
            return f"Git repository already exists in {repo_path}."

        result = subprocess.run(["git", "init"], cwd=repo_path, capture_output=True, text=True, check=False)
        if result.returncode == 0:
            return f"Git repository initialized in {repo_path}."
        else:
            raise RuntimeError(f"Git init failed in {repo_path}: {result.stderr or result.stdout}")

    def _action_git_commit(self, message, path=".", **kwargs): # Default path to project root
        repo_path = self._resolve_path(path)
        
        status_result = subprocess.run(["git", "status", "--porcelain"], cwd=repo_path, capture_output=True, text=True, check=False)
        if not status_result.stdout.strip() and not Path(repo_path / ".git").exists(): # No .git means nothing to add/commit
            return self._action_init_git(path=str(repo_path.relative_to(self.project_root) if self.project_root else repo_path)) + " Then, please try commit again."
        elif not status_result.stdout.strip():
             return f"No changes to commit in {repo_path}."


        add_result = subprocess.run(["git", "add", "."], cwd=repo_path, capture_output=True, text=True, check=False)
        if add_result.returncode != 0:
            logging.warning(f"git add . in {repo_path} might have failed or had issues: {add_result.stderr or add_result.stdout}")

        commit_result = subprocess.run(["git", "commit", "-m", message], cwd=repo_path, capture_output=True, text=True, check=False)
        if commit_result.returncode == 0:
            return f"Committed changes in {repo_path} with message: '{message}'. Output: {commit_result.stdout[:200]}"
        else:
            if "nothing to commit" in commit_result.stdout.lower() or "no changes added to commit" in commit_result.stdout.lower():
                return f"No effective changes to commit in {repo_path} for message: '{message}'."
            raise RuntimeError(f"Git commit failed in {repo_path}: {commit_result.stderr or commit_result.stdout}")


    def _action_run_script(self, path, **kwargs):
        script_full_path = self._resolve_path(path)
        if not script_full_path.exists(): raise FileNotFoundError(f"Script {script_full_path} not found.")

        cmd_list = []
        if self.language == "python":
            cmd_list = [self.get_venv_python(), str(script_full_path)]
        elif self.language == "nodejs":
            cmd_list = ["node", str(script_full_path)]
        else:
            raise ValueError(f"Unsupported language for running script: {self.language}")

        # Ensure script is executable (especially for Python scripts not run via 'python interpreter_path script_path')
        # However, we are explicitly calling the interpreter, so chmod might not be strictly necessary here.
        # if self.language == "python": os.chmod(script_full_path, 0o755)


        # Run from project root directory
        run_cwd = self.project_root if self.project_root else script_full_path.parent

        result = subprocess.run(cmd_list, cwd=run_cwd, capture_output=True, text=True, check=False)
        output = f"Stdout: {result.stdout[:500]}\nStderr: {result.stderr[:500]}"
        
        # Record as a "test result" for now, or create a separate "script_run_results"
        log_msg_for_results = f"Script {script_full_path.name} (in {script_full_path.parent}) "
        if result.returncode == 0:
            log_msg_for_results += f"ran successfully. Output: {output}"
            self.test_results.append(log_msg_for_results) # Using test_results for script outputs too
            return f"Script {script_full_path.name} executed successfully. Output preview: {output[:200]}"
        else:
            log_msg_for_results += f"failed. RC: {result.returncode}. Output: {output}"
            self.test_results.append(log_msg_for_results)
            raise RuntimeError(f"Script {script_full_path.name} failed. RC: {result.returncode}. Output preview: {output[:200]}")

    def _action_create_test(self, path, content, feature=None, **kwargs):
        result_msg = self._action_create_file(path, content, feature, **kwargs)
        return f"Test file created via: {result_msg}"

    def _action_run_test(self, path=None, **kwargs): 
        if not self.project_root: raise ValueError("Project root not set, cannot run tests.")
        
        # test_target is the specific file/dir to test, or empty for all tests in project
        test_target_str = str(self._resolve_path(path)) if path else "" 

        cmd_list = []
        if self.language == "python":
            pip_freeze_res = subprocess.run([self.get_venv_python(), "-m", "pip", "freeze"], cwd=self.project_root, capture_output=True, text=True)
            if 'pytest' not in pip_freeze_res.stdout:
                logging.info("pytest not found, attempting to install...")
                self._action_install_dependency(package="pytest", feature="testing_framework")
            cmd_list = [self.get_venv_python(), "-m", "pytest"]
            if test_target_str: cmd_list.append(test_target_str) # Add target if specified

        elif self.language == "nodejs":
            cmd_list = ["npm", "test"] # Assumes 'npm test' script is configured in package.json
            if test_target_str: cmd_list.extend(["--", test_target_str]) # Pass target after '--' to npm script
        else:
            raise ValueError(f"Unsupported language for running tests: {self.language}")

        result = subprocess.run(cmd_list, cwd=self.project_root, capture_output=True, text=True, check=False)
        output = f"Stdout: {result.stdout[:1000]}\nStderr: {result.stderr[:1000]}"
        
        success = result.returncode == 0
        # More specific checks for test runners
        if self.language == "python" and ("failed" in result.stdout.lower() or "errors" in result.stdout.lower()):
             if result.returncode == 0 : success = False # Pytest might exit 0 with failures in some configurations
        elif self.language == "nodejs" and "fail" in result.stdout.lower(): # Basic check for npm test output
             success = False
        
        test_run_path_desc = f"'{Path(test_target_str).name if path else 'all project tests'}'"
        if success:
            msg = f"Tests for {test_run_path_desc} passed."
            self.test_results.append(f"{msg} Output: {output}")
            return f"{msg} Output preview: {output[:200]}"
        else:
            msg = f"Tests for {test_run_path_desc} failed or had issues."
            self.test_results.append(f"{msg} RC: {result.returncode}. Output: {output}")
            # Not raising exception, as test failure is info for the AI
            return f"{msg} RC: {result.returncode}. Output preview: {output[:200]}"


    def _action_run_lint(self, path, tool, fix=False, feature=None, **kwargs):
        if not self.project_root: raise ValueError("Project root not set for linting.")
        target_path_resolved = self._resolve_path(path)

        linter_executable = tool # Fallback to global if specific path not found
        cmd_list = []

        if tool == "flake8" and self.language == "python":
            linter_executable = self.get_venv_python()
            if fix:
                pip_freeze_res = subprocess.run([linter_executable, "-m", "pip", "freeze"], cwd=self.project_root, capture_output=True, text=True)
                if 'autopep8' not in pip_freeze_res.stdout:
                    self._action_install_dependency(package="autopep8", feature="linting_tool_fixer")
                fix_cmd = [linter_executable, "-m", "autopep8", "--in-place", str(target_path_resolved)]
                fix_run_result = subprocess.run(fix_cmd, cwd=self.project_root, capture_output=True, text=True, check=False)
                if fix_run_result.returncode == 0: logging.info(f"Autopep8 ran on {target_path_resolved}.")
                else: logging.warning(f"Autopep8 failed on {target_path_resolved}: {fix_run_result.stderr or fix_run_result.stdout}")
            cmd_list = [linter_executable, "-m", "flake8", str(target_path_resolved)]

        elif tool == "eslint" and self.language == "nodejs":
            # Prefer npx for local eslint, fallback to global if installed
            npx_path = shutil.which("npx")
            eslint_path = shutil.which("eslint")
            if npx_path: 
                linter_executable = npx_path
                cmd_list = [linter_executable, "eslint", str(target_path_resolved)]
            elif eslint_path:
                linter_executable = eslint_path
                cmd_list = [linter_executable, str(target_path_resolved)]
            else: # Attempt to install if not found
                if not self.install_linter("eslint"):
                     raise RuntimeError("ESLint not found and failed to install. Cannot run lint.")
                # After install, re-check or assume npx eslint will work
                linter_executable = shutil.which("npx") or "npx" # Prefer npx after install
                cmd_list = [linter_executable, "eslint", str(target_path_resolved)]

            if fix: cmd_list.append("--fix")
        else:
            raise ValueError(f"Unsupported linter {tool} or language {self.language}")

        result = subprocess.run(cmd_list, cwd=self.project_root, capture_output=True, text=True, check=False)
        output_detail = f"LINT CMD: {' '.join(cmd_list)}\nStdout: {result.stdout[:500]}\nStderr: {result.stderr[:500]}"
        
        lint_message = f"Linting {target_path_resolved.name} with {tool}: "
        # Flake8: exit 0 if no issues, non-zero if issues. Output on stdout for issues.
        # Eslint: exit 0 if no issues (or auto-fixed), non-zero if unfixed issues.
        if result.returncode == 0 and (not result.stdout.strip() or "no problems found" in result.stdout.lower()):
            lint_message += "Passed (No issues found)."
        elif result.returncode == 0 and result.stdout.strip(): # Some linters (eslint --fix) exit 0 but list changes
            lint_message += f"Completed, potentially with fixes. Details:\n{output_detail}"
        else: # Non-zero exit code or stdout has content (flake8)
            lint_message += f"Issues found or errors occurred. Details:\n{output_detail}"
        
        self.linting_results.append(lint_message)
        if feature and feature not in self.features: self.features.append(feature)
        return f"{lint_message[:200]}..." # Summary for FunctionResponse

    def _action_generate_docs(self, path, content, feature=None, **kwargs):
        result_msg = self._action_create_file(path, content, feature, **kwargs)
        return f"Documentation generated via: {result_msg}"

    def _action_user_clarification_needed(self, question, **kwargs):
        print(f"\nSYSTEM: The AI needs clarification.")
        user_response = input(f"AI ASKS: {question}\nYour response: ")
        # This response will be sent back to Gemini via FunctionResponse
        return {"user_response": user_response, "original_question": question}


    def _execute_action(self, action_name, args_dict):
        logging.info(f"Attempting action: {action_name} with args: {args_dict}")
        if not self._validate_action_params(action_name, args_dict):
             raise ValueError(f"Invalid parameters for action {action_name}: {args_dict}")

        action_method_name = f"_action_{action_name}"
        if not hasattr(self, action_method_name) or not callable(getattr(self, action_method_name)):
            raise NotImplementedError(f"Action '{action_name}' is not implemented in the agent.")
        
        action_method = getattr(self, action_method_name)
        try:
            # Call the action method with unpacked arguments
            result_data = action_method(**args_dict) 
            
            # Ensure result_data is serializable for FunctionResponse later
            if not isinstance(result_data, (str, dict, list, int, float, bool, type(None))):
                result_data = str(result_data) 

            self.task_history.append({
                "action": action_name, "args": args_dict, 
                "result_summary": str(result_data)[:200] if result_data is not None else "None",
                "success": True, "api_model_name": self.api_model_name, "timestamp": datetime.now().isoformat()
            })
            logging.info(f"Action {action_name} successful. Result preview: {str(result_data)[:100] if result_data is not None else 'None'}")
            return result_data 
        except Exception as e:
            logging.error(f"Failed to execute action {action_name} with args {args_dict}: {e}", exc_info=True)
            self.task_history.append({
                "action": action_name, "args": args_dict, "error": str(e),
                "success": False, "api_model_name": self.api_model_name, "timestamp": datetime.now().isoformat()
            })
            raise # Re-raise for the calling Gemini loop to handle and form an error FunctionResponse


    def _validate_grok_task(self, task_item, task_idx, all_tasks):
        action = task_item.get("action")
        # Grok might put params under "parameters" or "params"
        params = task_item.get("parameters", task_item.get("params")) 
        
        if not action or action not in self.supported_actions:
            logging.error(f"Invalid action '{action}' in Grok task {task_idx}")
            return False
        if not isinstance(params, dict):
            logging.error(f"Parameters for action '{action}' in Grok task {task_idx} are not a dict: {params}")
            return False

        if not self._validate_action_params(action, params):
             logging.error(f"Validation failed for Grok task {task_idx} (action: {action}, params: {params})")
             return False

        depends_on_indices = task_item.get("depends_on", [])
        if not isinstance(depends_on_indices, list): 
            logging.error(f"'depends_on' for Grok task {task_idx} is not a list: {depends_on_indices}")
            return False # Should be a list of indices

        for dep_idx in depends_on_indices:
            if not (isinstance(dep_idx, int) and 0 <= dep_idx < len(all_tasks)):
                logging.error(f"Invalid dependency index {dep_idx} for Grok task {task_idx}")
                return False
            # Check if depended-upon task has successfully run (from self.task_results for Grok)
            if dep_idx not in self.task_results or not self.task_results.get(dep_idx, False):
                logging.warning(f"Grok task {task_idx} dependency on task {dep_idx} not met (failed or not run).")
                return False 
        return True

    def _execute_grok_tasks(self, tasks_list_from_grok):
        if not isinstance(tasks_list_from_grok, list):
            logging.error(f"Grok tasks received is not a list: {tasks_list_from_grok}")
            print("Error: AI response for tasks was not in the expected list format.")
            return False

        # Reset task_results for this batch from Grok
        self.task_results = {} # Stores success/failure of tasks in *this current batch*

        valid_tasks_to_run = []
        for i, task_item in enumerate(tasks_list_from_grok):
            if self._validate_grok_task(task_item, i, tasks_list_from_grok):
                valid_tasks_to_run.append((i, task_item)) # Store original index and task
            else:
                self.task_results[i] = False # Mark invalid task as failed

        if not valid_tasks_to_run and tasks_list_from_grok: # Some tasks provided, but all were invalid
            logging.error("All tasks from Grok were invalid. Attempting to ask for a retry.")
            # Simplified retry logic
            grok_response = self.send_to_api(self.command, is_retry=True, failed_task_context={"reason": "All tasks in the previous batch were invalid."})
            if grok_response and "tasks" in grok_response and grok_response["tasks"]:
                logging.info("Retrying with new tasks from Grok.")
                return self._execute_grok_tasks(grok_response["tasks"])
            logging.error("Grok retry failed to produce valid tasks.")
            return False


        all_batch_tasks_successful = True
        for original_idx, task_item in valid_tasks_to_run:
            action = task_item.get("action")
            params = task_item.get("parameters", task_item.get("params", {}))
            
            # Double check dependencies just before execution, as task_results might update
            depends_on_indices = task_item.get("depends_on", [])
            dependencies_met_at_runtime = True
            for dep_idx in depends_on_indices:
                if not self.task_results.get(dep_idx, False): # Check if dependency succeeded
                    dependencies_met_at_runtime = False; break
            
            if not dependencies_met_at_runtime:
                logging.warning(f"Grok task {original_idx} ({action}) skipped: runtime dependency check failed.")
                self.task_results[original_idx] = False
                all_batch_tasks_successful = False
                continue

            try:
                logging.info(f"Executing Grok task (original index {original_idx}): {action} with params {params}")
                # Use the same _execute_action dispatcher. It logs to self.task_history.
                self._execute_action(action, params) 
                self.task_results[original_idx] = True # Mark as successfully executed for this batch
            except Exception as e:
                logging.error(f"Grok task (original index {original_idx}, action {action}) failed: {e}", exc_info=True)
                self.task_results[original_idx] = False
                all_batch_tasks_successful = False
                # Attempt recovery for this specific failed task
                # This recursive recovery can be complex. A simpler approach might be to mark failure and let the next main iteration handle it.
                # For now, let's try a single-level recovery.
                failed_task_details_for_grok = {"action": action, "parameters": params, "error_message": str(e)}
                recovery_prompt = (f"The task to '{action}' with parameters '{json.dumps(params)}' "
                                   f"failed due to: {str(e)}. Please provide a new list of tasks to recover or proceed, "
                                   "considering this failure. The original command was: '{self.command}'")
                
                recovery_response = self.send_to_api(recovery_prompt, failed_task_context=failed_task_details_for_grok)
                if recovery_response and "tasks" in recovery_response and recovery_response["tasks"]:
                    logging.info(f"Executing {len(recovery_response['tasks'])} recovery tasks from Grok.")
                    if not self._execute_grok_tasks(recovery_response["tasks"]): # Recursive call for recovery
                         logging.warning("Recovery tasks from Grok also failed or had issues.")
                else:
                    logging.warning("Grok provided no recovery tasks or recovery failed.")
        return all_batch_tasks_successful


    def finalize_project(self):
        if not self.project_root or not self.project_root.exists():
            logging.warning("Project root not set or does not exist. Skipping finalization.")
            return

        if self.language == "nodejs" and not (self.project_root / "package.json").exists():
            logging.info("Attempting to create a basic package.json for Node.js project.")
            try:
                package_json_content = json.dumps({
                    "name": self.project_root.name.lower().replace(" ", "-"), 
                    "version": "1.0.0", 
                    "description": f"Project: {self.command}",
                    "main": "app.js", # Common default
                    "scripts": {
                        "start": "node app.js", # Common default
                        "test": "echo \"Error: no test specified\" && exit 1"
                    },
                    "keywords": ["ai-generated", self.language],
                    "author": "SuperAIAgent"
                }, indent=2)
                self._execute_action("create_file", {
                    "path": str(self.project_root / "package.json"),
                    "content": package_json_content,
                    "feature": "project_setup"
                })
            except Exception as e:
                logging.error(f"Failed to create package.json: {e}")

        if self.venv_path and self.language == "python":
            logging.info("Attempting to upgrade pip in virtual environment.")
            cmd = [self.get_venv_python(), "-m", "pip", "install", "--upgrade", "pip"]
            result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True, check=False)
            if result.returncode == 0: logging.info("Upgraded pip in virtual environment.")
            else: logging.warning(f"Failed to upgrade pip: {result.stderr or result.stdout}")

        summary_path = self.project_root / "PROJECT_SUMMARY.md"
        completeness = self.assess_project_completeness()
        summary_content = f"# Project Summary: {self.project_root.name}\n\n"
        summary_content += f"- **Original Command**: {self.command}\n"
        summary_content += f"- **Directory**: `{self.project_root}`\n"
        summary_content += f"- **Language**: {self.language}\n"
        summary_content += f"- **Final Completeness Score**: {completeness['score']}/100\n"
        summary_content += f"- **Features Implemented**: {', '.join(self.features) or 'None'}\n"
        summary_content += "- **Files Overview (sample)**:\n"
        
        # List files relative to project root for summary
        files_for_summary = []
        if self.project_root and self.project_root.exists():
            for item in self.project_root.rglob("*"):
                 if item.is_file() and ".git" not in item.parts and VENV_DIR not in item.parts:
                     try:
                         files_for_summary.append(str(item.relative_to(self.project_root)))
                     except ValueError: # If item is not under project_root (should not happen with rglob from root)
                         files_for_summary.append(str(item)) 
        else: # Fallback to created_files list
            files_for_summary = [Path(f).name for f in self.created_files]


        for f_rel_path in files_for_summary[:20]: 
            summary_content += f"  - `{f_rel_path}`\n"
        if len(files_for_summary) > 20: summary_content += "  - ... (and more)\n"
        
        summary_content += f"- **Dependencies Installed**: {', '.join(self.installed_deps) or 'None'}\n"
        summary_content += "- **Last Linting Results (sample)**:\n"
        for res_str in self.linting_results[-3:]: summary_content += f"  - {res_str[:200].strip()}...\n"
        if not self.linting_results: summary_content += "  - No linting results recorded.\n"
        summary_content += "- **Last Test Results (sample)**:\n"
        for res_str in self.test_results[-3:]: summary_content += f"  - {res_str[:200].strip()}...\n"
        if not self.test_results: summary_content += "  - No test results recorded.\n"
        summary_content += f"- **Identified Issues at End**: {', '.join(completeness['issues']) or 'None'}\n"
        
        # Basic run instructions
        summary_content += "\n## Basic Run Instructions:\n"
        if self.language == "python":
            venv_activate_cmd = f"source {self.venv_path.relative_to(Path.cwd())}/bin/activate" if self.venv_path else "source .venv/bin/activate"
            summary_content += f"1. Activate virtual env: `{venv_activate_cmd}` (Linux/Mac) or `.\\{self.venv_path.name}\\Scripts\\activate` (Windows, assuming venv in project root)\n"
            summary_content += f"2. Install dependencies (if needed): `pip install -r requirements.txt` (if a requirements.txt was created)\n"
            summary_content += f"3. Run main script: `python app.py` (or your main script name)\n"
            summary_content += f"4. Run tests: `pytest` (if pytest is used)\n"
        elif self.language == "nodejs":
            summary_content += f"1. Install dependencies: `npm install`\n"
            summary_content += f"2. Run main script: `npm start` (if 'start' script in package.json) or `node app.js`\n"
            summary_content += f"3. Run tests: `npm test` (if 'test' script in package.json)\n"

        with open(summary_path, 'w', encoding='utf-8') as f:
            f.write(summary_content)
        if str(summary_path) not in self.created_files: self.created_files.append(str(summary_path))
        logging.info(f"Generated project summary: {summary_path}")

        # Create ZIP archive
        archive_base_name = self.project_root.name
        archive_path = self.project_root.parent / f"{archive_base_name}_project_archive" # Name for zip, avoids .zip.zip

        logging.info(f"Creating project archive: {archive_path}.zip")
        # Use shutil.make_archive for easier directory zipping
        try:
            shutil.make_archive(str(archive_path), 'zip', self.project_root)
            logging.info(f"Created project archive: {archive_path}.zip")
            print(f"Project summary: {summary_path.resolve()}")
            print(f"Project archive: {Path(str(archive_path) + '.zip').resolve()}")
        except Exception as e:
            logging.error(f"Failed to create project archive: {e}", exc_info=True)
            print(f"Failed to create project archive. Check logs. Summary is at {summary_path.resolve()}")


    def prompt_user_for_next_step(self):
        completeness = self.assess_project_completeness()
        print(f"\n--- Iteration {self.current_iteration} Review ({self.api_model_name}) ---")
        print(f"Project: {self.project_root.name if self.project_root else 'N/A'}")
        print(f"Language: {self.language}")
        print(f"Completeness Score: {completeness['score']}/100")
        if completeness['issues']: print(f"Identified Issues: {', '.join(completeness['issues'])}")
        else: print("No major issues identified by completeness check.")
        if completeness['missing_features']: print(f"Suggested Next Features: {', '.join(completeness['missing_features'])}")

        print("\nOptions:")
        print("1. Continue (AI suggests next steps based on overall command and context)")
        print("2. Add/Refine specific feature (you provide a new focused command)")
        print("3. Stop and finalize project")
        print("4. Pause (save state and exit to resume later)")
        
        choice_prompt = "Enter choice (1-4) or type a new command/feature to work on: "
        user_input_str = input(choice_prompt).strip()
        
        if user_input_str == "1" or user_input_str.lower() == "continue" or not user_input_str: # Default to continue
            return {"action": "continue", "command": f"Continue enhancing project towards original goal: {self.command}"}
        elif user_input_str == "2":
            feature_desc = input("Enter feature description or refined command: ").strip()
            return {"action": "add_feature", "command": feature_desc}
        elif user_input_str == "3" or user_input_str.lower() == "stop":
            return {"action": "stop"}
        elif user_input_str == "4" or user_input_str.lower() == "pause":
            return {"action": "pause"}
        else: # Treat any other non-empty input as a new specific command/directive
            return {"action": "new_command", "command": user_input_str}


    def process_command(self, initial_command_str=None, initial_model_choice=None):
        if not self.validate_environment():
            print("Environment validation failed. Please ensure required tools (python3, git, node/npm if nodejs) are installed and in PATH.")
            return

        # API Model Selection (if not already set, e.g. from loaded state)
        if not self.api_model_name:
            if initial_model_choice:
                try: self.select_api(initial_model_choice)
                except ValueError as e: print(e); return
            else:
                available_models = []
                if self.gemini_api_key and self.gemini_api_key != "DISABLED": available_models.append("gemini")
                if self.xai_api_key and self.xai_api_key != "DISABLED": available_models.append("grok")

                if not available_models:
                    print("No API keys are configured. Cannot select an AI model.")
                    return
                
                model_prompt = f"Select AI model ({'/'.join(available_models)}): "
                while not self.api_model_name:
                    model_choice_input = input(model_prompt).strip().lower()
                    if model_choice_input not in available_models:
                        print(f"Invalid choice. Please select from {available_models}.")
                        continue
                    try: self.select_api(model_choice_input); break
                    except ValueError as e: print(e) # Catch if select_api itself raises for a valid key but other issue

        # State Loading / New Project Setup
        resumed_from_state = False
        if not initial_command_str and self.load_state(): # Try to load if no explicit new command
            if self.command: # Check if command was loaded from state
                initial_command_str = self.command # Use loaded command as the base
                resumed_from_state = True
                print(f"\nResuming work on project for command: '{self.command}'")
                print(f"Current Iteration: {self.current_iteration}, API Model: {self.api_model_name or 'Not Set'}")
                if self.project_root: print(f"Project root: {self.project_root}")
                else: print("Warning: Project root not found in loaded state.")
            else: # State loaded but no command, or state inconsistent
                logging.warning("State loaded but no previous command found or state was partial. Starting fresh command prompt.")
                initial_command_str = input("Enter your command (e.g., 'build a web app with user auth'): ").strip()
                if not initial_command_str: print("No command given. Exiting."); return
                # Treat as new command but on potentially existing (though partial) state.
                # May need to re-initialize parts of the state if it's too inconsistent.
                self.command = initial_command_str
                self.current_iteration = 0 # Reset iteration for this "new" command
        elif initial_command_str: # Explicit new command provided
            self.clear_state() # New command means fresh state (old agent_state.json is removed)
            self.command = initial_command_str
            
            # Project Root Setup for new project
            default_proj_name = "_".join(self.command.lower().split()[:4]).replace(r'[^a-zA-Z0-9_]+', '') or "my_ai_project"
            proj_root_input = input(f"Enter project directory name (will be created in current dir, default: '{default_proj_name}'): ").strip()
            self.project_root = (Path.cwd() / (proj_root_input if proj_root_input else default_proj_name)).resolve()
            try:
                self.project_root.mkdir(parents=True, exist_ok=True)
                print(f"Project root set to: {self.project_root}")
            except OSError as e:
                print(f"Error creating project directory {self.project_root}: {e}. Please check permissions or choose a different name.")
                return

            # Initialize other state vars for a fresh project
            self.language = "python" # Default, can be changed by AI
            self.venv_path = None
            self.created_files, self.installed_deps, self.linting_results, self.test_results, self.features, self.task_history, self.file_hashes = [], [], [], [], [], [], {}
            self.current_iteration = 0
            if self.api_model_name == "gemini" and self.gemini_model_instance: # Reset chat history for new project
                self.gemini_chat_session = self.gemini_model_instance.start_chat(history=[])
            logging.info(f"Starting new project: '{self.command}' in '{self.project_root}' using {self.api_model_name}")
        else: # No command and no state to load
            print("No command provided and no saved state found to resume.")
            initial_command_str = input("Enter your command to start a new project: ").strip()
            if not initial_command_str: print("No command given. Exiting."); return
            # Call self again to go through the new project setup path
            self.process_command(initial_command_str=initial_command_str, initial_model_choice=self.api_model_name)
            return

        current_user_directive = self.command if not resumed_from_state else f"Continue working on: {self.command}"

        # Main interaction loop
        while True:
            self.current_iteration += 1
            print(f"\n--- Iteration {self.current_iteration} ({self.api_model_name}) ---")
            logging.info(f"Starting iteration {self.current_iteration}. Current directive: '{current_user_directive}'")

            api_response_obj = self.send_to_api(current_user_directive)

            if self.api_model_name == "gemini":
                if isinstance(api_response_obj, str) and api_response_obj.startswith("Error:"): # Error string from send_to_api
                    print(f"Critical API Error: {api_response_obj}")
                    break 
                
                # Iteratively process Gemini's FunctionCalls
                # The first response is from send_to_api, subsequent ones from chat_session.send_message with FunctionResponse
                current_gemini_sdk_response = api_response_obj 
                
                max_tool_calls_per_turn = 5 # Safety break for tool call loops
                tool_calls_this_turn = 0

                while tool_calls_this_turn < max_tool_calls_per_turn:
                    if not current_gemini_sdk_response.candidates:
                        feedback = current_gemini_sdk_response.prompt_feedback if hasattr(current_gemini_sdk_response, 'prompt_feedback') else "No candidates and no feedback."
                        print(f"Gemini Warning: No candidates in response. Feedback: {feedback}")
                        logging.warning(f"Gemini: No candidates. Feedback: {feedback}")
                        break # Exit tool processing loop for this iteration

                    # Assuming the first candidate is the one we care about
                    candidate_part = current_gemini_sdk_response.candidates[0].content.parts[0]
                    
                    if candidate_part.function_call and candidate_part.function_call.name:
                        tool_calls_this_turn += 1
                        fc = candidate_part.function_call
                        action_name = fc.name
                        action_args = dict(fc.args) 
                        print(f"GEMINI requests tool: {action_name}({json.dumps(action_args, indent=2, default=str)})")
                        
                        tool_execution_result_content = None
                        try:
                            # _execute_action handles logging success/failure to self.task_history
                            tool_execution_result_content = self._execute_action(action_name, action_args)
                            # Ensure the result is a dict for FunctionResponse's 'response' field
                            if not isinstance(tool_execution_result_content, dict):
                                tool_execution_result_content = {"result": str(tool_execution_result_content if tool_execution_result_content is not None else "Action completed.")}
                        except Exception as e:
                            logging.error(f"Error executing action {action_name} for Gemini: {e}", exc_info=True)
                            print(f"ERROR executing action {action_name}: {e}")
                            tool_execution_result_content = {"error": f"Failed to execute {action_name}: {str(e)}"}
                        
                        print(f"Sending result of '{action_name}' back to Gemini...")
                        logging.info(f"Sending FunctionResponse for {action_name}. Result: {str(tool_execution_result_content)[:100]}")

                        try:
                            # Construct the FunctionResponse part for the SDK
                            function_response_message_part = Part(
                                function_response=FunctionResponse(name=action_name, response=tool_execution_result_content)
                            )
                            # Send this part as the next message. Chat history is managed by the session.
                            current_gemini_sdk_response = self.gemini_chat_session.send_message(function_response_message_part)
                            # Loop continues: check new current_gemini_sdk_response for another function_call or text
                        except Exception as e:
                            logging.error(f"Error sending FunctionResponse to Gemini or processing its reply: {e}", exc_info=True)
                            print(f"Error communicating with Gemini after tool execution: {e}")
                            break # Exit tool processing loop
                    else: # No more function calls from Gemini in this sequence, should be text
                        final_text_from_gemini = candidate_part.text if hasattr(candidate_part, 'text') else ""
                        if final_text_from_gemini:
                            print(f"GEMINI (text response): {final_text_from_gemini}")
                            current_user_directive = final_text_from_gemini # Use this as next prompt if it's a question/summary
                        else:
                            print("Gemini provided no further function calls and no text for this step.")
                        break # Exit tool processing loop
                
                if tool_calls_this_turn >= max_tool_calls_per_turn:
                    print(f"Warning: Reached max tool calls ({max_tool_calls_per_turn}) for this turn. Moving to user prompt.")
                    logging.warning(f"Max tool calls reached for iteration {self.current_iteration}.")


            elif self.api_model_name == "grok":
                if api_response_obj and "tasks" in api_response_obj:
                    tasks_from_grok = api_response_obj["tasks"]
                    if tasks_from_grok:
                        print(f"GROK provided {len(tasks_from_grok)} tasks. Executing...")
                        if not self._execute_grok_tasks(tasks_from_grok):
                            print("Warning: Failed to execute one or more tasks from Grok for this iteration.")
                    else:
                        print("Grok provided no tasks for this iteration. Project might be complete or AI needs different input.")
                else:
                    print("Error: Grok response was not in the expected format or API call failed.")
            
            self.save_state() 

            # User interaction for next step
            completeness = self.assess_project_completeness() # Re-assess after actions
            if completeness["is_complete"]:
                print("\nProject assessed as complete based on current metrics!")
            
            user_next_step_details = self.prompt_user_for_next_step()
            user_action = user_next_step_details["action"]
            
            if user_action == "stop":
                print("Stopping project as per user request."); break
            elif user_action == "pause":
                self.save_state_and_exit(None, None) # Uses the signal handler logic
            else: # continue, add_feature, or new_command
                current_user_directive = user_next_step_details["command"]
                if self.api_model_name == "gemini" and user_action == "new_command":
                    logging.info(f"New user directive for Gemini: '{current_user_directive}'. Chat session continues.")
                elif self.api_model_name == "grok" and user_action == "new_command":
                     logging.info(f"New user directive for Grok: '{current_user_directive}'.")


        # Loop finished (stop or break due to error)
        if self.project_root and self.project_root.exists():
            print("\nFinalizing project...")
            self.finalize_project()
            print("Project finalized.")
        else:
            print("Project root not available or not created. Finalization skipped.")
        
        # Clear state only if an explicit "stop" was chosen and finalization happened.
        # If paused or error, state should remain.
        if user_action == "stop": # Check last user action
            self.clear_state()
            logging.info("Project stopped and state cleared.")


def main():
    load_dotenv() 

    gemini_api_key_env = os.getenv("GEMINI_API_KEY")
    xai_api_key_env = os.getenv("XAI_API_KEY") # For Grok

    # Interactive API key input if not in .env
    if not gemini_api_key_env or gemini_api_key_env == "YOUR_GEMINI_API_KEY_HERE": # Check for placeholder too
        print("GEMINI_API_KEY not found or is a placeholder in .env file.")
        use_gemini = input("Do you want to configure and use Gemini? (yes/no): ").strip().lower()
        gemini_api_key_env = input("Please enter your Gemini API Key: ").strip() if use_gemini == 'yes' else "DISABLED"
    
    if not xai_api_key_env or xai_api_key_env == "YOUR_XAI_API_KEY_HERE":
        print("XAI_API_KEY (for Grok) not found or is a placeholder in .env file.")
        use_grok = input("Do you want to configure and use Grok? (yes/no): ").strip().lower()
        xai_api_key_env = input("Please enter your XAI API Key: ").strip() if use_grok == 'yes' else "DISABLED"
            
    if gemini_api_key_env == "DISABLED" and xai_api_key_env == "DISABLED":
        print("No API keys provided for either Gemini or Grok. The agent cannot function. Exiting.")
        return

    agent = SuperAIAgent(gemini_api_key_env, xai_api_key_env)
    
    initial_command_str = input("Enter your command (e.g., 'build a python flask app with a single hello world route and tests') or press Enter to resume: ").strip()
    agent.process_command(initial_command_str=initial_command_str if initial_command_str else None)

if __name__ == "__main__":
    main()

EOF
echo "Python script '$PYTHON_SCRIPT_NAME' created."

# 5. Create .env file and prompt for API keys
echo "Creating .env file for API keys..."
# Create an empty .env or clear it if it exists from a previous partial run
> .env

echo "You will be prompted for API keys. If you don't have one, press Enter to skip."

read -p "Enter your GEMINI_API_KEY: " gemini_key_input
if [[ -n "$gemini_key_input" ]]; then
    echo "GEMINI_API_KEY=$gemini_key_input" >> .env
else
    echo "# GEMINI_API_KEY=" >> .env # Comment out if not provided
fi

read -p "Enter your XAI_API_KEY (for Grok): " xai_key_input
if [[ -n "$xai_key_input" ]]; then
    echo "XAI_API_KEY=$xai_key_input" >> .env
else
    echo "# XAI_API_KEY=" >> .env
fi
echo ".env file configured."

# 6. Provide Instructions
echo ""
echo "---------------------------------------------------------------------"
echo "Setup complete for '$PROJECT_NAME'!"
echo ""
echo "To run your AI Agent:"
echo "1. Ensure you are in the project directory:"
echo "   cd $(pwd)  (You should already be here)"
echo "2. The virtual environment '$VENV_DIR' should be active for this session."
echo "   If you open a new terminal, reactivate it with:"
echo "   source $VENV_DIR/bin/activate"
echo "3. Run the agent script:"
echo "   python $PYTHON_SCRIPT_NAME"
echo ""
echo "The agent will create an 'agent.log' file for logging."
echo "It will also create 'agent_state.json' to save progress."
echo "---------------------------------------------------------------------"

# Deactivating the venv here is optional; the user's current shell session has it active.
# If you want to ensure it's deactivated when the script ends:
# deactivate
# echo "Virtual environment deactivated. Remember to source it again before running the agent."
