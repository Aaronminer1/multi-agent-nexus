#!/usr/bin/env bash
# 2025-07-08: Helper script for logging events to the append-only events.log file with error handling and resilience

# Usage: log_event.sh <interaction> <actor> <type> <content>
LOGFILE="$(pwd)/events.log"
OFFLINE_LOGFILE="$(pwd)/events.offline.log"
MAX_RETRIES=3
RETRY_DELAY=1
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Function to log error events
log_error() {
  local error_msg="$1"
  local error_event
  local error_time
  error_time=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
  error_event=$(jq -n --compact-output \
    --arg i "$1" \
    --arg actor "$2" \
    --arg type "error" \
    --arg content "$error_msg" \
    --arg timestamp "$error_time" \
    '{interaction: ($i|tonumber), actor: $actor, type: "error", content: $content, timestamp: $timestamp}')
  
  # Try to write the error directly without lock - this is a fallback mechanism
  printf "%s\n" "$error_event" >> "$LOGFILE" 2>/dev/null
  echo "ERROR: $error_msg" >&2
}

# Validate inputs
if [ $# -ne 4 ]; then
  echo "Usage: $0 <interaction> <actor> <type> <content>" >&2
  exit 1
fi

# Ensure logfile directory exists
mkdir -p "$(dirname "$LOGFILE")" 2>/dev/null

# Use jq to create properly formatted JSON
# The --arg flag in jq automatically handles proper JSON string quoting
event=$(jq -n --compact-output \
  --arg i "$1" \
  --arg actor "$2" \
  --arg type "$3" \
  --arg content "$4" \
  --arg timestamp "$timestamp" \
  '{interaction: ($i|tonumber), actor: $actor, type: $type, content: $content, timestamp: $timestamp}')

# Check if JSON creation was successful
if [ $? -ne 0 ]; then
  log_error "Failed to create JSON event data" "$2"
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
  log_error "Failed to acquire lock on events.log after $MAX_RETRIES attempts" "$2"
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
