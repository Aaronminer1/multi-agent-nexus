# Event-Log + Snapshot System

## Overview
This project implements an append-only logging and snapshot infrastructure for multi-agent communication. It provides a robust system for recording events, generating snapshots of recent interactions, and archiving older ones.

## Features
- Append-only event logging with automatic timestamps
- File-locking for concurrent write safety
- Automatic snapshot generation of recent interactions
- Archiving of older interactions
- Error handling and resilience measures

## Directory Structure
```
├── scripts/
│   ├── log_event.sh       # Helper for logging events
│   └── generate_snapshot.sh  # Generates communication.md and archive.md
├── events.log             # Append-only event log
├── communication.md       # Recent interactions (last K)
├── archive.md             # Archived older interactions
└── README.md              # This file
```

## Usage

### Logging Events
To log an event:

```bash
./scripts/log_event.sh <interaction_id> <actor> <type> <content>
```

Example:
```bash
./scripts/log_event.sh 1 "Agent A" "question" "How do I start the MCP server?"
```

### Generating Snapshots
To generate snapshots of recent interactions and archive older ones:

```bash
./scripts/generate_snapshot.sh
```

This will update `communication.md` with the most recent K interactions and move older ones to `archive.md`.

### Automated Snapshot Generation
To automatically generate snapshots whenever events.log changes:

```bash
while inotifywait -e close_write events.log; do
  ./scripts/generate_snapshot.sh
done
```

## Error Handling
The system includes various error handling mechanisms:
- File locking to prevent corruption during concurrent writes
- Backup creation before file modifications
- Automatic restoration from backups if errors occur
- JSON validation and error reporting

## Integration Guide
To integrate this system with your agent:

1. Call `log_event.sh` whenever your agent sends or receives a message
2. Run `generate_snapshot.sh` after logging events to update the communication files
3. Your agent should read from `communication.md` to get the most recent interactions

## License
Open Source - Feel free to use and modify as needed.
