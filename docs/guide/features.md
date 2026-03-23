# Features

## Menu Bar

The menu bar item shows your current daily spend or quota percentage. Click it to open the popover with:

- **Usage tab** — Today's cost, token breakdown, burn rate estimate
- **Quota tab** — 5-hour and 7-day utilization with reset timers

## Dashboard

Open the dashboard from the popover for detailed analytics:

- **Overview** — Summary cards, quota gauges, 7-day trend, all-time heatmap
- **Activity** — Hourly/weekly/monthly heatmaps with hover details, cost trend chart, session duration stats
- **Sessions** — Browse all sessions with cost, tokens, duration; click to read full conversation
- **Projects** — Per-project cost breakdown with session counts
- **Models** — Token usage by model (input, output, cache read, cache creation)
- **Tools** — Tool call frequency across all sessions

## Session Reader

Click any session to view the full conversation with:

- Role-colored message bubbles (user, assistant, tool results)
- Collapsible thinking blocks and tool calls
- Cmd+F search with match highlighting and navigation
- Open in a separate window for side-by-side reading

## Remote Devices

Aggregate usage from other machines over SSH. Configure in Settings > Devices:

1. Add a device with SSH host and optional key path
2. Test connection to verify access
3. Usage data is fetched with fingerprint caching — only re-parsed when files change

## Notifications

Set a quota threshold (e.g., 80%) to receive a system notification when your 5-hour usage window exceeds the limit.

## Auto-Update

Claudit uses Sparkle for seamless background updates. Check for updates manually from the app menu.
