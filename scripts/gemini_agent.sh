#!/usr/bin/env bash
# 2025-07-08: Gemini agent integration script for event-log system

# Configuration
AGENT_ID="Agent-Gemini"
PROJECT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
EVENTS_LOG="${PROJECT_DIR}/events.log"
COMM_FILE="${PROJECT_DIR}/communication.md"
LOG_EVENT="${PROJECT_DIR}/scripts/log_event.sh"
GENERATE_SNAPSHOT="${PROJECT_DIR}/scripts/generate_snapshot.sh"

# Find the latest interaction ID or start with 1
get_latest_interaction() {
  if [ -s "$EVENTS_LOG" ]; then
    latest=$(jq -r '.interaction' "$EVENTS_LOG" 2>/dev/null | sort -n | tail -n1)
    echo "${latest:-1}"
  else
    echo "1"
  fi
}

# Create a new interaction (question)
new_question() {
  interaction=$(get_latest_interaction)
  # For questions, increment the interaction ID
  interaction=$((interaction + 1))
  
  # Log the event
  "$LOG_EVENT" "$interaction" "$AGENT_ID" "question" "$*"
  
  # Generate snapshot
  "$GENERATE_SNAPSHOT"
  
  # Show the updated communication
  echo -e "\n--- Updated Communication File ---"
  cat "$COMM_FILE"
  echo -e "-------------------------------\n"
  
  # Return the interaction ID for follow-up
  echo "$interaction"
}

# Respond to an existing interaction
respond() {
  interaction="$1"
  shift
  
  # Log the response
  "$LOG_EVENT" "$interaction" "$AGENT_ID" "answer" "$*"
  
  # Generate snapshot
  "$GENERATE_SNAPSHOT"
  
  # Show the updated communication
  echo -e "\n--- Updated Communication File ---"
  cat "$COMM_FILE"
  echo -e "-------------------------------\n"
}

# Print usage instructions
usage() {
  echo "Gemini Agent Integration for Event-Log System"
  echo ""
  echo "Usage:"
  echo "  $0 ask \"Your question here\"       # Create a new interaction with a question"
  echo "  $0 respond ID \"Your answer here\"  # Respond to an existing interaction"
  echo "  $0 show                           # Display the current communication file"
  echo ""
  echo "Examples:"
  echo "  $0 ask \"How do I start the MCP server?\""
  echo "  $0 respond 3 \"You can start it with npm start\""
}

# Main command router
case "$1" in
  ask)
    shift
    if [ -z "$1" ]; then
      echo "Error: No question provided"
      usage
      exit 1
    fi
    new_question "$*"
    ;;
    
  respond)
    shift
    interaction="$1"
    shift
    if [ -z "$interaction" ] || [ -z "$1" ]; then
      echo "Error: Missing interaction ID or response"
      usage
      exit 1
    fi
    respond "$interaction" "$*"
    ;;
    
  show)
    cat "$COMM_FILE"
    ;;
    
  *)
    usage
    ;;
esac

exit 0
