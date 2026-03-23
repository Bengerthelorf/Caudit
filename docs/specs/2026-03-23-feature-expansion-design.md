# Claudit Feature Expansion Design

**Date:** 2026-03-23
**Architecture:** Approach B — independent Service files, AppState holds references

---

## Phase 1: CI Test Pipeline

**New file:** `.github/workflows/test.yml`
- Trigger: push to main, PR to main
- Steps: checkout → resolve SPM → `xcodebuild test` (ClauditTests scheme)
- Test files organized per-service: `ClauditTests/<Service>Tests.swift`
- Separate from build.yml (release workflow unchanged)

---

## Phase 2: Low-Risk High-Value Enhancements

### 2a. Sleep/Wake + Network Recovery Refresh

**New file:** `Claudit/Services/SystemEventService.swift`
- Listen `NSWorkspace.didWakeNotification` + `NWPathMonitor`
- Debounce 10s to prevent rapid re-triggers
- Calls AppState.refresh() on recovery
- **Test:** `SystemEventServiceTests.swift` — debounce logic

### 2b. Claude System Status

**New files:**
- `Claudit/Models/ClaudeStatus.swift` — `ClaudeStatus` with `Indicator` enum (none/minor/major/critical)
- `Claudit/Services/ClaudeStatusService.swift` — fetches `status.anthropic.com/api/v2/status.json`, 5-min interval

**UI:** Status dot + text in PopoverView footer. Tap opens status page.
**AppState:** `claudeStatus: ClaudeStatus?`
**Test:** `ClaudeStatusServiceTests.swift` — JSON parsing for all indicator values

### 2c. Data Export (JSON/CSV)

**New file:** `Claudit/Services/ExportService.swift`
- Export filtered UsageRecord array as JSON or CSV
- CSV columns: Timestamp, Project, Model, Source, Input/Output/CacheRead/CacheWrite Tokens, Cost
- NSSavePanel for file selection

**UI:** Export button in Dashboard toolbar
**Test:** `ExportServiceTests.swift` — format output correctness

---

## Phase 3: Interaction Enhancements

### 3a. Richer Notification System

**Extend:** `Claudit/Services/NotificationService.swift`
- Multiple thresholds: 75%, 90%, 95% + custom (individually toggleable)
- Session reset notification (usage drops from >0% to 0%)
- Session key expiry warning (24h before)
- Sound customization: none / default / system sounds
- Deduplication via persisted sent-notifications set
- Clear state on session reset

**Settings:** Expand notification settings tab with per-threshold toggles, sound picker
**AppState:** `notificationThresholds: Set<Int>`, `notifyOnSessionReset: Bool`, `notificationSound: String`
**Test:** `NotificationServiceTests.swift` — threshold logic, dedup, reset detection

### 3b. Global Keyboard Shortcuts

**New file:** `Claudit/Services/ShortcutService.swift`
- Carbon `RegisterEventHotKey` (no Accessibility permission needed)
- Actions: toggle popover, refresh, open settings, open dashboard
- Record shortcuts as `(keyCode, modifierFlags)`, persist to UserDefaults

**Settings:** New "Shortcuts" tab with recorder UI
**Test:** `ShortcutServiceTests.swift` — modifier conversion, storage round-trip

### 3c. Detachable Popover

**Modify:** `Claudit/AppDelegate.swift`, `Claudit/Views/PopoverView.swift`
- Add "detach" button (pin icon) in popover
- On detach: close popover, open NSPanel (floating, non-activating)
- Panel stays on top, can be repositioned
- Re-attach: close panel, revert to popover mode

**AppState:** `isPopoverDetached: Bool`
**Test:** Minimal — UI behavior, tested manually

---

## Phase 4: Major Features

### 4a. Pace System

**New files:**
- `Claudit/Models/PaceStatus.swift` — 6-tier enum: comfortable/onTrack/warming/pressing/critical/runaway
- `Claudit/Services/PaceService.swift` — calculates pace from `usedPercentage / elapsedFraction`

**Logic:**
- `elapsedFraction = timeElapsed / windowDuration` (min 3% to avoid noise)
- `projectedUsage = usedPercentage / elapsedFraction`
- Tiers: <50% comfortable, 50-75% onTrack, 75-90% warming, 90-100% pressing, 100-120% critical, >120% runaway
- Colors: green, teal, yellow, orange, red, purple

**UI:** Pace indicator on quota progress bars (marker line at elapsed position), pace label in popover
**AppState:** `sessionPace: PaceStatus?`, `weeklyPace: PaceStatus?`
**Test:** `PaceServiceTests.swift` — all 6 tiers, edge cases (0%, 100%, early window)

### 4b. Usage History Snapshots + Charts

**New files:**
- `Claudit/Models/UsageSnapshot.swift` — snapshot types: session/weekly/billing
- `Claudit/Services/UsageHistoryService.swift` — periodic recording + persistence

**Recording:**
- Session snapshots every 10 min (max 1000, ~7 days)
- Weekly snapshots every 2 hours (max 500, ~6 weeks)
- Persist to JSON file in app support directory

**Charts (in DashboardView or new UsageHistoryView):**
- Swift Charts: session + weekly overlay
- Time scale: 5h / 24h / 7d / 30d
- Navigation: back/forward buttons, "Now" jump

**Test:** `UsageHistoryServiceTests.swift` — snapshot recording, max cap, persistence round-trip

### 4c. API Console Billing

**New files:**
- `Claudit/Models/ConsoleBilling.swift` — spend, credits, per-model costs, per-key costs
- `Claudit/Services/ConsoleBillingService.swift` — fetches from console.anthropic.com endpoints

**Endpoints:**
- `/api/organizations/{org}/current_spend`
- `/api/organizations/{org}/prepaid/credits`
- `/api/organizations/{org}/workspaces/default/usage_cost`

**Auth:** Console session cookie (separate from CLI OAuth)
**UI:** New "Billing" section in Dashboard Overview or separate tab
**AppState:** `consoleBilling: ConsoleBilling?`
**Test:** `ConsoleBillingServiceTests.swift` — JSON parsing for all response types

---

## Phase 5: High Complexity

### 5a. Terminal Statusline

**New files:**
- `Claudit/Services/StatuslineService.swift` — manages script installation to `~/.claude/`
- `Resources/fetch-claude-usage.swift` — Swift script template for API calls
- `Resources/statusline-command.sh` — Bash script for display formatting

**Features:**
- Configurable components: dir, git branch, model, usage %, progress bar, reset time
- Config file: `~/.claude/statusline-config.txt`
- Cache file: `~/.claude/.statusline-usage-cache` (written by app, read by script)
- Install/uninstall from Settings

**Settings:** New "Statusline" section with component toggles
**Test:** `StatuslineServiceTests.swift` — config generation, cache format

### 5b. Multi-Profile System

**New files:**
- `Claudit/Models/Profile.swift` — isolated profile with own credentials, settings, usage
- `Claudit/Services/ProfileManager.swift` — profile CRUD, switching, credential rotation

**Features:**
- Each profile: name, credentials (session key, org ID, CLI creds), usage data, notification settings
- Profile switching: re-sync credentials, update statusline, notify
- Auto-switch: when active profile hits limit, switch to next available
- Persist profiles to app support directory as JSON

**UI:** Profile selector in popover, profile management in Settings
**AppState:** `profiles: [Profile]`, `activeProfileId: UUID`
**Test:** `ProfileManagerTests.swift` — CRUD, switching logic, auto-switch conditions

### 5c. Auto-Start Session

**New file:** `Claudit/Services/AutoStartService.swift`
- Background check every 5 min + on wake
- When session at 0%: send "Hi" via claude-haiku-4-5-20251001 to initialize
- Create temp conversation → send → delete (incognito)
- Capture reset time from SSE response
- Per-profile toggle

**Test:** `AutoStartServiceTests.swift` — check interval logic, debounce

---

## Phase 6: Polish

### 6a. Multi-Language (i18n)

- Add `Localizable.strings` for: en, zh-Hans, ja, ko, fr, de, es, it, pt
- Extract all user-facing strings to localization keys
- Start with en + zh-Hans, others later

### 6b. Setup Wizard

**New file:** `Claudit/Views/SetupWizardView.swift`
- 3-step flow: welcome → configure credentials → verify connection
- Show on first launch (check UserDefaults flag)
- Skip button available

### 6c. Debug Network Log

**New files:**
- `Claudit/Models/NetworkLog.swift` — request/response capture
- `Claudit/Services/NetworkLogService.swift` — timed capture with circular buffer

**UI:** Debug section in Settings → shows recent API calls with detail viewer
**Test:** `NetworkLogServiceTests.swift` — buffer size, capture format

---

## Test Strategy

- All tests in `ClauditTests/` directory, one file per service
- Pure logic tests only (no UI tests in CI)
- Mock network responses with static JSON fixtures
- CI runs on every push/PR via `.github/workflows/test.yml`
- Each phase commit includes corresponding tests
