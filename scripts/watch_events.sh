#!/usr/bin/env bash
# 2025-07-08: Watcher script to automatically generate snapshots when events.log changes

EVENTS_LOG="$(pwd)/events.log"
SCRIPT_DIR="$(dirname "$0")"
GENERATE_SNAPSHOT="${SCRIPT_DIR}/generate_snapshot.sh"

echo "Starting event log watcher..."
echo "Monitoring $EVENTS_LOG for changes"
echo "Will execute $GENERATE_SNAPSHOT on change"
echo "Press Ctrl+C to stop"

# Check if inotifywait is available
if ! command -v inotifywait &> /dev/null; then
    echo "Error: inotifywait not found. Please install inotify-tools:"
    echo "  sudo apt-get install inotify-tools"
    exit 1
fi

# Main watch loop
while true; do
    inotifywait -e close_write "$EVENTS_LOG" && {
        echo "$(date -u +"%Y-%m-%dT%H:%M:%SZ") - Event log changed, generating snapshot..."
        "$GENERATE_SNAPSHOT"
        echo "Snapshot generation complete, continuing to watch..."
    }
done
