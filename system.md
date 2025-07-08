# Agent Task: Implement Event-Log + Snapshot System

**Goal:** Build the append-only logging and snapshot infrastructure described in `instructions.md (v2.0)`. Once complete, we’ll onboard the second agent and verify multi-agent communication.

---

## 0. Initialize GitHub Repository (if none exists)

If this is a new project with no existing repository, perform these steps first:

1. **Create Local Git Repo:**

   ```bash
   git init
   ```
2. **Create Remote on GitHub:**

   * Log in with GitHub CLI:

     ```bash
     gh auth login
     ```
   * Create a new repo named `<repo-name>`:

     ```bash
     gh repo create <owner>/<repo-name> --public --confirm
     ```
3. **Initial Commit:**

   ```bash
   git add README.md
   git commit -m "chore: initial commit"
   git branch -M main
   git push -u origin main
   ```
4. **Prepare Baseline Files:**

   ```bash
   touch events.log communication.md archive.md
   mkdir scripts
   gh repo clone <owner>/<repo-name> .
   ```

---

## 1. Setup & Prerequisites

1. **Environment:** Ensure you have Linux shell access and required CLI tools:

   * `jq` (for JSON processing)
   * `flock` (for file locking)
   * `mktemp`, `awk`, `sed` (standard POSIX utilities)
2. **Directory Layout:** In the project root, create:

   ```bash
   scripts/
     └── generate_snapshot.sh
   events.log      # existing or create if missing
   communication.md # placeholder with markers
   archive.md       # placeholder
   ```
3. **Permissions:** Make `generate_snapshot.sh` executable (`chmod +x`).

---

## 2. Event-Logging Helper (Optional Library)

Write a shell function or small script (`scripts/log_event.sh`) for your agent to call when sending events:

```bash
#!/usr/bin/env bash
# Usage: log_event.sh <interaction> <actor> <type> <content>
LOGFILE="$(pwd)/events.log"
timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
event=$(jq -n \
  --arg i "$1" \
  --arg actor "$2" \
  --arg type "$3" \
  --arg content "$4" \
  '{interaction: ($i|tonumber), actor: $actor, type: $type, content: $content, timestamp: $timestamp}')
# Append under lock
flock --exclusive "$LOGFILE" bash -c "echo \"$event\" >> '$LOGFILE'"
```

* Agents should call:

  ```bash
  ./scripts/log_event.sh 1 "Agent A" "question" "How do I start the MCP server?"
  ```

---

## 3. Snapshot Generator (`generate_snapshot.sh`)

This script reads `events.log`, groups by `interaction`, and outputs:

* **`communication.md`**: last **K** interactions
* **`archive.md`**: all older interactions

```bash
#!/usr/bin/env bash
events_file="$(pwd)/events.log"
comm_file="$(pwd)/communication.md"
archive_file="$(pwd)/archive.md"
K=3  # number of recent interactions to keep

# 1. Read all events into JSON array
events=$(jq -s '.' "$events_file")

# 2. Extract unique interaction numbers sorted
interactions=( $(echo "$events" | jq -r '.[].interaction' | sort -n | uniq) )

echo "# Communication Snapshot" > "$comm_file"
echo "<!-- BEGIN COMMUNICATION -->" >> "$comm_file"

# 3. Determine archive vs recent
archived=(${interactions[@]:0:${#interactions[@]}-K})
recent=(${interactions[@]: -K})

# 4. Render archived to archive.md
for i in "${archived[@]}"; do
  echo "## Interaction #$i" >> "$archive_file"
  echo "$events" | jq -r ".[] | select(.interaction==$i) | "'- [\(.actor) \(.type) \(.timestamp)]
\(.content)"" >> "$archive_file"
  echo "" >> "$archive_file"
done

# 5. Render recent to communication.md
for i in "${recent[@]}"; do
  echo "### Interaction #$i" >> "$comm_file"
  echo "$events" | jq -r ".[] | select(.interaction==$i) | if .type=="question" then "#### A → B" else if .type=="answer" then "#### B → A" else if .type=="followup" then "#### A Follow-Up" else "#### heartbeat" end end end" >> "$comm_file"
  echo "$events" | jq -r ".[] | select(.interaction==$i) | ' - ' + .content" >> "$comm_file"
  echo "" >> "$comm_file"
done

echo "<!-- END COMMUNICATION -->" >> "$comm_file"
```

Adjust the mapping of `type` to headings as needed.

---

## 4. Agent Integration & Testing

1. **Initial Test:** Manually append 4–5 events via `log_event.sh`, then run `scripts/generate_snapshot.sh`. Inspect `communication.md` and `archive.md`.
2. **Agent Hook:** Update your agent’s script to call `log_event.sh` on each turn, then trigger `generate_snapshot.sh` (e.g., after each log).
3. **Automate with Watcher:** Optionally, install `entr` or use `inotifywait`:

   ```bash
   while inotifywait -e close_write events.log; do
     ./scripts/generate_snapshot.sh
   done
   ```
4. **Bring in Agent B:** Once Agent A’s logging & snapshotting works, onboard Agent B. Validate both can append events concurrently (no corruption) and snapshots always reflect the latest K interactions.

---

## 6. Error Handling & Resilience

To ensure reliability when the orchestrator or any agent faces connection or operational issues, implement the following safeguards:

### 6.1 Orchestrator Connectivity Failures

* **Detection:** Agents monitor the orchestrator via regular `heartbeat` events (each with a timestamp). If no heartbeat is appended for >T seconds, agents assume orchestrator down.
* **Automatic Fallback:** Trigger the leader election process immediately upon missing heartbeats. Eligible agents elect a new coordinator to resume task dispatch.
* **Retry Logic:** The orchestrator, when disconnected from GitHub or the log file, retries operations with exponential backoff (e.g. 1s, 2s, 4s) before declaring itself offline.

### 6.2 File Lock & I/O Errors

* **Lock Contention:** If `flock` fails or times out (e.g. due to stale lock), retry a limited number of times (3 attempts) with short delays, then alert via a `error` event:

  ```json
  {"interaction":n,"actor":"AgentX","type":"error","content":"Failed to acquire lock on events.log","timestamp":"..."}
  ```
* **Disk Full / Permission Issues:** On any write error to `events.log`, `communication.md`, or `archive.md`, capture the exception, log an `error` event, and pause further operations until manual intervention.

### 6.3 GitHub & Network Errors

* **Push/Pull Failures:** Wrap all `git push`/`git pull` commands in retry blocks. On persistent failure (>5 retries), log an `error` event and switch to offline mode: queue events locally in a secondary log (`events.offline.log`) until connectivity restores.
* **Authentication Errors:** Validate GitHub credentials at startup. If invalid, halt agent with a clear error message and await credential refresh.

### 6.4 Snapshot Generator Robustness

* **Parsing Failures:** If `jq` or JSON parsing fails on malformed `events.log`, isolate the bad line to `events.error.log`, skip it, and continue processing. Emit an `error` event listing the line number.
* **Script Crashes:** Wrap the entire snapshot generation in a try-catch (shell `set -e` and trap). On any fatal error, restore the last known-good snapshot from a backup copy (`communication.md.bak`).

### 6.5 Agent Process Crashes & Restarts

* **Unfinished Claims:** Since we use append-only logging, no interaction blocks are locked—agents cannot leave a “claimed” block. On restart, agents resume by reading the last processed interaction number from their local state or a lightweight checkpoint file.
* **Checkpointing:** Each agent writes its last processed interaction ID to `agent-<id>.checkpoint` after successfully handling it. On startup, the agent reads this file to pick up where it left off.

### 6.6 Monitoring & Alerts

* **Central Health Dashboard:** Optionally, build a lightweight dashboard that reads recent `heartbeat`, `leader_election`, and `error` events to display system health.
* **Alerting:** Configure a simple email or chat alert (via a webhook) when an `error` event is logged, so humans can intervene promptly.

Implementing these layers of fault detection, automatic recovery, and safe fallback will keep the coordination robust—even with network hiccups, process failures, or high agent churn.
