# Claude Code Context Handoff

Automatic context preservation for Claude Code sessions. Prevents intelligence degradation after auto-compaction by extracting and restoring key context.

## The Problem

Claude Code auto-compacts context when it reaches ~95% capacity. After compaction, the session continues but loses critical information:
- Recent user requests
- Files you were working on
- Conversation flow

This causes:
- Repeated questions about things you already explained
- Loss of project context mid-task
- Degraded performance in long sessions

## The Solution

Two hooks that run automatically:

1. **PreCompact Hook** - Extracts context snapshot before compaction
2. **SessionStart Hook** - Restores context after compaction

No manual intervention. No `/compact` commands. Just continuous, intelligent sessions.

## How It Works

```
Context reaches 95% → Auto-compact triggered
    │
    ▼
PreCompact Hook fires
    → Parses conversation transcript
    → Deduplicates messages (>85% similarity filtered)
    → Filters junk (API errors, interruptions)
    → Extracts file paths from tool calls
    → Writes snapshot to ~/.claude/handoff/{session_id}.md
    │
    ▼
Compaction completes → SessionStart Hook fires
    → Reads snapshot for this session_id
    → Injects as additional context
    → Session continues with full memory
```

## Installation

```bash
git clone https://github.com/who96/claude-code-context-handoff.git
cd claude-code-context-handoff
./install.sh
```

The installer will:
1. Copy hooks to `~/.claude/hooks/`
2. Backup your `settings.json`
3. Register hooks in `~/.claude/settings.json`
4. Create `~/.claude/handoff/` directory

**Restart Claude Code** to activate hooks:
```bash
exit  # Exit current session
claude  # Start new session
```

## What Gets Preserved

### User Messages
- Last 15 user messages (deduplicated)
- Truncated to 500 chars each
- Filters out `[Request interrupted by user]`

### Assistant Context
- Last 10 assistant responses
- Truncated to 800 chars each
- Filters out API errors, rate limits, empty responses

### File References
- Last 20 file paths from tool calls
- Only real paths (excludes bash commands)

## Configuration

Edit the Python hook to customize:

```python
# ~/.claude/hooks/pre-compact-handoff.py

MAX_USER_MESSAGES = 15        # How many user messages to keep
MAX_ASSISTANT_CHARS = 800     # Max chars per assistant snippet
```

## Multi-Agent Safety

Each session gets its own handoff file:
```
~/.claude/handoff/
├── abc-123-def.md    ← Main agent
├── xyz-456-ghi.md    ← Subagent A
└── ...
```

No conflicts. No overwrites. Works with Claude Code teams.

## Compatibility

### Works With
- **Ralph Loop** - Complements `--resume` by protecting long-running sessions
- **Agent Teams** - Each team member gets independent context preservation
- **All Claude Code versions** - Uses standard hook API

### Does Not Conflict With
- Existing hooks (runs in parallel)
- Custom status line scripts
- MCP servers
- Plugins

## Verification

After installation, check hooks are registered:

```bash
cat ~/.claude/settings.json | grep -A 20 '"hooks"'
```

You should see:
```json
"hooks": {
  "PreCompact": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "command",
          "command": "python3 /Users/YOUR_USER/.claude/hooks/pre-compact-handoff.py",
          "timeout": 30
        }
      ]
    }
  ],
  "SessionStart": [
    {
      "matcher": "compact",
      "hooks": [
        {
          "type": "command",
          "command": "bash /Users/YOUR_USER/.claude/hooks/session-restore.sh",
          "timeout": 10
        }
      ]
    }
  ]
}
```

## Testing

Trigger a manual compact to test:

```bash
# In Claude Code session
/compact
```

Check that handoff file was created:
```bash
ls -la ~/.claude/handoff/
```

You should see a `.md` file named after your session ID.

## Troubleshooting

### Hooks not firing

**Check hook registration:**
```bash
cat ~/.claude/settings.json | jq '.hooks'
```

**Check hook scripts exist:**
```bash
ls -la ~/.claude/hooks/
```

**Check permissions:**
```bash
chmod +x ~/.claude/hooks/*.sh
chmod +x ~/.claude/hooks/*.py
```

### Handoff file not created

**Test PreCompact hook manually:**
```bash
echo '{"session_id":"test","transcript_path":"PATH_TO_YOUR_TRANSCRIPT"}' | \
  python3 ~/.claude/hooks/pre-compact-handoff.py
```

Replace `PATH_TO_YOUR_TRANSCRIPT` with actual path from:
```bash
ls ~/.claude/projects/*/
```

### Context not restored

**Check SessionStart hook:**
```bash
echo '{"session_id":"YOUR_SESSION_ID"}' | \
  bash ~/.claude/hooks/session-restore.sh
```

**Enable debug mode:**
```bash
claude --debug
```

Look for hook execution logs.

## Uninstallation

```bash
./uninstall.sh
```

This will:
1. Remove hooks from `~/.claude/hooks/`
2. Restore backup of `settings.json`
3. Optionally remove `~/.claude/handoff/` directory

## How This Differs From Other Solutions

| Feature | This Tool | Ralph `--resume` | Manual `/compact` |
|---------|-----------|------------------|-------------------|
| **Automatic** | ✅ | ❌ (requires script) | ❌ (manual command) |
| **Preserves context** | ✅ | ⚠️ (only loop metadata) | ❌ |
| **Multi-agent safe** | ✅ | N/A | N/A |
| **Zero config** | ✅ | ❌ (needs Ralph setup) | ✅ |
| **Works in teams** | ✅ | ❌ | ✅ |

## Technical Details

### PreCompact Hook
- **Language**: Python 3
- **Trigger**: Before auto-compact or `/compact`
- **Input**: JSON via stdin (session_id, transcript_path)
- **Output**: JSON with systemMessage
- **Timeout**: 30 seconds

### SessionStart Hook
- **Language**: Bash
- **Trigger**: After compaction (matcher: "compact")
- **Input**: JSON via stdin (session_id)
- **Output**: JSON with additionalContext
- **Timeout**: 10 seconds

### Handoff File Format
- **Location**: `~/.claude/handoff/{session_id}.md`
- **Format**: Markdown
- **Sections**: User Requests, Files Touched, Assistant Context
- **Retention**: Manual cleanup (no auto-expiration)

## Contributing

Contributions welcome. Focus areas:
- Better deduplication algorithms
- Configurable retention policies
- Handoff file compression
- Integration tests

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Credits

Inspired by the "Ralph Loop" pattern and community discussions about context degradation in long Claude Code sessions.

Built with the philosophy: **Good tools should be invisible. They just work.**
