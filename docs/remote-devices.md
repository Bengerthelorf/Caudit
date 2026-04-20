---
title: Remote Devices
section: guide
order: 3
---

Claudit aggregates Claude Code and OpenClaw usage from remote machines via SSH.

## Setup

1. Open **Settings → Devices**
2. Click **Add Device**
3. Fill in:
   - **Name** — display name (e.g. `Mac Mini`)
   - **SSH Host** — `user@hostname` or an SSH config alias
   - **Claude Config Path** — remote path to `~/.claude` (default)
   - **OpenClaw Paths** — remote paths to `~/.openclaw` directories (optional)
   - **SSH Key Path** — path to identity file (optional; uses SSH agent by default)
4. Click **Test Connection** to verify
5. Click **Save**

## How It Works

- Claudit runs `find | grep` over SSH to extract usage records from remote JSONL files
- A fingerprint (file count + total size) is checked first — if unchanged, cached data is reused
- SSH authentication inherits your local SSH agent (`SSH_AUTH_SOCK`)
- No hard timeout — relies on SSH `ServerAliveInterval` for connection health

## Troubleshooting

- **Connection failed**: ensure `ssh user@host` works in your terminal first
- **No data found**: check that the remote Claude Config Path is correct
- **Slow fetch**: large log directories take time on first fetch; subsequent fetches use fingerprint caching
