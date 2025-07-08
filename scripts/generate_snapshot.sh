#!/usr/bin/env bash
# 2025-07-08: Snapshot generator for events.log, creating communication.md and archive.md

# Paths
events_file="$(pwd)/events.log"
comm_file="$(pwd)/communication.md"
archive_file="$(pwd)/archive.md"
K=3  # number of recent interactions to keep

# Create backups before processing
[ -f "$comm_file" ] && cp "$comm_file" "${comm_file}.bak"
[ -f "$archive_file" ] && cp "$archive_file" "${archive_file}.bak"

# Setup error handling
cleanup() {
  echo "Error occurred, restoring from backup"
  [ -f "${comm_file}.bak" ] && cp "${comm_file}.bak" "$comm_file"
  [ -f "${archive_file}.bak" ] && cp "${archive_file}.bak" "$archive_file"
  exit 1
}
trap cleanup ERR

# Initialize files
echo "# Communication Snapshot" > "$comm_file"
echo "<!-- BEGIN COMMUNICATION -->" >> "$comm_file"
echo "# Archived Communications" > "$archive_file"

# Handle empty events file case
if [ ! -s "$events_file" ]; then
  echo "No interactions recorded yet." >> "$comm_file"
  echo "<!-- END COMMUNICATION -->" >> "$comm_file"
  echo "No archived interactions yet." >> "$archive_file"
  echo "Snapshot generated successfully (empty events)."
  exit 0
fi

# Process the events file
# First, get a sorted list of unique interaction IDs
interaction_ids=$(jq -r '.interaction' "$events_file" | sort -n | uniq)

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
  for i in "${recent[@]}"; do
    i=$(echo "$i" | tr -d '\n')  # Remove any newlines
    echo "### Interaction #$i" >> "$comm_file"
    
    # Process events for this interaction
    while IFS= read -r event_type; do
      event_type=$(echo "$event_type" | tr -d '\n')  # Remove any newlines
      
      # Set heading based on event type
      case "$event_type" in
        question)
          heading="#### A → B"
          ;;
        answer)
          heading="#### B → A"
          ;;
        followup)
          heading="#### A Follow-Up"
          ;;
        *)
          heading="#### $event_type"
          ;;
      esac
      
      echo "$heading" >> "$comm_file"
      
      # Get content for this event
      jq -r --arg i "$i" --arg type "$event_type" 'select(.interaction == ($i|tonumber) and .type == $type) | " - " + .content' "$events_file" >> "$comm_file"
    done < <(jq -r "select(.interaction == $i) | .type" "$events_file" | sort | uniq)
    
    echo "" >> "$comm_file"
  done
fi

echo "<!-- END COMMUNICATION -->" >> "$comm_file"

# Clean up backups if successful
rm -f "${comm_file}.bak" "${archive_file}.bak"

echo "Snapshot generated successfully."
exit 0
