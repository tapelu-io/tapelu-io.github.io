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

# Configure logging
logging.basicConfig(
    filename='agent.log',
    level=logging.INFO,
    format='%(asctime)s - %(levelname)s - %(message)s'
)

class SuperAIAgent:
    def __init__(self, gemini_api_key, xai_api_key):
        self.gemini_api_key = gemini_api_key
        self.xai_api_key = xai_api_key
        self.api_key = None
        self.api_url = None
        self.api_model = None
        self.project_root = None
        self.language = "python"
        self.venv_path = None
        self.task_results = {}
        self.created_files = []
        self.installed_deps = []
        self.linting_results = []
        self.test_results = []
        self.features = []
        self.task_history = []
        self.file_hashes = {}
        self.current_iteration = 0
        self.state_file = Path("agent_state.json")
        self.context_file = Path("context_summary.json")
        self.command = None
        self.supported_actions = {
            "create_directory", "create_venv", "set_language", "create_file",
            "modify_file", "delete_file", "install_dependency", "init_git",
            "git_commit", "git_branch", "git_push", "run_script", "create_test",
            "run_test", "generate_docs", "run_lint"
        }
        self.supported_linters = {"python": "flake8", "nodejs": "eslint"}
        self.required_tools = {"python": "python3", "git": "git"}
        signal.signal(signal.SIGINT, self.save_state_and_exit)

    def select_api(self, model_choice):
        """Configure API based on user choice."""
        model_choice = model_choice.lower().strip()
        if model_choice == "grok":
            self.api_model = "grok"
            self.api_key = self.xai_api_key
            self.api_url = "https://api.grok.x.ai/v1/chat/completions"
        elif model_choice == "gemini":
            self.api_model = "gemini"
            self.api_key = self.gemini_api_key
            self.api_url = "https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent"
        else:
            raise ValueError(f"Invalid model choice: {model_choice}. Use 'gemini' or 'grok'.")
        logging.info(f"Selected API model: {self.api_model}")

    def save_state_and_exit(self, signum, frame):
        """Save state and exit on interrupt."""
        self.save_state()
        print(f"Work paused at {datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')}. State saved. Resume by re-running.")
        sys.exit(0)

    def save_state(self):
        """Save full state and context summary."""
        state = {
            "project_root": self.project_root,
            "language": self.language,
            "venv_path": str(self.venv_path) if self.venv_path else None,
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
            "api_model": self.api_model,
            "last_updated": datetime.now().isoformat()
        }
        with open(self.state_file, 'w') as f:
            json.dump(state, f, indent=2)
        logging.info(f"Saved state to {self.state_file}")

        context = self.get_context_summary()
        with open(self.context_file, 'w') as f:
            json.dump(context, f, indent=2)
        logging.info(f"Saved context to {self.context_file}")

    def load_state(self):
        """Load agent state from JSON file."""
        if not self.state_file.exists():
            return False
        try:
            with open(self.state_file, 'r') as f:
                state = json.load(f)
            self.project_root = state.get("project_root")
            self.language = state.get("language", "python")
            self.venv_path = Path(state["venv_path"]) if state.get("venv_path") else None
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
            self.api_model = state.get("api_model")
            if self.project_root and not Path(self.project_root).exists():
                logging.error(f"Project root {self.project_root} does not exist")
                return False
            logging.info(f"Loaded state from {self.state_file}")
            return True
        except Exception as e:
            logging.error(f"Failed to load state: {e}")
            return False

    def clear_state(self):
        """Clear saved state and context."""
        if self.state_file.exists():
            self.state_file.unlink()
            logging.info("State cleared")
        if self.context_file.exists():
            self.context_file.unlink()
            logging.info("Context summary cleared")

    def get_file_summary(self, file_path):
        """Summarize file content to reduce token usage."""
        try:
            path = Path(file_path)
            if not path.exists():
                return {"path": str(path), "summary": "File not found"}
            with open(path, 'r', encoding='utf-8') as f:
                content = f.read()
            file_hash = hashlib.md5(content.encode()).hexdigest()
            self.file_hashes[file_path] = file_hash
            if len(content) < 500:
                return {"path": str(file_path), "content": content, "hash": file_hash}
            lines = content.splitlines()
            summary = "\n".join(lines[:5]) + "\n... (truncated)\n"
            signatures = [line.strip() for line in lines if line.strip().startswith(("def ", "class "))]
            if signatures:
                summary += "Key definitions:\n" + "\n".join(signatures[:3]) + "\n"
            return {"path": str(file_path), "summary": summary, "hash": file_hash}
        except Exception as e:
            logging.error(f"Failed to summarize file {file_path}: {e}")
            return {"path": str(file_path), "summary": "Error summarizing file"}

    def get_context_summary(self):
        """Generate a concise context summary for the selected API."""
        completeness = self.assess_project_completeness()
        key_files = [f for f in self.created_files if "app." in f or "test_" in f or f.endswith(".md")]
        recent_files = sorted(
            self.created_files,
            key=lambda x: max((h.get("timestamp", "1970-01-01") for h in self.task_history if h["task"].get("path") == x), default="1970-01-01"),
            reverse=True
        )[:3]
        file_summaries = [self.get_file_summary(f) for f in set(key_files + recent_files)]
        recent_tasks = self.task_history[-5:] if len(self.task_history) > 5 else self.task_history
        return {
            "metadata": {
                "project_root": self.project_root,
                "language": self.language,
                "features": self.features,
                "dependencies": self.installed_deps,
                "iteration": self.current_iteration,
                "original_command": self.command
            },
            "completeness": completeness,
            "file_summaries": file_summaries,
            "recent_tasks": recent_tasks,
            "issues": completeness["issues"],
            "missing_features": completeness["missing_features"]
        }

    def assess_project_completeness(self):
        """Assess project quality and completeness."""
        score = 0
        issues = []
        main_files = list(Path(self.project_root).glob("*.py" if self.language == "python" else "*.js")) if self.project_root else []
        if main_files:
            score += 20
        else:
            issues.append("No main script found")
        test_files = list(Path(self.project_root).glob("test_*.py" if self.language == "python" else "test_*.js")) if self.project_root else []
        if test_files:
            score += 20
        else:
            issues.append("No test files found")
        passing_tests = sum(1 for result in self.test_results if "Passed" in result)
        if passing_tests > 0:
            score += 20
        elif test_files:
            issues.append("Tests are failing")
        linting_passed = all("Passed" in result or "Fixed" in result for result in self.linting_results)
        if linting_passed:
            score += 20
        else:
            issues.append("Linting issues detected")
        production_features = ["authentication", "database", "logging", "docker", "ci_cd"]
        implemented = [f for f in self.features if f in production_features]
        score += len(implemented) * 4
        missing_features = [f for f in production_features if f not in implemented]
        if missing_features:
            issues.append(f"Missing production features: {', '.join(missing_features)}")
        return {
            "score": score,
            "issues": issues,
            "is_complete": score >= 80 and not issues,
            "missing_features": missing_features
        }

    def validate_environment(self):
        """Validate required tools."""
        missing_tools = []
        for tool, cmd in self.required_tools.items():
            if not shutil.which(cmd):
                missing_tools.append(tool)
        if self.language == "nodejs" and not shutil.which("node"):
            missing_tools.append("node")
        if missing_tools:
            logging.error(f"Missing tools: {', '.join(missing_tools)}")
            return False
        return True

    def validate_task(self, task, task_index, tasks):
        """Validate a single task to prevent divergence."""
        action = task.get("action")
        path = task.get("path")
        feature = task.get("feature")
        if action not in self.supported_actions:
            logging.error(f"Invalid action: {action}")
            return False
        if path:
            if self.project_root and Path(path).is_absolute() and not Path(path).resolve().startswith(Path(self.project_root).resolve()):
                logging.error(f"Invalid path: {path} is outside project root")
                return False
            if re.search(r'[<>:"|?*\x00-\x1F]', path):
                logging.error(f"Invalid characters in path: {path}")
                return False
        if action == "run_lint":
            tool = task.get("tool")
            expected_linter = self.supported_linters.get(self.language)
            if tool != expected_linter:
                logging.error(f"Unsupported linter {tool} for {self.language}")
                return False
            if not shutil.which(tool):
                logging.warning(f"Linter {tool} not installed, attempting to install...")
                try:
                    self.install_linter(tool)
                except Exception as e:
                    logging.error(f"Failed to install linter {tool}: {e}")
                    return False
        depends_on = task.get("depends_on", [])
        for dep in depends_on:
            if dep >= len(tasks) or dep < 0:
                logging.error(f"Invalid dependency index {dep} for task {task_index}")
                return False
        if feature in self.features and action in ["create_file", "install_dependency"]:
            logging.warning(f"Feature {feature} already implemented, task may be redundant")
            return False
        if action == "modify_file" and path in self.file_hashes:
            with open(path, 'r', encoding='utf-8') as f:
                current_hash = hashlib.md5(f.read().encode()).hexdigest()
            if current_hash == self.file_hashes.get(path):
                logging.warning(f"File {path} unchanged, modification may be unnecessary")
                return False
        return True

    def install_linter(self, tool):
        """Install a linter if not present."""
        if tool == "flake8":
            cmd = [self.get_venv_python(), "-m", "pip", "install", "flake8", "autopep8"]
        elif tool == "eslint":
            cmd = ["npm", "install", "-g", "eslint"]
        result = subprocess.run(cmd, capture_output=True, text=True)
        if result.returncode != 0:
            raise RuntimeError(f"Failed to install {tool}: {result.stderr}")
        logging.info(f"Installed linter: {tool}")

    def send_to_api(self, command, failed_task=None, retry=False):
        """Send command to the selected API with summarized context."""
        context = self.get_context_summary()
        prompt = f"""
        You are an expert coder AI continuing a long-term software project, acting as a human coder resuming work on a potentially large codebase. You have no memory of past interactions, so rely on the provided context to stay aligned with the project's state and goals.

        **User Command**: '{command}'
        **Current Iteration**: {self.current_iteration}
        {'**Previous Task Failed**: ' + str(failed_task) if failed_task else ''}
        {'**Retry Attempt**: Correct previous incorrect response' if retry else ''}

        **Project Context Summary**:
        {json.dumps(context, indent=2)}

        **Instructions**:
        - Provide a JSON response with tasks to enhance the project toward production readiness.
        - **Supported Actions**:
          - create_directory: {{"path": "dir_name"}}
          - create_venv: {{"path": "dir_name", "name": "venv_name"}}
          - set_language: {{"language": "python|nodejs"}}
          - create_file: {{"path": "file_path", "content": "file_content"}}
          - modify_file: {{"path": "file_path", "content": "new_content"}}
          - delete_file: {{"path": "file_path"}}
          - install_dependency: {{"package": "package_name", "version": "version_number"}}
          - init_git: {{"path": "repo_path"}}
          - git_commit: {{"path": "repo_path", "message": "commit_message"}}
          - git_branch: {{"path": "repo_path", "branch": "branch_name"}}
          - git_push: {{"path": "repo_path", "remote": "remote_url", "branch": "branch_name"}}
          - run_script: {{"path": "script_path"}}
          - create_test: {{"path": "test_file_path", "content": "test_content"}}
          - run_test: {{"path": "test_file_path"}}
          - generate_docs: {{"path": "doc_path", "content": "doc_content"}}
          - run_lint: {{"path": "file_path", "tool": "flake8|eslint", "fix": true/false}}
        - Include 'depends_on': [task_indices] and 'feature': "feature_name" for each task.
        - **Example Response**:
          {{
              "tasks": [
                  {{"action": "create_file", "path": "my_app/auth.py", "content": "...", "feature": "authentication", "depends_on": [0]}},
                  {{"action": "run_lint", "path": "my_app/auth.py", "tool": "flake8", "fix": true, "feature": "authentication"}}
              ]
          }}

        **Guardrails**:
        - **Stay Aligned**: Base tasks on the user command and context. Do not re-implement existing features: {context['metadata']['features']}.
        - **Respect Structure**: Ensure tasks integrate with existing code (see file_summaries). Do not modify files unnecessarily.
        - **Address Gaps**: Prioritize issues ({context['issues']}) and missing features ({context['missing_features']}).
        - **Avoid Redundancy**: Check recent_tasks to avoid repeating work.
        - **Handle Failures**: If failed_task is provided, suggest recovery tasks.
        - **Complete Project**: If score >= 80 and no issues, return an empty tasks list.
        - **Stay Focused**: Do not diverge to unrelated features or architectures unless explicitly requested.

        **Goal**: Continue the project as if you were the original coder, using the context to maintain consistency and avoid errors.
        """

        try:
            headers = {"Authorization": f"Bearer {self.api_key}", "Content-Type": "application/json"}
            if self.api_model == "grok":
                payload = {
                    "model": "grok-3",
                    "messages": [{"role": "user", "content": prompt}],
                    "response_format": {"type": "json_object"}
                }
                response = requests.post(self.api_url, json=payload, headers=headers)
                response.raise_for_status()
                # Parse Grok response
                result = response.json()
                tasks = json.loads(result["choices"][0]["message"]["content"])
                return tasks
            else:  # Gemini
                payload = {"contents": [{"parts": [{"text": prompt}]}]}
                response = requests.post(f"{self.api_url}?key={self.api_key}", json=payload, headers=headers)
                response.raise_for_status()
                # Parse Gemini response
                result = response.json()
                tasks = json.loads(result["candidates"][0]["content"]["parts"][0]["text"])
                return tasks
        except requests.RequestException as e:
            logging.error(f"{self.api_model} API request failed: {e}")
            return {"tasks": []}
        except (KeyError, json.JSONDecodeError) as e:
            logging.error(f"Failed to parse {self.api_model} response: {e}")
            return {"tasks": []}

    def check_dependencies(self, task, task_index, tasks):
        """Check if task dependencies are met."""
        depends_on = task.get("depends_on", [])
        for dep in depends_on:
            if dep >= len(tasks) or dep not in self.task_results or not self.task_results[dep]:
                return False
        return True

    def get_venv_python(self):
        """Return path to Python executable in virtual environment."""
        if self.venv_path:
            if sys.platform == "win32":
                return str(Path(self.venv_path) / "Scripts" / "python.exe")
            return str(Path(self.venv_path) / "bin" / "python")
        return sys.executable

    def execute_task(self, task, task_index, tasks):
        """Execute a single task if dependencies are met."""
        if not self.check_dependencies(task, task_index, tasks):
            logging.warning(f"Task {task_index} skipped: dependencies not met")
            self.task_results[task_index] = False
            return False

        action = task.get("action")
        path = task.get("path")
        feature = task.get("feature", "unknown")
        try:
            if action == "create_directory":
                Path(path).mkdir(parents=True, exist_ok=True)
                if not self.project_root:
                    self.project_root = path
                logging.info(f"Created directory: {path}")

            elif action == "create_venv":
                venv_path = Path(task["path"]) / task.get("name", ".venv")
                venv.create(venv_path, with_pip=True)
                self.venv_path = venv_path
                logging.info(f"Created virtual environment: {venv_path}")

            elif action == "set_language":
                self.language = task.get("language", "python")
                logging.info(f"Set project language: {self.language}")

            elif action in ["create_file", "create_test", "generate_docs"]:
                content = task.get("content", "")
                Path(path).parent.mkdir(parents=True, exist_ok=True)
                with open(path, 'w') as f:
                    f.write(content)
                self.created_files.append(path)
                if feature not in self.features:
                    self.features.append(feature)
                logging.info(f"Created file: {path} (feature: {feature})")

            elif action == "modify_file":
                content = task.get("content", "")
                if not Path(path).exists():
                    logging.warning(f"File {path} does not exist, creating it.")
                with open(path, 'w') as f:
                    f.write(content)
                self.created_files.append(path)
                if feature not in self.features:
                    self.features.append(feature)
                logging.info(f"Modified file: {path} (feature: {feature})")

            elif action == "delete_file":
                if Path(path).exists():
                    Path(path).unlink()
                    self.created_files = [f for f in self.created_files if f != path]
                    logging.info(f"Deleted file: {path}")
                else:
                    logging.warning(f"File {path} does not exist.")

            elif action == "install_dependency":
                package = task.get("package")
                version = task.get("version")
                if self.language == "python":
                    cmd = [self.get_venv_python(), "-m", "pip", "install"]
                    cmd.append(f"{package}=={version}" if version else package)
                elif self.language == "nodejs":
                    cmd = ["npm", "install", f"{package}@{version}" if version else package]
                else:
                    raise ValueError(f"Unsupported language for dependency: {self.language}")
                result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
                if result.returncode == 0:
                    self.installed_deps.append(f"{package}{f'=={version}' if version else ''}")
                    logging.info(f"Installed {package} {version or ''} (feature: {feature})")
                else:
                    raise RuntimeError(f"Failed to install {package}: {result.stderr}")

            elif action == "init_git":
                if not Path(path).exists():
                    Path(path).mkdir(parents=True, exist_ok=True)
                result = subprocess.run(["git", "init"], cwd=path, capture_output=True, text=True)
                if result.returncode == 0:
                    logging.info(f"Initialized git repository in {path}")
                else:
                    raise RuntimeError(f"Git init failed: {result.stderr}")

            elif action == "git_commit":
                message = task.get("message", "Automated commit")
                subprocess.run(["git", "add", "."], cwd=path, capture_output=True, text=True)
                result = subprocess.run(
                    ["git", "commit", "-m", message], cwd=path, capture_output=True, text=True
                )
                if result.returncode == 0:
                    logging.info(f"Committed changes in {path}: {message}")
                else:
                    raise RuntimeError(f"Git commit failed: {result.stderr}")

            elif action == "git_branch":
                branch = task.get("branch")
                result = subprocess.run(
                    ["git", "checkout", "-b", branch], cwd=path, capture_output=True, text=True
                )
                if result.returncode == 0:
                    logging.info(f"Created and switched to branch {branch} in {path}")
                else:
                    raise RuntimeError(f"Git branch failed: {result.stderr}")

            elif action == "git_push":
                remote = task.get("remote")
                branch = task.get("branch")
                result = subprocess.run(
                    ["git", "push", remote, branch], cwd=path, capture_output=True, text=True
                )
                if result.returncode == 0:
                    logging.info(f"Pushed to {remote}/{branch} from {path}")
                else:
                    raise RuntimeError(f"Git push failed: {result.stderr}")

            elif action == "run_script":
                if self.language == "python":
                    cmd = [self.get_venv_python(), path]
                elif self.language == "nodejs":
                    cmd = ["node", path]
                else:
                    raise ValueError(f"Unsupported language for script: {self.language}")
                result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
                if result.returncode == 0:
                    logging.info(f"Ran script {path}: {result.stdout}")
                else:
                    raise RuntimeError(f"Script {path} failed: {result.stderr}")

            elif action == "run_test":
                if self.language == "python":
                    cmd = [self.get_venv_python(), "-m", "pytest", path]
                elif self.language == "nodejs":
                    cmd = ["npm", "test", "--", path]
                else:
                    raise ValueError(f"Unsupported language for test: {self.language}")
                result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
                self.test_results.append(f"Tests for {path}: {'Passed' if result.returncode == 0 else 'Failed'}\n{result.stdout}")
                if result.returncode == 0:
                    logging.info(f"Tests passed for {path}: {result.stdout}")
                else:
                    raise RuntimeError(f"Tests failed for {path}: {result.stderr}")

            elif action == "run_lint":
                tool = task.get("tool")
                fix = task.get("fix", False)
                lint_result = f"Linting {path} with {tool}: "
                if tool == "flake8" and self.language == "python":
                    if fix:
                        cmd_fix = [self.get_venv_python(), "-m", "autopep8", "--in-place", path]
                        result_fix = subprocess.run(cmd_fix, cwd=self.project_root, capture_output=True, text=True)
                        if result_fix.returncode == 0:
                            lint_result += "Fixed issues with autopep8. "
                        else:
                            lint_result += f"Autopep8 failed: {result_fix.stderr}. "
                    cmd = [self.get_venv_python(), "-m", "flake8", path]
                    result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
                    if result.returncode == 0:
                        lint_result += "Passed"
                    else:
                        lint_result += f"Issues found: {result.stdout}"
                elif tool == "eslint" and self.language == "nodejs":
                    cmd = ["eslint", path]
                    if fix:
                        cmd.append("--fix")
                    result = subprocess.run(cmd, cwd=self.project_root, capture_output=True, text=True)
                    if result.returncode == 0:
                        lint_result += "Passed"
                    else:
                        lint_result += f"Issues found: {result.stdout}"
                else:
                    raise ValueError(f"Unsupported linter {tool} for language {self.language}")
                self.linting_results.append(lint_result)
                if feature not in self.features:
                    self.features.append(feature)
                logging.info(lint_result)

            self.task_history.append({
                "task": task,
                "index": task_index,
                "action": action,
                "success": True,
                "api_model": self.api_model,
                "timestamp": datetime.now().isoformat()
            })
            self.task_results[task_index] = True
            return True

        except Exception as e:
            logging.error(f"Failed to execute task {action} on {path}: {e}")
            self.task_history.append({
                "task": task,
                "index": task_index,
                "action": action,
                "success": False,
                "error": str(e),
                "api_model": self.api_model,
                "timestamp": datetime.now().isoformat()
            })
            self.task_results[task_index] = False
            return False

    def execute_tasks(self, tasks):
        """Execute tasks, respecting dependencies and handling failures."""
        valid_tasks = True
        for i, task in enumerate(tasks):
            if not self.validate_task(task, i, tasks):
                logging.error(f"Task {i} from {self.api_model} is invalid, skipping")
                valid_tasks = False
        if not valid_tasks:
            print(f"Iteration {self.current_iteration} at {datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')}: Invalid tasks detected. Retrying with corrected prompt.")
            retry_response = self.send_to_api(self.command, retry=True)
            retry_tasks = retry_response.get("tasks", [])
            if not retry_tasks:
                print("Retry failed. Check logs for details.")
                return False
            return self.execute_tasks(retry_tasks)

        for i, task in enumerate(tasks):
            if not self.execute_task(task, i, tasks):
                logging.info(f"Task {i} from {self.api_model} failed, querying for recovery...")
                recovery_response = self.send_to_api(f"Recover from failed task: {task}", failed_task=task)
                recovery_tasks = recovery_response.get("tasks", [])
                if recovery_tasks:
                    logging.info(f"Executing {len(recovery_tasks)} recovery tasks")
                    self.execute_tasks(recovery_tasks)
                else:
                    logging.warning("No recovery tasks provided")
        return True

    def finalize_project(self):
        """Perform post-execution tasks to prepare the project."""
        if self.language == "nodejs" and not (Path(self.project_root) / "package.json").exists():
            package_json = {
                "name": Path(self.project_root).name,
                "version": "1.0.0",
                "main": "app.js",
                "scripts": {"test": "jest"}
            }
            with open(Path(self.project_root) / "package.json", 'w') as f:
                json.dump(package_json, f, indent=2)
            self.created_files.append("package.json")
            logging.info("Created package.json for Node.js project")

        if self.venv_path:
            cmd = [self.get_venv_python(), "-m", "pip", "install", "--upgrade", "pip"]
            result = subprocess.run(cmd, capture_output=True, text=True)
            if result.returncode == 0:
                logging.info("Updated pip in virtual environment")
            else:
                logging.warning(f"Failed to update pip: {result.stderr}")

        summary_path = Path(self.project_root) / "PROJECT_SUMMARY.md"
        completeness = self.assess_project_completeness()
        summary_content = f"# Project Summary\n\n"
        summary_content += f"- **Project**: {Path(self.project_root).name}\n"
        summary_content += f"- **Directory**: {self.project_root}\n"
        summary_content += f"- **Language**: {self.language}\n"
        summary_content += f"- **Completeness Score**: {completeness['score']}/100\n"
        summary_content += f"- **Features Implemented**: {', '.join(self.features) or 'None'}\n"
        summary_content += f"- **Files Created**:\n"
        for file in self.created_files:
            summary_content += f"  - {file}: {'Main app' if 'app.' in file else 'Test file' if 'test_' in file else 'Documentation' if file.endswith('.md') else 'Other'}\n"
        summary_content += f"- **Dependencies**: {', '.join(self.installed_deps) or 'None'}\n"
        summary_content += f"- **Linting Results**:\n"
        for result in self.linting_results:
            summary_content += f"  - {result}\n"
        summary_content += f"- **Test Results**:\n"
        for result in self.test_results:
            summary_content += f"  - {result}\n"
        summary_content += f"- **Issues**: {', '.join(completeness['issues']) or 'None'}\n"
        summary_content += f"- **Run Instructions**:\n"
        if self.language == "python":
            summary_content += f"  - Activate virtual env: `source {self.venv_path}/bin/activate` (Linux/Mac) or `{self.venv_path}\\Scripts\\activate` (Windows)\n"
            summary_content += f"  - Run tests: `pytest`\n"
            summary_content += f"  - Run app: `python app.py`\n"
        elif self.language == "nodejs":
            summary_content += f"  - Run tests: `npm test`\n"
            summary_content += f"  - Run app: `node app.js`\n"
        summary_content += f"- **Deployment Instructions**:\n"
        summary_content += f"  - Review `Dockerfile` (if present) for containerization.\n"
        summary_content += f"  - Check CI/CD configs (e.g., `.github/workflows`) for deployment pipelines.\n"
        summary_content += f"- **API Usage**:\n"
        summary_content += f"  - Last API used: {self.api_model}\n"
        summary_content += f"  - Total tasks: {len(self.task_history)}\n"

        with open(summary_path, 'w') as f:
            f.write(summary_content)
        self.created_files.append(str(summary_path))
        logging.info(f"Generated project summary: {summary_path}")

        zip_path = f"{self.project_root}.zip"
        with zipfile.ZipFile(zip_path, 'w', zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(self.project_root):
                for file in files:
                    zf.write(os.path.join(root, file), os.path.relpath(os.path.join(root, file), self.project_root))
        logging.info(f"Created project archive: {zip_path}")

    def prompt_user(self):
        """Prompt user for next action."""
        completeness = self.assess_project_completeness()
        timestamp = datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')
        print(f"\nIteration {self.current_iteration} completed at {timestamp} using {self.api_model}")
        print("Project State:")
        print(f"- Directory: {self.project_root}")
        print(f"- Features: {', '.join(self.features) or 'None'}")
        print(f"- Files Created: {len(self.created_files)}")
        print(f"- Dependencies: {', '.join(self.installed_deps) or 'None'}")
        print(f"- Completeness Score: {completeness['score']}/100")
        print(f"- Issues: {', '.join(completeness['issues']) or 'None'}")
        print(f"- Suggested Features: {', '.join(completeness['missing_features']) or 'None'}")
        print("\nOptions:")
        print("1. Continue (API suggests next enhancements)")
        print("2. Add specific feature (e.g., 'add authentication')")
        print("3. Stop and finalize project")
        print("4. Pause (resume later)")
        choice = input("Enter choice (1-4) or feature to add: ").strip().lower()
        logging.info(f"User input: {choice}")
        if choice == "1" or choice == "continue":
            return {"action": "continue", "command": f"Enhance project to be production-ready: {self.command}"}
        elif choice == "2" or choice.startswith("add "):
            feature = choice[4:] if choice.startswith("add ") else input("Enter feature to add: ").strip()
            return {"action": "add_feature", "command": f"Add {feature} to project: {self.command}"}
        elif choice == "3" or choice == "stop":
            return {"action": "stop"}
        elif choice == "4" or choice == "pause":
            return {"action": "pause"}
        else:
            print("Invalid choice. Defaulting to continue.")
            return {"action": "continue", "command": f"Enhance project to be production-ready: {self.command}"}

    def validate_project(self):
        """Validate project integrity."""
        if not self.project_root or not Path(self.project_root).exists():
            logging.error("Project root not set or does not exist")
            return False
        for file in self.created_files:
            if not Path(file).exists():
                logging.error(f"File {file} listed in state does not exist")
                return False
        return True

    def process_command(self, command=None, model_choice=None):
        """Process command with iterative enhancements, resuming from saved state."""
        if not self.validate_environment():
            print("Environment validation failed. Ensure required tools (python, git) are installed.")
            return

        # Select API model
        if model_choice:
            try:
                self.select_api(model_choice)
            except ValueError as e:
                print(e)
                return
        else:
            model_choice = input("Select AI model (gemini/grok): ").strip().lower()
            try:
                self.select_api(model_choice)
            except ValueError as e:
                print(e)
                return

        # Check for saved state
        resumed = False
        if not command and self.load_state():
            if self.command:
                command = self.command
                resumed = True
                print(f"Resuming work on project: {self.command} (iteration {self.current_iteration}) at {datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')} using {self.api_model}")
            else:
                print("No command found in saved state. Please provide a new command.")
                return
        elif command:
            self.clear_state()
            self.command = command
            self.current_iteration = 0
            self.task_results = {}
            self.created_files = []
            self.installed_deps = []
            self.linting_results = []
            self.test_results = []
            self.features = []
            self.task_history = []
            self.file_hashes = {}
            logging.info(f"Starting new project with command: {command} using {self.api_model}")
        else:
            print("No command provided and no saved state found. Please provide a command.")
            return

        # Start iterations
        while True:
            self.current_iteration += 1
            timestamp = datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')
            print(f"Starting iteration {self.current_iteration} at {timestamp} using {self.api_model}")
            logging.info(f"Iteration {self.current_iteration}: Querying {self.api_model} with command: {command}")

            # Query API
            response = self.send_to_api(command)
            tasks = response.get("tasks", [])
            if not tasks:
                print(f"Iteration {self.current_iteration} completed at {timestamp}: No tasks returned. Project may be complete.")
                user_choice = self.prompt_user()
                if user_choice["action"] == "stop":
                    break
                elif user_choice["action"] == "pause":
                    self.save_state()
                    print(f"Work paused at {timestamp}. State saved. Resume by re-running.")
                    return
                else:
                    command = user_choice["command"]
                    continue

            # Execute tasks
            if not self.execute_tasks(tasks):
                print(f"Iteration {self.current_iteration} at {timestamp}: Task execution failed. Check logs.")
                user_choice = self.prompt_user()
                if user_choice["action"] == "stop":
                    break
                elif user_choice["action"] == "pause":
                    self.save_state()
                    print(f"Work paused at {timestamp}. State saved.")
                    return
                else:
                    command = user_choice["command"]
                    continue

            # Validate project
            if not self.validate_project():
                print(f"Iteration {self.current_iteration} at {timestamp}: Project validation failed.")
                user_choice = self.prompt_user()
                if user_choice["action"] == "stop":
                    break
                elif user_choice["action"] == "pause":
                    self.save_state()
                    print(f"Work paused at {timestamp}. State saved.")
                    return
                else:
                    command = user_choice["command"]
                    continue

            # Save state
            self.save_state()

            # Prompt user
            user_choice = self.prompt_user()
            if user_choice["action"] == "stop":
                break
            elif user_choice["action"] == "pause":
                self.save_state()
                print(f"Work paused at {timestamp}. State saved. Resume by re-running.")
                return
            else:
                command = user_choice["command"]

        # Finalize project
        if self.project_root:
            self.finalize_project()
            timestamp = datetime.now().strftime('%I:%M %p %Z, %B %d, %Y')
            print(f"Production-ready project created in {self.project_root} at {timestamp} using {self.api_model}")
            print(f"Summary: {self.project_root}/PROJECT_SUMMARY.md")
            print(f"Archive: {self.project_root}.zip")
            if self.language == "python":
                print(f"Activate virtual env: source {self.venv_path}/bin/activate (Linux/Mac) or {self.venv_path}\\Scripts\\activate (Windows)")
                print("Run tests: pytest")
                print("Run app: python app.py")
            elif self.language == "nodejs":
                print("Run tests: npm test")
                print("Run app: node app.js")
            logging.info(f"Completed project with {len(self.task_history)} tasks for command: {self.command} using {self.api_model}")
            self.clear_state()
        else:
            print("Project creation failed. Check logs for details.")

def main():
    # Replace with your API keys
    GEMINI_API_KEY = "your-gemini-api-key"  # Obtain from Gemini provider
    XAI_API_KEY = "your-xai-api-key"        # Obtain from https://x.ai/api

    agent = SuperAIAgent(GEMINI_API_KEY, XAI_API_KEY)
    command = input("Enter your command (e.g., 'build a web app') or press Enter to resume: ").strip()
    agent.process_command(command if command else None)

if __name__ == "__main__":
    main()
  
