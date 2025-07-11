#!/usr/bin/env bash
# 2025-07-08: Watcher script to automatically generate snapshots when events.log changes
# 2025-07-10: Added real-time event summaries and notification features

EVENTS_LOG="$(pwd)/events.log"
SCRIPT_DIR="$(dirname "$0")"
GENERATE_SNAPSHOT="${SCRIPT_DIR}/generate_snapshot.sh"
SNAPSHOT_JSON="$(pwd)/latest_snapshot.json"
LAST_PROCESSED_LINE=0
SUMMARY_INTERVAL=10  # How often to show summary (in seconds)
VERBOSE=true         # Show detailed event notifications by default

# Process command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --quiet|-q)
      VERBOSE=false
      shift
      ;;
    --summary-interval=*)
      SUMMARY_INTERVAL="${1#*=}"
      shift
      ;;
    --help|-h)
      echo "Usage: $0 [OPTIONS]"
      echo "Options:"
      echo "  --quiet, -q           Reduce verbosity, only show summaries"
      echo "  --summary-interval=N  Set summary interval in seconds (default: $SUMMARY_INTERVAL)"
      echo "  --help, -h            Show this help message"
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      echo "Use --help for usage information" >&2
      exit 1
      ;;
  esac
done

# Print colorful header
echo -e "\033[1;34m========================================\033[0m"
echo -e "\033[1;32m  Event Log Watcher & Notifier Started  \033[0m"
echo -e "\033[1;34m========================================\033[0m"
echo -e "\033[1mMonitoring:\033[0m $EVENTS_LOG"
echo -e "\033[1mGenerating snapshots with:\033[0m $GENERATE_SNAPSHOT"
echo -e "\033[1mVerbose mode:\033[0m $VERBOSE"
echo -e "\033[1mSummary interval:\033[0m Every $SUMMARY_INTERVAL seconds"
echo -e "\033[1;33mPress Ctrl+C to stop\033[0m"

# Function to check dependencies
check_dependencies() {
  local missing_deps=false
  
  # Check for inotifywait
  if ! command -v inotifywait &> /dev/null; then
    echo -e "\033[1;31mError:\033[0m inotifywait not found. Please install inotify-tools:\033[0m"
    echo "  sudo apt-get install inotify-tools"
    missing_deps=true
  fi
  
  # Check for jq
  if ! command -v jq &> /dev/null; then
    echo -e "\033[1;31mError:\033[0m jq not found. Please install jq:\033[0m"
    echo "  sudo apt-get install jq"
    missing_deps=true
  fi
  
  if [ "$missing_deps" = true ]; then
    exit 1
  fi
}

# Check dependencies
check_dependencies

# Function to display a single event in a human-readable format
display_event() {
  local event_json="$1"
  local interaction_id=$(echo "$event_json" | jq -r '.interaction')
  local timestamp=$(echo "$event_json" | jq -r '.timestamp')
  local event_type=$(echo "$event_json" | jq -r '.type')
  local content=$(echo "$event_json" | jq -r '.content')
  
  # Format the timestamp for display
  local display_time=$(date -d "$timestamp" +"%H:%M:%S" 2>/dev/null || echo "$timestamp")
  
  echo -e "\033[1;36m[$display_time]\033[0m \033[1;33mInteraction #$interaction_id\033[0m - \033[1;35m$event_type\033[0m"
  
  # Format different event types appropriately
  case "$event_type" in
    message)
      local from=$(echo "$content" | jq -r '.from // "unknown"')
      local to=$(echo "$content" | jq -r '.to // "all"')
      local message=$(echo "$content" | jq -r '.message // "No message"')
      
      if [ "$to" = "all" ]; then
        echo -e "  \033[1;32m$from\033[0m (to everyone): $message"
      else
        echo -e "  \033[1;32m$from\033[0m → \033[1;32m$to\033[0m: $message"
      fi
      ;;
      
    agent_registration)
      local agent_id=$(echo "$content" | jq -r '.agent_id // "unknown"')
      local agent_type=$(echo "$content" | jq -r '.agent_type // "unknown"')
      
      echo -e "  New agent: \033[1;32m$agent_id\033[0m (Type: $agent_type)"
      ;;
      
    error)
      local source=$(echo "$content" | jq -r '.source // "unknown"')
      local error_msg=$(echo "$content" | jq -r '.message // .content // "Unknown error"')
      
      echo -e "  \033[1;31mERROR\033[0m from $source: $error_msg"
      ;;
      
    *)
      # For other event types, show a brief summary
      local summary=$(echo "$content" | jq -r 'if type == "object" then "(structured data)" else . end' | head -c 60)
      if [ ${#summary} -gt 60 ]; then
        summary="${summary}..."
      fi
      echo -e "  $summary"
      ;;
  esac
  echo ""
}

# Function to generate a periodic summary
generate_summary() {
  if [ ! -f "$SNAPSHOT_JSON" ]; then
    echo -e "\033[1;33mNo snapshot data available yet\033[0m"
    return
  fi
  
  local total_events=$(jq '.metadata.event_count // 0' "$SNAPSHOT_JSON" 2>/dev/null || echo 0)
  local total_interactions=$(jq '.recent_interactions | length' "$SNAPSHOT_JSON" 2>/dev/null || echo 0)
  local agent_count=$(jq '[.all_events[] | select(.type == "agent_registration") | .content.agent_id] | unique | length' "$SNAPSHOT_JSON" 2>/dev/null || echo 0)
  local message_count=$(jq '[.all_events[] | select(.type == "message")] | length' "$SNAPSHOT_JSON" 2>/dev/null || echo 0)
  local error_count=$(jq '[.all_events[] | select(.type == "error")] | length' "$SNAPSHOT_JSON" 2>/dev/null || echo 0)
  
  echo -e "\033[1;34m=== Event Log Summary ===\033[0m"
  echo -e "Total events: \033[1;33m$total_events\033[0m"
  echo -e "Total interactions: \033[1;33m$total_interactions\033[0m"
  echo -e "Registered agents: \033[1;33m$agent_count\033[0m"
  echo -e "Messages: \033[1;33m$message_count\033[0m"
  if [ "$error_count" -gt 0 ]; then
    echo -e "Errors: \033[1;31m$error_count\033[0m"
  fi
  echo ""
  
  # Show the most recent event
  local recent_event=$(jq '.all_events[-1]' "$SNAPSHOT_JSON" 2>/dev/null)
  if [ -n "$recent_event" ] && [ "$recent_event" != "null" ]; then
    echo -e "\033[1;34m=== Most Recent Event ===\033[0m"
    display_event "$recent_event"
  fi
}

# Process new events from the log file
process_new_events() {
  local current_lines=$(wc -l < "$EVENTS_LOG" 2>/dev/null || echo 0)
  local new_events=0
  
  # If there are new lines to process
  if [ "$current_lines" -gt "$LAST_PROCESSED_LINE" ]; then
    if [ "$VERBOSE" = true ]; then
      echo -e "\033[1;34m=== New Events ===\033[0m"
      
      # Extract and display new events
      local line_num=$((LAST_PROCESSED_LINE + 1))
      while [ "$line_num" -le "$current_lines" ]; do
        local event_json=$(sed -n "${line_num}p" "$EVENTS_LOG")
        if [ -n "$event_json" ]; then
          display_event "$event_json"
          new_events=$((new_events + 1))
        fi
        line_num=$((line_num + 1))
      done
    else
      new_events=$((current_lines - LAST_PROCESSED_LINE))
      echo -e "\033[1;34m[$new_events new event(s)]\033[0m"
    fi
    
    LAST_PROCESSED_LINE=$current_lines
  fi
  
  return $new_events
}

# Main watch loop
echo -e "\033[1;32mInitial snapshot generation...\033[0m"
"$GENERATE_SNAPSHOT" >/dev/null 2>&1
generate_summary

# Set up interval summary timer
last_summary_time=$(date +%s)

while true; do
  # Wait for file changes
  inotifywait -q -e close_write "$EVENTS_LOG" >/dev/null 2>&1 && {
    # Generate a new snapshot
    "$GENERATE_SNAPSHOT" >/dev/null 2>&1
    
    # Process and display new events
    process_new_events
    new_events=$?
    
    # Check if it's time for a summary
    current_time=$(date +%s)
    time_since_summary=$((current_time - last_summary_time))
    
    if [ $time_since_summary -ge $SUMMARY_INTERVAL ]; then
      generate_summary
      last_summary_time=$current_time
    fi
  }
done
