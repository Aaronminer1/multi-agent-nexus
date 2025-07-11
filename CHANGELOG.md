# Changelog

All notable changes to this project will be documented in this file.

## [1.0.0] - 2025-07-08

### Added
- Initial implementation of event-log and snapshot system
- Created `log_event.sh` for appending events to events.log with proper JSON formatting
- Created `generate_snapshot.sh` for generating communication.md and archive.md from events.log
- Created `watch_events.sh` to automatically generate snapshots when events.log changes
- Implemented error handling and resilience features:
  - Retry logic for lock contention
  - Offline event logging for when the main log is unavailable
  - Automatic backup and restore for snapshot files
  - Error event logging for monitoring
- Added comprehensive README.md with usage instructions
- Created architecture.svg showing system components and data flow
