# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.1.0] - 2026-02-11

### Added
- `SessionEnd(clear)` hook to persist handoff before `/clear` teardown
- `SessionStart(clear)` restore support (in addition to `compact`)
- Shared `hooks/handoff_core.py` for extraction + file writing logic
- `latest-handoff.md` and `latest-handoff.json` fallback pointer files
- `scripts/claude-handoff-supervisor.py` external controller to rewrite manual `/compact` -> `/clear`

### Changed
- `session-restore.sh` now falls back to `latest-handoff.md` for clear-start sessions
- `session-restore.sh` fallback is now guarded by `cwd` match + max-age window
- Installer/uninstaller now manage SessionEnd hook and supervisor binary
- Test suite updated for clear transition coverage
- Supervisor now forwards unknown CLI args directly to Claude (no required `--` delimiter)
- `plugin.json` bumped to `1.1.0`

## [1.0.0] - 2026-02-11

### Added
- Initial release
- PreCompact hook for context extraction before auto-compaction
- SessionStart hook for context restoration after compaction
- Session-id based file isolation for multi-agent safety
- Message deduplication (>85% similarity threshold)
- Junk filtering (API errors, interruptions, empty responses)
- File path extraction from tool calls
- Automatic installation script
- Automatic uninstallation script
- Comprehensive README with troubleshooting guide

### Features
- Preserves last 15 user messages (configurable)
- Preserves last 10 assistant responses (configurable)
- Preserves last 20 file references
- Zero manual intervention required
- Compatible with Claude Code teams
- Compatible with Ralph Loop
- Works with all existing hooks and plugins

### Technical Details
- Python 3 for PreCompact hook
- Bash for SessionStart hook
- JSON-based handoff format
- Markdown output for human readability
- 30-second timeout for PreCompact
- 10-second timeout for SessionStart
