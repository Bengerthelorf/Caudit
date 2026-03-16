<div align="center">

<img src="Caudit/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" height="128" alt="Caudit">

# Caudit

**Track your Claude API usage from the macOS menu bar — cost, tokens, quota, and more.**

[![Download](https://img.shields.io/github/v/release/Bengerthelorf/Caudit?label=Download&style=for-the-badge&color=blue)](https://github.com/Bengerthelorf/Caudit/releases/latest)
&nbsp;
[![Documentation](https://img.shields.io/badge/Documentation-Visit_→-2ea44f?style=for-the-badge)](https://bengerthelorf.github.io/Caudit/)
&nbsp;
[![Homebrew](https://img.shields.io/badge/Homebrew-Available-orange?style=for-the-badge)](https://github.com/Bengerthelorf/Caudit#install)

</div>

---

## Highlights

- 💰 **Real-Time Cost** — Today's spend in the menu bar, updated automatically
- 📊 **Rich Dashboard** — Heatmaps, trend charts, model breakdowns, session browser, project analytics
- 🔔 **Quota Alerts** — System notification when your 5-hour window approaches the limit
- 🖥️ **Multi-Device** — Aggregate usage from remote machines over SSH
- 💬 **Session Reader** — Browse full conversations with search, highlighting, and tool call details
- 🔒 **Fully Local** — Parses `~/.claude` JSONL logs directly, no data leaves your machine
- ⚡ **Lightweight** — Native SwiftUI + AppKit with C-level I/O for large log files

## Install

### Homebrew

```bash
brew install Bengerthelorf/tap/caudit
```

### Manual

Download the latest DMG from [Releases](https://github.com/Bengerthelorf/Caudit/releases/latest), drag to Applications, and launch.

## System Requirements

- macOS 15.0 or later
- [Claude Code](https://docs.anthropic.com/en/docs/claude-code) installed

## Development

```bash
git clone https://github.com/Bengerthelorf/Caudit.git
cd Caudit
open Caudit.xcodeproj
```

Build and run with Xcode. Release with:

```bash
./scripts/release.sh 0.0.5
```

## License

MIT License. See [LICENSE](LICENSE) for details.
</div>
