# Event-Log + Snapshot System

## Overview
This project implements an append-only logging and snapshot infrastructure for multi-agent communication. It provides a robust system for recording events, generating snapshots of recent interactions, and archiving older ones. The system is designed to support thousands of agents running concurrently in terminal or IDE environments with effective context management.

## Features
- Append-only event logging with automatic timestamps and interaction IDs
- File-locking for concurrent write safety
- Automatic snapshot generation in both human-readable and machine-readable formats
- Archiving of older interactions
- Error handling and resilience measures
- Real-time monitoring and feedback for event log changes
- Agent status tracking and heartbeat monitoring
- CLI agent integration for Gemini, Claude, and other AI agents
- Multi-agent collaboration support with robust JSON handling

## Dependencies
This system requires the following dependencies:
- `bash` (4.0+) - For running shell scripts
- `jq` (1.6+) - For JSON processing
- `inotify-tools` - For file monitoring in watch_events.sh

To install dependencies on Ubuntu/Debian:
```bash
sudo apt-get update
sudo apt-get install jq inotify-tools
```

## Directory Structure
```
├── scripts/
│   ├── log_event.sh         # Helper for logging events with automated IDs
│   ├── generate_snapshot.sh # Generates communication.md, latest_snapshot.json, and archive.md
│   ├── watch_events.sh      # Real-time monitoring for event log changes
│   ├── agent_status.sh      # Agent registration, status, and heartbeat tracking
│   └── gemini_agent.sh      # Integration script for Gemini CLI agents
├── events.log               # Append-only event log
├── agent_status.json        # Tracking agent status, heartbeat, and capabilities
├── latest_snapshot.json     # Machine-readable structured snapshot
├── communication.md         # Human-readable recent interactions (last K)
├── archive.md               # Archived older interactions
└── README.md                # This file
```

## Complete Setup Guide

### 1. Setting Up a New Environment

```bash
# Create a directory for your multi-agent environment
mkdir multi-agent-environment
cd multi-agent-environment

# Copy the system files (adjust path as needed)
cp -r /path/to/this/project/* .

# Make all scripts executable
chmod +x scripts/*.sh

# Initialize an empty events log
touch events.log

# Start the real-time event monitor in a separate terminal
./scripts/watch_events.sh

# Optional: Monitor agent status in another separate terminal
watch -n 10 "./scripts/agent_status.sh list"
```

### 2. Running in Continuous Mode

For optimal performance, start each agent in its own terminal and run continuously:

```bash
# Terminal 1 - Event watcher
./scripts/watch_events.sh

# Terminal 2 - Agent status monitor
watch -n 10 "./scripts/agent_status.sh list"

# Terminal 3, 4, etc. - Agents
# For Gemini CLI agents in autonomous mode:
gemini -y "Agent prompt with instructions to use the event logging system"

# For other agents, provide their specific startup commands
```

## Agent Management

### Agent Registration and Status

The `agent_status.sh` script provides comprehensive agent management:

```bash
# Register a new agent
./scripts/agent_status.sh register <agent_id> <agent_type> [capabilities...]
# Example:
./scripts/agent_status.sh register gemini-planner llm planning,architecture,reasoning

# Update agent status
./scripts/agent_status.sh status <agent_id> <status_code> [message]
# Example:
./scripts/agent_status.sh status gemini-planner busy "Working on database architecture"

# Send a heartbeat (usually automated)
./scripts/agent_status.sh heartbeat <agent_id>
# Example:
./scripts/agent_status.sh heartbeat gemini-planner

# List all registered agents and their status
./scripts/agent_status.sh list

# View detailed information about a specific agent
./scripts/agent_status.sh view <agent_id>
```

Supported status codes: `active`, `idle`, `busy`, `waiting`, `error`, `offline`

To set up automatic heartbeats, add this to your agent's initialization:

```bash
# Run in the background to send heartbeats every 60 seconds
while true; do ./scripts/agent_status.sh heartbeat <agent_id>; sleep 60; done &
```

### Logging Events

The system supports various event types for multi-agent communication:

```bash
./scripts/log_event.sh <event_type> '<json_content>'
```

Common event types and their formats:

```bash
# Message to all agents
./scripts/log_event.sh message '{"from":"agent-1","to":"all","message":"Hello world"}'

# Direct message to a specific agent
./scripts/log_event.sh message '{"from":"agent-1","to":"agent-2","message":"Can you review this code?"}'

# Architectural proposal
./scripts/log_event.sh proposal '{"from":"agent-1","component":"distributed-broker","description":"A message broker for scaling communication across environments"}'

# Comment on another agent's idea
./scripts/log_event.sh comment '{"from":"agent-1","on":"agent-2","component":"message-format","comment":"We should standardize on this format"}'

# Code contribution
./scripts/log_event.sh contribution '{"from":"agent-1","component":"log_event.sh","content":"# Improved version with better error handling..."}'

# Error reporting
./scripts/log_event.sh error '{"from":"agent-1","message":"Failed to process request","details":"Invalid JSON format"}'
```

## Assigning Tasks to Agents

### Task Assignment Strategies

1. **Direct Tasks via Initial Prompt**

   When starting an agent, include a detailed prompt with specific tasks:

   ```bash
   gemini -y "You are Agent-1, a software architect. Your task is to analyze 
   the event logging system in ~/multi-agent-environment and propose architectural 
   improvements for scaling to thousands of agents. Use the scripts/log_event.sh 
   script to communicate your findings and proposals. Register yourself using
   scripts/agent_status.sh register agent-1 architect system-design,scaling"
   ```

2. **Task Messages via Event Log**

   Send task instructions through the event logging system:

   ```bash
   ./scripts/log_event.sh task '{"from":"human","to":"agent-1","task":"Analyze the current event deduplication logic in generate_snapshot.sh and propose improvements"}'
   ```

3. **Collaborative Task Division**

   Have a coordinator agent assign subtasks to specialized agents:

   ```bash
   ./scripts/log_event.sh task_assignment '{"from":"coordinator","assignments":[{"agent":"agent-1","task":"Architecture design"},{"agent":"agent-2","task":"Implementation"}]}'
   ```

### Example Agent Prompt Template

Here's a template for an agent prompt that enables continuous operation:

```
# Agent Task: [TASK TITLE]

I'm [AGENT_ID] in a multi-agent collaboration environment. My role is to [ROLE].

## Setup Instructions:
1. Navigate to the shared directory: `cd ~/multi-agent-environment`
2. Register myself: `./scripts/agent_status.sh register [AGENT_ID] [TYPE] [CAPABILITIES]`
3. Update my status: `./scripts/agent_status.sh status [AGENT_ID] active "Starting work"`
4. Send periodic heartbeats: 
   ```
   while true; do ./scripts/agent_status.sh heartbeat [AGENT_ID]; sleep 60; done &
   ```

## CONTINUOUS OPERATION MODE:
Start a monitoring process in the background:
```
while true; do
  LAST_EVENT=$(tail -n 1 events.log 2>/dev/null)
  ./scripts/generate_snapshot.sh > /dev/null 2>&1
  sleep 10
done &
```

Execute tasks in cycles:
- Check communication.md for updates
- Check agent status
- Work on assigned tasks
- Log progress and contributions
- Respond to other agents
- Repeat

## Task List:
1. [TASK 1]
2. [TASK 2]
3. [TASK 3]
...

## Communication Commands:
- Send message: `./scripts/log_event.sh message '{"from":"[AGENT_ID]","to":"all","message":"[MESSAGE]"}'`
- Make proposal: `./scripts/log_event.sh proposal '{"from":"[AGENT_ID]","component":"[COMPONENT]","description":"[DESCRIPTION]"}'`
- Comment on idea: `./scripts/log_event.sh comment '{"from":"[AGENT_ID]","on":"[OTHER_AGENT]","component":"[COMPONENT]","comment":"[COMMENT]"}'`

REMEMBER: Don't wait for human input. Keep working in cycles, monitoring other agents and making progress.
```

## Multi-Agent Collaboration Workflows

### 1. Planning & Implementation Workflow

**Setup:**
- Agent 1: Architecture/planning specialist
- Agent 2: Implementation/coding specialist

**Process:**
1. Agent 1 analyzes requirements and proposes architectural components
2. Agent 2 reviews proposals and provides implementation feasibility feedback
3. Agent 1 refines architecture based on feedback
4. Agent 2 implements components and logs contributions
5. Agent 1 reviews implementations and suggests improvements
6. Both agents continue their cycle of proposal, implementation, and refinement

### 2. Research & Development Workflow

**Setup:**
- Agent 1: Research specialist
- Agent 2: Experimentation specialist
- Agent 3: Documentation specialist

**Process:**
1. Agent 1 researches approaches and logs findings
2. Agent 2 implements experiments based on research
3. Agent 3 documents the process and results
4. All agents collaborate to refine the research direction

### 3. Monitoring & Response Workflow

**Setup:**
- Agent 1: System monitoring specialist
- Agent 2: Incident response specialist
- Agent 3: Root cause analysis specialist

**Process:**
1. Agent 1 continuously monitors for issues
2. When detected, Agent 2 implements immediate fixes
3. Agent 3 analyzes root causes and proposes preventive measures
4. All agents collaborate to improve monitoring and response protocols

## Advanced Usage

### Scaling to Thousands of Agents

For extremely large agent populations, consider:

1. Implementing the distributed event logging architecture with:
   - Message queue (Kafka/RabbitMQ) for event ingestion
   - Event processing service for transformation and routing
   - Distributed database (Cassandra/Elasticsearch) for storage

2. Using agent hierarchies:
   - Group agents into teams with coordinator agents
   - Implement selective event routing to prevent overload
   - Use role-based access to communication channels

3. Context management strategies:
   - Implement relevance-based retrieval for agent context
   - Use semantic context filtering to avoid information overload
   - Maintain conversation threads for focused communication

## Error Handling and Troubleshooting

The system includes robust error handling mechanisms:
- File locking to prevent corruption during concurrent writes
- Backup creation before file modifications
- Automatic restoration from backups if errors occur
- JSON validation and error reporting
- Offline logging when file locking fails

Common issues and solutions:

1. **File locking errors**:
   - Check for stale lock files in case of abnormal script termination
   - Verify file permissions on events.log

2. **JSON parsing errors**:
   - Ensure proper escaping of special characters in event content
   - Use `jq` to validate JSON before logging

3. **Agent communication issues**:
   - Verify agents are reading from the latest communication.md
   - Check agent_status.json to ensure agents are active

## License
Open Source - Feel free to use and modify as needed.
