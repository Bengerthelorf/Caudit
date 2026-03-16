# Remote Devices

Caudit can aggregate Claude Code and OpenClaw usage from remote machines via SSH.

## Setup

1. Open **Settings > Devices**
2. Click **Add Device**
3. Fill in:
   - **Name** — Display name (e.g., "Mac Mini")
   - **SSH Host** — `user@hostname` or an SSH config alias
   - **Claude Config Path** — Remote path to `~/.claude` (default)
   - **OpenClaw Paths** — Remote paths to `~/.openclaw` directories (optional)
   - **SSH Key Path** — Path to identity file (optional, uses SSH agent by default)
4. Click **Test Connection** to verify
5. Click **Save**

## How It Works

- Caudit runs `find | grep` over SSH to extract usage records from remote JSONL files
- A fingerprint (file count + total size) is checked first — if unchanged, cached data is reused
- SSH authentication inherits your local SSH agent (`SSH_AUTH_SOCK`)
- No hard timeout — relies on SSH `ServerAliveInterval` for connection health

## Troubleshooting

- **Connection failed**: Ensure `ssh user@host` works in your terminal first
- **No data found**: Check that the remote Claude Config Path is correct
- **Slow fetch**: Large log directories take time on first fetch; subsequent fetches use fingerprint caching
