#!/usr/bin/env bash
# 2025-07-08: Snapshot generator for events.log, creating communication.md and archive.md
# 2025-07-10: Improved deduplication, JSON handling, and added structured JSON output

# Paths
events_file="$(pwd)/events.log"
comm_file="$(pwd)/communication.md"
archive_file="$(pwd)/archive.md"
json_snapshot="$(pwd)/latest_snapshot.json"
K=5  # number of recent interactions to keep

# Create backups before processing
[ -f "$comm_file" ] && cp "$comm_file" "${comm_file}.bak"
[ -f "$archive_file" ] && cp "$archive_file" "${archive_file}.bak"
[ -f "$json_snapshot" ] && cp "$json_snapshot" "${json_snapshot}.bak"

# Setup error handling
cleanup() {
  local error_msg="$1"
  echo "ERROR: $error_msg" >&2
  echo "Restoring from backup..." >&2
  [ -f "${comm_file}.bak" ] && cp "${comm_file}.bak" "$comm_file"
  [ -f "${archive_file}.bak" ] && cp "${archive_file}.bak" "$archive_file"
  [ -f "${json_snapshot}.bak" ] && cp "${json_snapshot}.bak" "$json_snapshot"
  exit 1
}

# Handle jq errors specifically
jq_safe() {
  local result
  result=$("$@") || { 
    cleanup "jq command failed: $*"
    return 1
  }
  echo "$result"
}
trap 'cleanup "An unexpected error occurred"' ERR

# Initialize files
echo "# Communication Snapshot" > "$comm_file"
echo "<!-- BEGIN COMMUNICATION -->" >> "$comm_file"
echo "<!-- Generated: $(date) -->" >> "$comm_file"
echo "\n## Recent Events\n" >> "$comm_file"
echo "# Archived Communications" > "$archive_file"
echo "<!-- Generated: $(date) -->" >> "$archive_file"

# Initialize JSON snapshot with metadata
echo '{"metadata":{"generated_at":"'"$(date -Iseconds)"'","event_count":0},"recent_interactions":[],"all_events":[]}' > "$json_snapshot"

# Handle empty events file case
if [ ! -s "$events_file" ]; then
  echo "No interactions recorded yet." >> "$comm_file"
  echo "<!-- END COMMUNICATION -->" >> "$comm_file"
  echo "No archived interactions yet." >> "$archive_file"
  echo "Snapshot generated successfully (empty events)."
  exit 0
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
  echo "ERROR: jq is not installed but required for processing JSON" >&2
  echo "Please install jq using your package manager (e.g., 'apt install jq')" >&2
  exit 1
fi

# First, load all events and canonicalize the JSON (reduces deduplication issues)
echo "Loading and processing events..." >&2
all_events=$(jq -s '.' "$events_file" || cleanup "Failed to parse events.log JSON data")

# Update the JSON snapshot with all events
jq --argjson events "$all_events" '.all_events = $events | .metadata.event_count = ($events | length)' "$json_snapshot" > "${json_snapshot}.tmp" && mv "${json_snapshot}.tmp" "$json_snapshot"

# Get a sorted list of unique interaction IDs - ignore timestamp for deduplication
interaction_ids=$(echo "$all_events" | jq -r '.[].interaction' | sort -n | uniq)

# Convert to array
mapfile -t interactions <<< "$interaction_ids"

# Determine which interactions go in archive vs communication
if [ ${#interactions[@]} -le $K ]; then
  # All interactions go to communication
  recent=("${interactions[@]}")
  archived=()
else
  # Split between archive and communication
  cutoff=$((${#interactions[@]} - $K))
  archived=("${interactions[@]:0:$cutoff}")
  recent=("${interactions[@]:$cutoff}")
fi

# Process archived interactions
if [ ${#archived[@]} -eq 0 ]; then
  echo "No archived interactions yet." >> "$archive_file"
else
  for i in "${archived[@]}"; do
    i=$(echo "$i" | tr -d '\n')  # Remove any newlines
    echo "## Interaction #$i" >> "$archive_file"
    
    # Get all events for this interaction
    jq -r "select(.interaction == $i) | \"- [\(.actor) \(.type) \(.timestamp)]\n\(.content)\"" "$events_file" >> "$archive_file"
    echo "" >> "$archive_file"
  done
fi

# Process recent interactions
if [ ${#recent[@]} -eq 0 ]; then
  echo "No recent interactions." >> "$comm_file"
else
  # Create JSON array for recent interactions
  recent_json="[]"
  
  for i in "${recent[@]}"; do
    i=$(echo "$i" | tr -d '\n')  # Remove any newlines
    echo "### Interaction #$i" >> "$comm_file"
    
    # Add this interaction's events to recent_json
    interaction_events=$(echo "$all_events" | jq --arg i "$i" '[.[] | select(.interaction == ($i|tonumber))]')
    recent_json=$(echo "$recent_json" | jq --argjson events "$interaction_events" '. + $events')
    
    # Process events for this interaction
    while IFS= read -r event_type; do
      event_type=$(echo "$event_type" | tr -d '\n')  # Remove any newlines
      
      # Set heading based on event type
      case "$event_type" in
        message)
          echo "#### Message" >> "$comm_file"
          ;;
        agent_registration)
          echo "#### Agent Registration" >> "$comm_file"
          ;;
        proposal)
          echo "#### Proposal" >> "$comm_file"
          ;;
        comment)
          echo "#### Comment" >> "$comm_file"
          ;;
        contribution)
          echo "#### Contribution" >> "$comm_file"
          ;;
        synthesis)
          echo "#### Synthesis" >> "$comm_file"
          ;;
        question)
          echo "#### Question" >> "$comm_file"
          ;;
        answer)
          echo "#### Answer" >> "$comm_file"
          ;;
        followup)
          echo "#### Follow-Up" >> "$comm_file"
          ;;
        error)
          echo "#### Error" >> "$comm_file"
          ;;
        *)
          echo "#### $event_type" >> "$comm_file"
          ;;
      esac
      
      # Get content for this event and format it for human readability
      while IFS= read -r event_json; do
        if [ -n "$event_json" ]; then
          # Extract and format the content based on event type
          case "$event_type" in
            message)
              from=$(echo "$event_json" | jq -r '.from // "unknown"')
              to=$(echo "$event_json" | jq -r '.to // "unknown"')
              message=$(echo "$event_json" | jq -r '.message // "No message content"')
              
              if [ "$to" = "all" ]; then
                echo "**$from** (to everyone): $message" >> "$comm_file"
              else
                echo "**$from** (to $to): $message" >> "$comm_file"
              fi
              ;;
            
            agent_registration)
              agent_id=$(echo "$event_json" | jq -r '.agent_id // "unknown"')
              agent_type=$(echo "$event_json" | jq -r '.agent_type // "unknown"')
              capabilities=$(echo "$event_json" | jq -r '.capabilities | join(", ") // "none"')
              
              echo "Agent **$agent_id** registered (Type: $agent_type, Capabilities: $capabilities)" >> "$comm_file"
              ;;
            
            proposal)
              from=$(echo "$event_json" | jq -r '.from // "unknown"')
              component=$(echo "$event_json" | jq -r '.component // "unknown component"')
              description=$(echo "$event_json" | jq -r '.description // "No description"')
              
              echo "**$from** proposed component '$component':\n> $description" >> "$comm_file"
              ;;
            
            comment)
              from=$(echo "$event_json" | jq -r '.from // "unknown"')
              on_agent=$(echo "$event_json" | jq -r '.on // "unknown"')
              component=$(echo "$event_json" | jq -r '.component // "unknown component"')
              comment=$(echo "$event_json" | jq -r '.comment // "No comment"')
              
              echo "**$from** commented on $on_agent's '$component':\n> $comment" >> "$comm_file"
              ;;
              
            contribution)
              from=$(echo "$event_json" | jq -r '.from // "unknown"')
              component=$(echo "$event_json" | jq -r '.component // "unknown component"')
              content=$(echo "$event_json" | jq -r '.content // "No content"')
              
              echo "**$from** contributed to '$component':\n\`\`\`\n$content\n\`\`\`" >> "$comm_file"
              ;;
              
            error)
              source=$(echo "$event_json" | jq -r '.source // "unknown"')
              content=$(echo "$event_json" | jq -r '.content // "Unknown error"')
              
              echo "**ERROR** from $source: $content" >> "$comm_file"
              ;;
              
            *)
              # For any other event types, print raw JSON but formatted nicely
              echo "\`\`\`json\n$event_json\n\`\`\`" >> "$comm_file"
              ;;
          esac
        fi
      done < <(echo "$all_events" | jq -c --arg i "$i" --arg type "$event_type" '.[] | select(.interaction == ($i|tonumber) and .type == $type) | .content')
      
      echo "" >> "$comm_file"
    done < <(echo "$all_events" | jq -r --arg i "$i" '.[] | select(.interaction == ($i|tonumber)) | .type' | sort | uniq)
    
    echo "" >> "$comm_file"
  done
  
  # Update JSON snapshot with recent interactions
  jq --argjson recent "$recent_json" '.recent_interactions = $recent' "$json_snapshot" > "${json_snapshot}.tmp" && mv "${json_snapshot}.tmp" "$json_snapshot"
fi

echo "<!-- END COMMUNICATION -->" >> "$comm_file"

# Clean up backups if successful
rm -f "${comm_file}.bak" "${archive_file}.bak" "${json_snapshot}.bak"

echo "Snapshot generated successfully." >&2
echo "- Communication snapshot: $comm_file" >&2
echo "- Archived interactions: $archive_file" >&2
echo "- JSON snapshot: $json_snapshot" >&2
exit 0
