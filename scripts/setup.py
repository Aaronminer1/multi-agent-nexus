#!/usr/bin/env python3
"""
Multi-Agent Nexus: Cross-platform setup script
Created: 2025-07-10
"""

import os
import sys
import json
import time
import platform
import subprocess
import shutil
from pathlib import Path
import threading
import re
import random
import string
import signal
import atexit

# ANSI colors for compatible terminals
class Colors:
    BLUE = '\033[1;34m'
    GREEN = '\033[1;32m'
    YELLOW = '\033[1;33m'
    RED = '\033[1;31m'
    MAGENTA = '\033[1;35m'
    CYAN = '\033[1;36m'
    RESET = '\033[0m'

    @staticmethod
    def supports_color():
        """Check if the terminal supports color."""
        os_name = platform.system()
        if os_name == 'Windows':
            return 'ANSICON' in os.environ or 'WT_SESSION' in os.environ
        return hasattr(sys.stdout, 'isatty') and sys.stdout.isatty()

# Use colors only if supported
def colorize(text, color):
    if Colors.supports_color():
        return f"{color}{text}{Colors.RESET}"
    return text

# Banner and messages
def print_banner():
    banner = """
    ███╗   ███╗██╗   ██╗██╗  ████████╗██╗      █████╗  ██████╗ ███████╗███╗   ██╗████████╗
    ████╗ ████║██║   ██║██║  ╚══██╔══╝██║     ██╔══██╗██╔════╝ ██╔════╝████╗  ██║╚══██╔══╝
    ██╔████╔██║██║   ██║██║     ██║   ██║     ███████║██║  ███╗█████╗  ██╔██╗ ██║   ██║   
    ██║╚██╔╝██║██║   ██║██║     ██║   ██║     ██╔══██║██║   ██║██╔══╝  ██║╚██╗██║   ██║   
    ██║ ╚═╝ ██║╚██████╔╝███████╗██║   ███████╗██║  ██║╚██████╔╝███████╗██║ ╚████║   ██║   
    ╚═╝     ╚═╝ ╚═════╝ ╚══════╝╚═╝   ╚══════╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝╚═╝  ╚═══╝   ╚═╝   
    ====================== NEXUS =====================================================
    """
    print(colorize(banner, Colors.CYAN))
    print(colorize("Cross-platform setup script for Multi-Agent Nexus", Colors.CYAN))
    print("This script will set up your multi-agent collaboration environment.\n")

# Detect operating system
def get_os_info():
    os_name = platform.system()
    if os_name == "Darwin":
        return "macOS", "darwin"
    elif os_name == "Windows":
        return "Windows", "win32"
    else:
        return "Linux", "linux"

# Check for dependencies
def check_dependencies():
    os_type, _ = get_os_info()
    missing_deps = []
    
    print(colorize("[1/5]", Colors.BLUE), "Checking dependencies...")
    
    # Check for jq
    if not shutil.which("jq"):
        missing_deps.append("jq")
    
    # Check for inotify-tools on Linux
    if os_type == "Linux" and not shutil.which("inotifywait"):
        missing_deps.append("inotify-tools")
    
    # Check for fswatch on macOS (alternative to inotify)
    if os_type == "macOS" and not shutil.which("fswatch"):
        missing_deps.append("fswatch")
    
    # Return list of missing dependencies
    return missing_deps

# Install dependencies based on OS
def install_dependencies(missing_deps):
    os_type, _ = get_os_info()
    
    if not missing_deps:
        print(colorize("✓ All dependencies are installed.", Colors.GREEN))
        return True
    
    print(colorize(f"Installing missing dependencies: {', '.join(missing_deps)}", Colors.YELLOW))
    
    try:
        if os_type == "Linux":
            # Try apt-get (Debian/Ubuntu)
            if shutil.which("apt-get"):
                subprocess.run(["sudo", "apt-get", "update"], check=True)
                subprocess.run(["sudo", "apt-get", "install", "-y"] + missing_deps, check=True)
            # Try yum (RHEL/CentOS)
            elif shutil.which("yum"):
                subprocess.run(["sudo", "yum", "install", "-y"] + missing_deps, check=True)
            else:
                print(colorize("Unsupported Linux distribution. Please install dependencies manually:", Colors.RED))
                for dep in missing_deps:
                    print(f"  - {dep}")
                return False
                
        elif os_type == "macOS":
            # Try brew
            if shutil.which("brew"):
                for dep in missing_deps:
                    subprocess.run(["brew", "install", dep], check=True)
            else:
                print(colorize("Homebrew not found. Please install it first:", Colors.RED))
                print("  /bin/bash -c \"$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)\"")
                return False
                
        elif os_type == "Windows":
            # Try chocolatey
            if shutil.which("choco"):
                for dep in missing_deps:
                    # Map Linux package names to Windows equivalents
                    win_pkg = dep
                    if dep == "jq":
                        win_pkg = "jq"
                    elif dep == "inotify-tools":
                        win_pkg = "fswatch"  # Closest Windows equivalent
                    
                    subprocess.run(["choco", "install", "-y", win_pkg], check=True)
            else:
                print(colorize("Chocolatey not found. Please install it first:", Colors.RED))
                print("  https://chocolatey.org/install")
                print("\nOr install these dependencies manually:")
                print("  - jq: https://stedolan.github.io/jq/download/")
                if "inotify-tools" in missing_deps:
                    print("  - For file watching: https://github.com/thekid/inotify-win")
                return False
    except subprocess.CalledProcessError:
        print(colorize("Error installing dependencies. Please install them manually:", Colors.RED))
        for dep in missing_deps:
            print(f"  - {dep}")
        return False
        
    print(colorize("✓ Dependencies installed successfully.", Colors.GREEN))
    return True

# Setup directory structure
def setup_directories():
    print(colorize("[2/5]", Colors.BLUE), "Setting up directory structure...")
    
    # Create logs directory
    os.makedirs("logs", exist_ok=True)
    
    print(colorize("✓ Directory structure set up.", Colors.GREEN))

# Initialize files
def initialize_files():
    print(colorize("[3/5]", Colors.BLUE), "Initializing log files...")
    
    # Create empty event log if it doesn't exist
    if not os.path.exists("events.log"):
        with open("events.log", "w") as f:
            pass
    
    # Create agent status file if it doesn't exist
    if not os.path.exists("agent_status.json"):
        with open("agent_status.json", "w") as f:
            f.write("[]")
    
    # Create communication.md if it doesn't exist
    if not os.path.exists("communication.md"):
        with open("communication.md", "w") as f:
            f.write("# Communication Log\n")
    
    # Create archive.md if it doesn't exist
    if not os.path.exists("archive.md"):
        with open("archive.md", "w") as f:
            f.write("# Archived Communications\n")
    
    print(colorize("✓ Log files initialized.", Colors.GREEN))

# Make scripts executable
def make_scripts_executable():
    print(colorize("[4/5]", Colors.BLUE), "Making scripts executable...")
    
    os_type, _ = get_os_info()
    scripts_dir = Path("scripts")
    
    # Only needed for Unix-like systems
    if os_type != "Windows":
        for script in scripts_dir.glob("*.sh"):
            script_path = str(script)
            os.chmod(script_path, 0o755)
    
    print(colorize("✓ Scripts are now executable.", Colors.GREEN))

# Configure agent
def configure_agent():
    print(colorize("[5/5]", Colors.BLUE), "Configuring your agent...")
    
    agent_id = input("Enter your agent ID (e.g., agent1): ")
    agent_type = input("Enter your agent type (e.g., llm, coding, research): ")
    description = input("Enter a brief agent description: ")
    
    return agent_id, agent_type, description

# Register agent using agent_status.sh
def register_agent(agent_id, agent_type, description):
    os_type, _ = get_os_info()
    
    if os_type == "Windows":
        # Windows might need to use bash.exe or sh.exe with Git Bash
        shell_cmd = "bash.exe" if shutil.which("bash.exe") else "sh.exe"
        subprocess.run([shell_cmd, "scripts/agent_status.sh", "register", agent_id, agent_type, description])
        subprocess.run([shell_cmd, "scripts/agent_status.sh", "status", agent_id, "active", "Starting up and ready for collaboration"])
    else:
        # Unix systems can run the script directly
        subprocess.run(["./scripts/agent_status.sh", "register", agent_id, agent_type, description])
        subprocess.run(["./scripts/agent_status.sh", "status", agent_id, "active", "Starting up and ready for collaboration"])

# Send a message using log_event.sh
def send_message(agent_id, agent_type, message):
    os_type, _ = get_os_info()
    
    json_data = json.dumps({"from": agent_id, "to": "all", "message": message})
    
    if os_type == "Windows":
        shell_cmd = "bash.exe" if shutil.which("bash.exe") else "sh.exe"
        subprocess.run([shell_cmd, "scripts/log_event.sh", "message", json_data])
    else:
        subprocess.run(["./scripts/log_event.sh", "message", json_data])

# Generate snapshot
def generate_snapshot():
    os_type, _ = get_os_info()
    
    if os_type == "Windows":
        shell_cmd = "bash.exe" if shutil.which("bash.exe") else "sh.exe"
        subprocess.run([shell_cmd, "scripts/generate_snapshot.sh"])
    else:
        subprocess.run(["./scripts/generate_snapshot.sh"])

# Start background monitoring thread
def start_monitoring():
    print(colorize("\nStarting system services...", Colors.MAGENTA))
    
    os_type, _ = get_os_info()
    
    # Kill any existing monitoring processes
    if os_type != "Windows":
        try:
            subprocess.run(["pkill", "-f", "scripts/watch_events.sh"], stderr=subprocess.DEVNULL)
        except:
            pass
    
    # Start monitoring based on OS
    if os_type == "Windows":
        # Windows needs a different approach
        print("Starting event monitoring in a new window...")
        if shutil.which("start"):
            # Use cmd's start command
            subprocess.Popen(["start", "bash.exe", "scripts/watch_events.sh"], shell=True)
        else:
            print(colorize("Warning: Unable to start monitoring automatically.", Colors.YELLOW))
            print("Please open a new terminal and run: bash.exe scripts/watch_events.sh")
    
    elif os_type == "Linux" or os_type == "macOS":
        # Unix-like systems
        terminal_options = []
        
        # Try screen
        if shutil.which("screen"):
            print("Starting event monitor in screen session...")
            subprocess.run(["screen", "-dmS", "event_monitor", "./scripts/watch_events.sh"])
            subprocess.run(["screen", "-dmS", "agent_monitor", "watch", "-n", "10", "./scripts/agent_status.sh", "list"])
            terminal_options.append("screen")
            
        # Try tmux
        elif shutil.which("tmux"):
            print("Starting event monitor in tmux session...")
            subprocess.run(["tmux", "new-session", "-d", "-s", "event_monitor", "./scripts/watch_events.sh"])
            subprocess.run(["tmux", "new-session", "-d", "-s", "agent_monitor", "watch -n 10 ./scripts/agent_status.sh list"])
            terminal_options.append("tmux")
            
        # Fallback to background process
        else:
            print("Starting event monitor in background...")
            subprocess.Popen(["./scripts/watch_events.sh"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            
        if not terminal_options:
            print(colorize("NOTE: Install 'screen' or 'tmux' for better background process management.", Colors.YELLOW))
            
    return True

# Start heartbeat process
def start_heartbeat(agent_id):
    os_type, _ = get_os_info()
    
    # Clean up any existing heartbeat process
    heartbeat_pid_file = f".heartbeat_{agent_id}.pid"
    if os.path.exists(heartbeat_pid_file):
        try:
            with open(heartbeat_pid_file, 'r') as f:
                pid = int(f.read().strip())
            try:
                os.kill(pid, signal.SIGTERM)
            except:
                pass
            os.remove(heartbeat_pid_file)
        except:
            pass
    
    print("Starting automatic heartbeat...")
    
    # Define heartbeat function
    def heartbeat_thread():
        while True:
            try:
                if os_type == "Windows":
                    shell_cmd = "bash.exe" if shutil.which("bash.exe") else "sh.exe"
                    subprocess.run([shell_cmd, "scripts/agent_status.sh", "heartbeat", agent_id], 
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
                else:
                    subprocess.run(["./scripts/agent_status.sh", "heartbeat", agent_id],
                                  stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            except:
                pass
            time.sleep(60)
    
    # Start heartbeat thread
    heartbeat = threading.Thread(target=heartbeat_thread, daemon=True)
    heartbeat.start()
    
    # Register thread for cleanup
    atexit.register(lambda: print("Heartbeat stopped."))
    
    return True

# Show quick reference
def show_quick_reference(agent_id):
    os_type, _ = get_os_info()
    
    print(colorize("\n=== Quick Reference Commands ===", Colors.YELLOW))
    
    cmd_prefix = ""
    if os_type == "Windows":
        shell_cmd = "bash.exe" if shutil.which("bash.exe") else "sh.exe"
        cmd_prefix = f"{shell_cmd} "
    
    # Create command strings first to avoid complex nested f-strings
    msg_cmd = f"{cmd_prefix}scripts/log_event.sh message '{{\"from\":\"{agent_id}\",\"to\":\"all\",\"message\":\"Hello\"}}'"
    print(f"  Send message:     {colorize(msg_cmd, Colors.CYAN)}")
    
    prop_cmd = f"{cmd_prefix}scripts/log_event.sh proposal '{{\"from\":\"{agent_id}\",\"component\":\"X\",\"description\":\"Y\"}}'"
    print(f"  Make proposal:    {colorize(prop_cmd, Colors.CYAN)}")
    
    status_cmd = f"{cmd_prefix}scripts/agent_status.sh status {agent_id} active \"Working on task X\""
    print(f"  Update status:    {colorize(status_cmd, Colors.CYAN)}")
    
    print(f"  View messages:    {colorize('cat communication.md', Colors.CYAN)}")
    
    agents_cmd = f"{cmd_prefix}scripts/agent_status.sh list"
    print(f"  List agents:      {colorize(agents_cmd, Colors.CYAN)}")
    
    snapshot_cmd = f"{cmd_prefix}scripts/generate_snapshot.sh"
    print(f"  Generate snapshot: {colorize(snapshot_cmd, Colors.CYAN)}\n")

def main():
    # Display welcome banner
    print_banner()
    
    # Get OS information
    os_type, os_platform = get_os_info()
    print(f"Detected operating system: {colorize(os_type, Colors.CYAN)}\n")
    
    # Check and install dependencies
    missing_deps = check_dependencies()
    if missing_deps and not install_dependencies(missing_deps):
        print(colorize("\nSetup cannot continue without required dependencies.", Colors.RED))
        print("Please install them manually and run this script again.")
        return 1
    
    # Setup directories
    setup_directories()
    
    # Initialize files
    initialize_files()
    
    # Make scripts executable
    make_scripts_executable()
    
    # Configure agent
    agent_id, agent_type, description = configure_agent()
    
    # Start monitoring
    start_monitoring()
    
    # Register agent
    register_agent(agent_id, agent_type, description)
    
    # Start heartbeat
    start_heartbeat(agent_id)
    
    # Send welcome message
    send_message(agent_id, agent_type, f"{agent_type} agent '{agent_id}' has joined the collaboration.")
    
    # Generate initial snapshot
    generate_snapshot()
    
    print(colorize("\n✓ Setup complete!", Colors.GREEN))
    print(f"Your agent ID: {colorize(agent_id, Colors.CYAN)} is registered and active.")
    print("Event monitoring is running in the background.")
    print("You can now begin collaborating with other agents.\n")
    
    # Show quick reference
    show_quick_reference(agent_id)
    
    print(colorize("You're all set! Happy collaborating!\n", Colors.GREEN))
    return 0

if __name__ == "__main__":
    sys.exit(main())
