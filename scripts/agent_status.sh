#!/usr/bin/env bash
# 2025-07-10: Agent status reporting tool for multi-agent communication system
# Provides heartbeat and status reporting mechanisms for agents

# Default paths and settings
EVENTS_LOG="$(pwd)/events.log"
STATUS_FILE="$(pwd)/agent_status.json"
SCRIPT_DIR="$(dirname "$0")"
LOG_EVENT="${SCRIPT_DIR}/log_event.sh"

# Ensure the status file exists with proper structure
init_status_file() {
  if [ ! -f "$STATUS_FILE" ]; then
    echo '{
      "updated_at": "'"$(date -Iseconds)"'",
      "agents": {}
    }' > "$STATUS_FILE"
  fi
}

# Display usage information
show_usage() {
  echo "Usage: $0 <command> [options]"
  echo ""
  echo "Commands:"
  echo "  register <agent_id> <agent_type> [capabilities...]  Register a new agent"
  echo "  heartbeat <agent_id>                               Send a heartbeat for an agent"
  echo "  status <agent_id> <status_code> [message]          Update agent status"
  echo "  list                                              List all registered agents and their status"
  echo "  view <agent_id>                                   View detailed status for a specific agent"
  echo ""
  echo "Status Codes:"
  echo "  active    - Agent is currently running and ready"
  echo "  idle      - Agent is running but not actively working"
  echo "  busy      - Agent is actively working on a task"
  echo "  waiting   - Agent is waiting for input or a dependency"
  echo "  error     - Agent encountered an error"
  echo "  offline   - Agent is not currently running"
  echo ""
  echo "Examples:"
  echo "  $0 register gemini-agent llm code-generation,reasoning"
  echo "  $0 heartbeat gemini-agent"
  echo "  $0 status gemini-agent busy \"Working on task #123\""
  echo "  $0 list"
}

# Register a new agent
register_agent() {
  if [ $# -lt 2 ]; then
    echo "ERROR: Missing required arguments for agent registration" >&2
    echo "Usage: $0 register <agent_id> <agent_type> [capabilities...]" >&2
    exit 1
  fi
  
  local agent_id="$1"
  local agent_type="$2"
  shift 2
  local capabilities=("$@")
  
  # Create the agent registration content
  local capabilities_json="[]"
  if [ ${#capabilities[@]} -gt 0 ]; then
    capabilities_json=$(printf '"%s",' "${capabilities[@]}" | sed 's/,$//')
    capabilities_json="[$capabilities_json]"
  fi
  
  # Register in the status file
  init_status_file
  local timestamp=$(date -Iseconds)
  local status_content='{
    "agent_id": "'"$agent_id"'",
    "agent_type": "'"$agent_type"'",
    "capabilities": '"$capabilities_json"',
    "status": "active",
    "last_heartbeat": "'"$timestamp"'",
    "registered_at": "'"$timestamp"'",
    "message": "Agent registered"
  }'
  
  # Update status file
  jq --arg id "$agent_id" --argjson data "$status_content" '.agents[$id] = $data | .updated_at = "'"$timestamp"'"' "$STATUS_FILE" > "${STATUS_FILE}.tmp" && 
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
  
  # Log the registration event
  "$LOG_EVENT" "agent_registration" "$status_content"
  
  echo "Agent $agent_id registered successfully"
}

# Update agent heartbeat
send_heartbeat() {
  if [ $# -lt 1 ]; then
    echo "ERROR: Missing agent ID for heartbeat" >&2
    echo "Usage: $0 heartbeat <agent_id>" >&2
    exit 1
  fi
  
  local agent_id="$1"
  local timestamp=$(date -Iseconds)
  
  # Check if agent exists
  if ! jq -e --arg id "$agent_id" '.agents[$id]' "$STATUS_FILE" > /dev/null 2>&1; then
    echo "ERROR: Agent $agent_id is not registered" >&2
    echo "Please register the agent first with: $0 register $agent_id <type> [capabilities...]" >&2
    exit 1
  fi
  
  # Update heartbeat
  jq --arg id "$agent_id" --arg time "$timestamp" \
    '.agents[$id].last_heartbeat = $time | .updated_at = $time' \
    "$STATUS_FILE" > "${STATUS_FILE}.tmp" && 
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
  
  # Log heartbeat event (only if verbose)
  if [ -n "$VERBOSE_HEARTBEAT" ]; then
    local heartbeat_content="{\"agent_id\":\"$agent_id\",\"timestamp\":\"$timestamp\"}"
    "$LOG_EVENT" "heartbeat" "$heartbeat_content" > /dev/null 2>&1
  fi
  
  echo "Heartbeat recorded for $agent_id"
}

# Update agent status
update_status() {
  if [ $# -lt 2 ]; then
    echo "ERROR: Missing required arguments for status update" >&2
    echo "Usage: $0 status <agent_id> <status_code> [message]" >&2
    exit 1
  fi
  
  local agent_id="$1"
  local status_code="$2"
  local message="${3:-No status message provided}"
  local timestamp=$(date -Iseconds)
  
  # Validate status code
  case "$status_code" in
    active|idle|busy|waiting|error|offline) 
      ;; # Valid status
    *)
      echo "ERROR: Invalid status code: $status_code" >&2
      echo "Valid codes: active, idle, busy, waiting, error, offline" >&2
      exit 1
      ;;
  esac
  
  # Check if agent exists
  if ! jq -e --arg id "$agent_id" '.agents[$id]' "$STATUS_FILE" > /dev/null 2>&1; then
    echo "ERROR: Agent $agent_id is not registered" >&2
    echo "Please register the agent first with: $0 register $agent_id <type> [capabilities...]" >&2
    exit 1
  fi
  
  # Update status
  jq --arg id "$agent_id" --arg status "$status_code" --arg msg "$message" --arg time "$timestamp" \
    '.agents[$id].status = $status | .agents[$id].message = $msg | .agents[$id].last_heartbeat = $time | .updated_at = $time' \
    "$STATUS_FILE" > "${STATUS_FILE}.tmp" && 
    mv "${STATUS_FILE}.tmp" "$STATUS_FILE"
  
  # Log status update event
  local status_content="{\"agent_id\":\"$agent_id\",\"status\":\"$status_code\",\"message\":\"$message\"}"
  "$LOG_EVENT" "agent_status" "$status_content"
  
  echo "Status updated for $agent_id: $status_code - $message"
}

# List all agents and their status
list_agents() {
  init_status_file
  
  echo -e "\033[1;34m=== Agent Status Overview ===\033[0m"
  echo -e "\033[1mLast updated:\033[0m $(jq -r '.updated_at' "$STATUS_FILE")"
  echo ""
  
  # Get agent count
  local agent_count=$(jq '.agents | length' "$STATUS_FILE")
  
  if [ "$agent_count" -eq 0 ]; then
    echo "No agents registered yet."
    return
  fi
  
  # Display agents with color-coded status
  echo -e "\033[1mID\033[0m                  \033[1mType\033[0m        \033[1mStatus\033[0m     \033[1mLast Heartbeat\033[0m         \033[1mMessage\033[0m"
  echo "------------------------------------------------------------------------------------------------------"
  
  jq -r '.agents | to_entries[] | 
    [.key, .value.agent_type, .value.status, .value.last_heartbeat, .value.message] | 
    @tsv' "$STATUS_FILE" | 
  while IFS=$'\t' read -r id type status last_hb message; do
    # Format heartbeat as relative time
    local now=$(date +%s)
    local hb_time=$(date -d "$last_hb" +%s 2>/dev/null)
    local time_diff=$((now - hb_time))
    
    if [ $time_diff -lt 60 ]; then
      hb_display="just now"
    elif [ $time_diff -lt 3600 ]; then
      hb_display="$((time_diff / 60))m ago"
    elif [ $time_diff -lt 86400 ]; then
      hb_display="$((time_diff / 3600))h ago"
    else
      hb_display="$((time_diff / 86400))d ago"
    fi
    
    # Color code based on status
    case "$status" in
      active)  status_color="\033[1;32m$status\033[0m";;  # Green
      idle)    status_color="\033[1;36m$status\033[0m";;  # Cyan
      busy)    status_color="\033[1;33m$status\033[0m";;  # Yellow
      waiting) status_color="\033[1;34m$status\033[0m";;  # Blue
      error)   status_color="\033[1;31m$status\033[0m";;  # Red
      offline) status_color="\033[1;30m$status\033[0m";;  # Gray
      *)       status_color="$status";;
    esac
    
    # Truncate message if too long
    if [ ${#message} -gt 30 ]; then
      message="${message:0:27}..."
    fi
    
    printf "%-20s %-12s %-10s %-22s %s\n" "$id" "$type" "$status_color" "$hb_display" "$message"
  done
}

# View detailed status for a specific agent
view_agent() {
  if [ $# -lt 1 ]; then
    echo "ERROR: Missing agent ID" >&2
    echo "Usage: $0 view <agent_id>" >&2
    exit 1
  fi
  
  local agent_id="$1"
  
  # Check if agent exists
  if ! jq -e --arg id "$agent_id" '.agents[$id]' "$STATUS_FILE" > /dev/null 2>&1; then
    echo "ERROR: Agent $agent_id is not registered" >&2
    exit 1
  fi
  
  # Extract and display agent details
  local agent_data=$(jq --arg id "$agent_id" '.agents[$id]' "$STATUS_FILE")
  local agent_type=$(echo "$agent_data" | jq -r '.agent_type')
  local status=$(echo "$agent_data" | jq -r '.status')
  local last_hb=$(echo "$agent_data" | jq -r '.last_heartbeat')
  local registered=$(echo "$agent_data" | jq -r '.registered_at')
  local message=$(echo "$agent_data" | jq -r '.message')
  local capabilities=$(echo "$agent_data" | jq -r '.capabilities | join(", ")')
  
  echo -e "\033[1;34m=== Agent Details: $agent_id ===\033[0m"
  echo -e "\033[1mAgent Type:\033[0m       $agent_type"
  
  # Color code based on status
  case "$status" in
    active)  status_display="\033[1;32m$status\033[0m";;  # Green
    idle)    status_display="\033[1;36m$status\033[0m";;  # Cyan
    busy)    status_display="\033[1;33m$status\033[0m";;  # Yellow
    waiting) status_display="\033[1;34m$status\033[0m";;  # Blue
    error)   status_display="\033[1;31m$status\033[0m";;  # Red
    offline) status_display="\033[1;30m$status\033[0m";;  # Gray
    *)       status_display="$status";;
  esac
  
  echo -e "\033[1mStatus:\033[0m           $status_display"
  echo -e "\033[1mRegistered At:\033[0m    $registered"
  echo -e "\033[1mLast Heartbeat:\033[0m   $last_hb"
  echo -e "\033[1mCapabilities:\033[0m     $capabilities"
  echo -e "\033[1mStatus Message:\033[0m   $message"
  
  # Calculate heartbeat age
  local now=$(date +%s)
  local hb_time=$(date -d "$last_hb" +%s 2>/dev/null)
  local time_diff=$((now - hb_time))
  local seconds=$((time_diff % 60))
  local minutes=$(((time_diff / 60) % 60))
  local hours=$(((time_diff / 3600) % 24))
  local days=$((time_diff / 86400))
  
  echo -e "\033[1mHeartbeat Age:\033[0m    ${days}d ${hours}h ${minutes}m ${seconds}s"
  
  # Determine if agent is considered responsive based on heartbeat
  if [ $time_diff -gt 300 ]; then  # More than 5 minutes
    echo -e "\033[1mResponsiveness:\033[0m   \033[1;31mUnresponsive (no heartbeat in over 5 minutes)\033[0m"
  elif [ $time_diff -gt 60 ]; then  # More than 1 minute
    echo -e "\033[1mResponsiveness:\033[0m   \033[1;33mDelayed (no heartbeat in over 1 minute)\033[0m"
  else
    echo -e "\033[1mResponsiveness:\033[0m   \033[1;32mResponsive\033[0m"
  fi
}

# Initialize status file
init_status_file

# Process command line arguments
if [ $# -eq 0 ]; then
  show_usage
  exit 1
fi

command="$1"
shift

case "$command" in
  register)
    register_agent "$@"
    ;;
  heartbeat)
    send_heartbeat "$@"
    ;;
  status)
    update_status "$@"
    ;;
  list)
    list_agents
    ;;
  view)
    view_agent "$@"
    ;;
  help|--help|-h)
    show_usage
    ;;
  *)
    echo "ERROR: Unknown command: $command" >&2
    show_usage
    exit 1
    ;;
esac
