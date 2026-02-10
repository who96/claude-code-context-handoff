# Frequently Asked Questions

## General

### What problem does this solve?

Claude Code auto-compacts context when it reaches ~95% capacity. After compaction, the session loses critical information like recent user requests, files you were working on, and conversation flow. This causes Claude to ask repeated questions and lose project context.

This plugin automatically extracts and restores that context, maintaining continuity across compactions.

### How is this different from `/compact`?

`/compact` is a manual command that triggers compaction. This plugin works with both auto-compact and manual `/compact`, automatically preserving context in both cases.

### Does this work with Claude Code teams?

Yes. Each team member (including subagents) gets their own handoff file keyed by session_id, so there are no conflicts.

### Does this work with Ralph Loop?

Yes. Ralph's `--resume` handles cross-script session continuity. This plugin handles within-session context preservation. They complement each other.

## Installation

### Do I need to restart Claude Code after installation?

Yes. Hooks are loaded at session start, so you must exit and restart Claude Code for the hooks to activate.

### Can I install this alongside other hooks?

Yes. Hooks run in parallel and don't interfere with each other.

### What if I don't have `jq` installed?

The installer will work without `jq`, but uses a Python fallback for JSON manipulation. Install `jq` for better error checking:
- macOS: `brew install jq`
- Linux: `apt-get install jq` or `yum install jq`

### Where are the hook scripts installed?

`~/.claude/hooks/pre-compact-handoff.py` and `~/.claude/hooks/session-restore.sh`

### Where are handoff files stored?

`~/.claude/handoff/{session-id}.md`

## Usage

### How do I know it's working?

After a `/compact` or auto-compact, check `~/.claude/handoff/` for a new `.md` file. You can also run `./test.sh` to verify installation.

### Can I manually trigger a handoff?

The hooks trigger automatically on compact. To test manually:
```bash
/compact  # In Claude Code session
ls ~/.claude/handoff/  # Check for new file
```

### How much context is preserved?

- Last 15 user messages (deduplicated)
- Last 10 assistant responses (filtered)
- Last 20 file paths

These are configurable in `pre-compact-handoff.py`.

### What gets filtered out?

- Duplicate messages (>85% similarity)
- API errors and rate limit messages
- Empty responses
- `[Request interrupted by user]` messages
- Bash commands (only real file paths are kept)

### Can I view the handoff files?

Yes, they're markdown files at `~/.claude/handoff/{session-id}.md`. You can read them with any text editor.

### Do handoff files expire?

No automatic expiration. You can manually clean them up:
```bash
rm ~/.claude/handoff/*.md
```

Or delete old files:
```bash
find ~/.claude/handoff -name "*.md" -mtime +30 -delete  # Older than 30 days
```

## Troubleshooting

### Hooks not firing

1. Check hooks are registered: `cat ~/.claude/settings.json | jq '.hooks'`
2. Check scripts exist: `ls -la ~/.claude/hooks/`
3. Check permissions: `chmod +x ~/.claude/hooks/*.sh ~/.claude/hooks/*.py`
4. Restart Claude Code

### Handoff file not created

1. Test PreCompact hook manually:
   ```bash
   echo '{"session_id":"test","transcript_path":"PATH"}' | \
     python3 ~/.claude/hooks/pre-compact-handoff.py
   ```
2. Check Python 3 is installed: `python3 --version`
3. Check transcript path exists (find it in `~/.claude/projects/`)

### Context not restored

1. Check handoff file exists for your session_id
2. Test SessionStart hook manually:
   ```bash
   echo '{"session_id":"YOUR_SESSION_ID"}' | \
     bash ~/.claude/hooks/session-restore.sh
   ```
3. Enable debug mode: `claude --debug`

### "Permission denied" errors

Make scripts executable:
```bash
chmod +x ~/.claude/hooks/pre-compact-handoff.py
chmod +x ~/.claude/hooks/session-restore.sh
```

### JSON parsing errors in settings.json

Restore from backup:
```bash
cp ~/.claude/settings.json.backup.TIMESTAMP ~/.claude/settings.json
```

Then reinstall:
```bash
./install.sh
```

## Configuration

### Can I change how many messages are preserved?

Yes. Edit `~/.claude/hooks/pre-compact-handoff.py`:

```python
MAX_USER_MESSAGES = 20        # Default: 15
MAX_ASSISTANT_CHARS = 1000    # Default: 800
```

Restart Claude Code after changes.

### Can I change the deduplication threshold?

Yes. Edit the `_dedup_messages` function in `pre-compact-handoff.py`:

```python
if ratio > 0.90:  # Default: 0.85 (85% similarity)
```

### Can I disable handoff for specific sessions?

Not currently. The hooks run for all sessions. You can manually delete unwanted handoff files.

## Performance

### Does this slow down Claude Code?

No. Hooks run in parallel and have timeouts:
- PreCompact: 30 seconds max
- SessionStart: 10 seconds max

Typical execution is <1 second for each.

### How much disk space do handoff files use?

Typically 5-10 KB per file. With 100 sessions, that's ~1 MB total.

### Does this increase token usage?

Yes, slightly. The restored context is injected as additional context, which counts toward input tokens. Typical overhead is 1000-2000 tokens per restoration.

## Uninstallation

### How do I uninstall?

```bash
./uninstall.sh
```

This removes hooks and optionally removes handoff files.

### Will uninstalling break my settings.json?

No. The uninstaller backs up settings.json before making changes and only removes the specific hooks it added.

### Can I reinstall after uninstalling?

Yes. Just run `./install.sh` again.

## Contributing

### How can I contribute?

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

### Where do I report bugs?

Open an issue on GitHub with:
- Claude Code version
- Operating system
- Steps to reproduce
- Relevant logs (use `claude --debug`)

### Can I suggest features?

Yes! Open an issue with the `enhancement` label.

## Advanced

### Can I customize the handoff format?

Yes. Edit the `write_handoff` function in `pre-compact-handoff.py`. The format is markdown, so you can add/remove sections as needed.

### Can I use this with custom MCP servers?

Yes. The hooks don't interfere with MCP servers.

### Can I use this in CI/CD?

Not recommended. This is designed for interactive sessions. CI/CD environments typically don't have long-running sessions that need context preservation.

### Can I use this with multiple Claude Code installations?

Yes, if they use different `~/.claude` directories. Otherwise, they'll share the same hooks and handoff files.
