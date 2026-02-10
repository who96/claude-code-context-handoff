# Project Structure

```
claude-code-context-handoff/
├── .gitignore
├── LICENSE
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── plugin.json                    # Claude Code plugin metadata
├── install.sh                     # Installation script
├── uninstall.sh                   # Uninstallation script
├── test.sh                        # Test suite
├── hooks/
│   ├── pre-compact-handoff.py    # PreCompact hook (Python)
│   └── session-restore.sh        # SessionStart hook (Bash)
├── examples/
│   └── handoff-example.md        # Example handoff file output
└── docs/
    ├── ARCHITECTURE.md           # Technical architecture
    └── FAQ.md                    # Frequently asked questions
```

## File Descriptions

### Root Files

- **README.md** - Main documentation, installation guide, usage
- **LICENSE** - MIT License
- **CHANGELOG.md** - Version history
- **CONTRIBUTING.md** - Contribution guidelines
- **.gitignore** - Git ignore patterns
- **plugin.json** - Plugin metadata for Claude Code plugin system

### Scripts

- **install.sh** - Automated installation
  - Copies hooks to `~/.claude/hooks/`
  - Registers hooks in `~/.claude/settings.json`
  - Creates `~/.claude/handoff/` directory
  - Backs up settings.json

- **uninstall.sh** - Automated uninstallation
  - Removes hooks from `~/.claude/hooks/`
  - Removes hook registrations from settings.json
  - Optionally removes handoff files
  - Restores settings.json backup

- **test.sh** - Test suite
  - Verifies installation
  - Tests hook execution
  - Validates output format

### Hooks

- **hooks/pre-compact-handoff.py** - PreCompact hook
  - Parses transcript JSONL
  - Deduplicates messages
  - Filters junk
  - Extracts file paths
  - Writes handoff markdown

- **hooks/session-restore.sh** - SessionStart hook
  - Reads handoff file by session_id
  - Injects as additionalContext
  - Escapes JSON properly

### Documentation

- **docs/ARCHITECTURE.md** - Technical details
- **docs/FAQ.md** - Common questions
- **examples/handoff-example.md** - Sample output

## Installation Paths

When installed, files are placed at:

```
~/.claude/
├── hooks/
│   ├── pre-compact-handoff.py
│   └── session-restore.sh
├── handoff/
│   ├── {session-id-1}.md
│   ├── {session-id-2}.md
│   └── ...
└── settings.json (modified)
```

## Usage Paths

### As Standalone Installation

```bash
git clone https://github.com/YOUR_USERNAME/claude-code-context-handoff.git
cd claude-code-context-handoff
./install.sh
```

### As Claude Code Plugin (Future)

```bash
claude plugin install context-handoff
# or
claude plugin install github:YOUR_USERNAME/claude-code-context-handoff
```

## Development Workflow

1. Clone repository
2. Make changes to hooks/
3. Test with `./test.sh`
4. Test installation with `./install.sh`
5. Test in real Claude Code session
6. Test uninstallation with `./uninstall.sh`
7. Commit and push

## Release Workflow

1. Update version in `plugin.json`
2. Update `CHANGELOG.md`
3. Commit: `git commit -m "chore: release v1.x.x"`
4. Tag: `git tag v1.x.x`
5. Push: `git push origin main --tags`
6. Create GitHub release with changelog
