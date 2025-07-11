#!/usr/bin/env bash
# 2025-07-08: Helper script for logging events to the append-only events.log file with error handling and resilience
# 2025-07-10: Updated with automatic interaction ID generation and improved special character handling

# Usage: log_event.sh <event_type> <content>
LOGFILE="$(pwd)/events.log"
OFFLINE_LOGFILE="$(pwd)/events.offline.log"
MAX_RETRIES=3
RETRY_DELAY=1
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to get the next interaction ID
get_next_interaction_id() {
  local last_id=0
  
  # If log file exists, get the highest interaction ID
  if [ -f "$LOGFILE" ]; then
    # Extract the highest interaction ID using jq
    last_id=$(jq -r '.interaction' "$LOGFILE" 2>/dev/null | sort -n | tail -1 || echo 0)
    
    # If not a number or empty, set to 0
    if ! [[ "$last_id" =~ ^[0-9]+$ ]]; then
      last_id=0
    fi
  fi
  
  # Return next ID
  echo $((last_id + 1))
}

# Function to log error events
log_error() {
  local error_msg="$1"
  local error_source="$2"
  local error_event
  local error_time
  local error_id
  
  error_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  error_id=$(get_next_interaction_id)
  
  error_event=$(jq -n --compact-output \
    --arg i "$error_id" \
    --arg actor "system" \
    --arg type "error" \
    --arg content "$error_msg" \
    --arg source "$error_source" \
    --arg timestamp "$error_time" \
    '{interaction: ($i|tonumber), actor: $actor, type: "error", content: $content, source: $source, timestamp: $timestamp}')
  
  # Try to write the error directly without lock - this is a fallback mechanism
  printf "%s\n" "$error_event" >> "$LOGFILE" 2>/dev/null
  echo "ERROR: $error_msg" >&2
}

# Validate inputs
if [ $# -ne 2 ]; then
  echo "ERROR: Incorrect number of arguments" >&2
  echo "Usage: $0 <event_type> <json_content>" >&2
  echo "Example: $0 \"message\" '{\"from\":\"agent-1\",\"message\":\"Hello\",\"to\":\"all\"}'" >&2
  exit 1
fi

# Ensure logfile directory exists
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null

# Get event type and content
event_type="$1"
json_content="$2"

# Validate JSON content
if ! echo "$json_content" | jq empty > /dev/null 2>&1; then
  echo "ERROR: Invalid JSON content" >&2
  echo "Content must be a valid JSON string" >&2
  echo "Example: '{\"from\":\"agent-1\",\"message\":\"Hello\",\"to\":\"all\"}'" >&2
  exit 1
fi

# Get next interaction ID
interaction_id=$(get_next_interaction_id)

# Use jq to create properly formatted JSON
# The --argjson flag in jq properly handles nested JSON content
event=$(jq -n --compact-output \
  --arg i "$interaction_id" \
  --arg type "$event_type" \
  --argjson content "$json_content" \
  --arg timestamp "$timestamp" \
  '{interaction: ($i|tonumber), type: $type, content: $content, timestamp: $timestamp}')

# Check if JSON creation was successful
if [ $? -ne 0 ]; then
  log_error "Failed to create JSON event data" "log_event.sh"
  echo "ERROR: Failed to process event data" >&2
  echo "This could be due to malformed JSON or special characters" >&2
  exit 1
fi

# Retry loop for lock contention
retries=0
success=false
while [ $retries -lt $MAX_RETRIES ] && [ "$success" != "true" ]; do
  # Append under lock with timeout to prevent indefinite blocking
  if flock --exclusive --timeout=2 "$LOGFILE" bash -c "printf '%s\n' '$event' >> '$LOGFILE'"; then
    success=true
  else
    retries=$((retries + 1))
    echo "Lock contention on $LOGFILE, retry $retries/$MAX_RETRIES" >&2
    sleep $((RETRY_DELAY * retries))  # Exponential backoff
  fi
done

# Handle lock failure
if [ "$success" != "true" ]; then
  # Log to offline file as fallback
  printf "%s\n" "$event" >> "$OFFLINE_LOGFILE"
  log_error "Failed to acquire lock on events.log after $MAX_RETRIES attempts" "log_event.sh"
  echo "WARNING: Event was saved to offline log and will be merged later" >&2
  exit 2
fi

# Check for offline events to merge
if [ -s "$OFFLINE_LOGFILE" ]; then
  echo "Found offline events, attempting to merge..." >&2
  if flock --exclusive --timeout=5 "$LOGFILE" bash -c "cat '$OFFLINE_LOGFILE' >> '$LOGFILE' && rm '$OFFLINE_LOGFILE'"; then
    echo "Successfully merged offline events" >&2
  fi
fi

# Return success
exit 0
