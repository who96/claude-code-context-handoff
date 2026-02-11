# Project Structure

```text
claude-code-context-handoff/
├── README.md
├── CHANGELOG.md
├── CONTRIBUTING.md
├── LICENSE
├── plugin.json
├── install.sh
├── uninstall.sh
├── test.sh
├── hooks/
│   ├── handoff_core.py
│   ├── pre-compact-handoff.py
│   ├── session-end-handoff.py
│   └── session-restore.sh
├── scripts/
│   └── claude-handoff-supervisor.py
├── docs/
│   └── FAQ.md
└── examples/
    └── handoff-example.md
```

## Installed Footprint

```text
~/.claude/
├── hooks/
│   ├── handoff_core.py
│   ├── pre-compact-handoff.py
│   ├── session-end-handoff.py
│   ├── session-restore.sh
│   └── claude-handoff-supervisor.py
├── handoff/
│   ├── <session-id>.md
│   ├── latest-handoff.md
│   └── latest-handoff.json
└── settings.json
```
