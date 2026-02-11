#!/usr/bin/env bash
# Claude Code Context Handoff - Installation Script
# Installs hooks and registers them in settings.json

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Claude Code Context Handoff - Installer${NC}"
echo "================================================"
echo ""

if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}Error: Claude Code directory not found at ${CLAUDE_DIR}${NC}"
    echo "Please install Claude Code first: https://claude.ai/code"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${YELLOW}Warning: jq not found. Falling back to Python JSON editing.${NC}"
    USE_JQ=false
else
    USE_JQ=true
fi

echo "Creating directories..."
mkdir -p "$HOOKS_DIR"
mkdir -p "$HANDOFF_DIR"
echo -e "${GREEN}✓${NC} Directories created"

echo ""
echo "Installing hook and supervisor scripts..."

required_files=(
    "${SCRIPT_DIR}/hooks/pre-compact-handoff.py"
    "${SCRIPT_DIR}/hooks/session-end-handoff.py"
    "${SCRIPT_DIR}/hooks/session-restore.sh"
    "${SCRIPT_DIR}/hooks/handoff_core.py"
    "${SCRIPT_DIR}/scripts/claude-handoff-supervisor.py"
)

for file in "${required_files[@]}"; do
    if [ ! -f "$file" ]; then
        echo -e "${RED}Error: Required file missing: ${file}${NC}"
        exit 1
    fi
done

cp "${SCRIPT_DIR}/hooks/pre-compact-handoff.py" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/hooks/session-end-handoff.py" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/hooks/session-restore.sh" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/hooks/handoff_core.py" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/scripts/claude-handoff-supervisor.py" "${HOOKS_DIR}/"

chmod +x "${HOOKS_DIR}/pre-compact-handoff.py"
chmod +x "${HOOKS_DIR}/session-end-handoff.py"
chmod +x "${HOOKS_DIR}/session-restore.sh"
chmod +x "${HOOKS_DIR}/claude-handoff-supervisor.py"

echo -e "${GREEN}✓${NC} Scripts installed to ${HOOKS_DIR}"

echo ""
echo "Backing up settings.json..."
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Backup created: ${BACKUP_FILE}"
else
    echo -e "${YELLOW}Warning: settings.json not found. Creating new one.${NC}"
    echo '{}' > "$SETTINGS_FILE"
fi

echo ""
echo "Registering hooks in settings.json..."

if [ "$USE_JQ" = true ]; then
    temp_file="$(mktemp)"
    jq --arg hooks_dir "$HOOKS_DIR" '
      .hooks = (.hooks // {}) |
      .hooks.PreCompact = (
        ((.hooks.PreCompact // [])
          | map(select(((.hooks[0].command // "") | contains("pre-compact-handoff")) | not))
        ) + [
          {
            "matcher": "*",
            "hooks": [
              {
                "type": "command",
                "command": ("python3 " + $hooks_dir + "/pre-compact-handoff.py"),
                "timeout": 30
              }
            ]
          }
        ]
      ) |
      .hooks.SessionEnd = (
        ((.hooks.SessionEnd // [])
          | map(select(((.hooks[0].command // "") | contains("session-end-handoff")) | not))
        ) + [
          {
            "matcher": "clear",
            "hooks": [
              {
                "type": "command",
                "command": ("python3 " + $hooks_dir + "/session-end-handoff.py"),
                "timeout": 20
              }
            ]
          }
        ]
      ) |
      .hooks.SessionStart = (
        ((.hooks.SessionStart // [])
          | map(select(((.hooks[0].command // "") | contains("session-restore.sh")) | not))
        ) + [
          {
            "matcher": "compact",
            "hooks": [
              {
                "type": "command",
                "command": ("bash " + $hooks_dir + "/session-restore.sh"),
                "timeout": 10
              }
            ]
          },
          {
            "matcher": "clear",
            "hooks": [
              {
                "type": "command",
                "command": ("bash " + $hooks_dir + "/session-restore.sh"),
                "timeout": 10
              }
            ]
          }
        ]
      )
    ' "$SETTINGS_FILE" > "$temp_file"
    mv "$temp_file" "$SETTINGS_FILE"
else
    python3 - "$SETTINGS_FILE" "$HOOKS_DIR" <<'PY'
import json
import pathlib
import sys

settings_path = pathlib.Path(sys.argv[1])
hooks_dir = sys.argv[2]

try:
    settings = json.loads(settings_path.read_text(encoding="utf-8"))
except Exception:
    settings = {}

hooks = settings.setdefault("hooks", {})

def clean_entries(entries, markers):
    cleaned = []
    for entry in entries:
        command = ""
        try:
            command = str(entry.get("hooks", [{}])[0].get("command", ""))
        except Exception:
            command = ""
        if any(marker in command for marker in markers):
            continue
        cleaned.append(entry)
    return cleaned

hooks["PreCompact"] = clean_entries(
    hooks.get("PreCompact", []),
    ["pre-compact-handoff"],
) + [
    {
        "matcher": "*",
        "hooks": [
            {
                "type": "command",
                "command": f"python3 {hooks_dir}/pre-compact-handoff.py",
                "timeout": 30,
            }
        ],
    }
]

hooks["SessionEnd"] = clean_entries(
    hooks.get("SessionEnd", []),
    ["session-end-handoff"],
) + [
    {
        "matcher": "clear",
        "hooks": [
            {
                "type": "command",
                "command": f"python3 {hooks_dir}/session-end-handoff.py",
                "timeout": 20,
            }
        ],
    }
]

hooks["SessionStart"] = clean_entries(
    hooks.get("SessionStart", []),
    ["session-restore.sh"],
) + [
    {
        "matcher": "compact",
        "hooks": [
            {
                "type": "command",
                "command": f"bash {hooks_dir}/session-restore.sh",
                "timeout": 10,
            }
        ],
    },
    {
        "matcher": "clear",
        "hooks": [
            {
                "type": "command",
                "command": f"bash {hooks_dir}/session-restore.sh",
                "timeout": 10,
            }
        ],
    },
]

settings_path.write_text(json.dumps(settings, indent=2), encoding="utf-8")
print("Hooks registered")
PY
fi

echo -e "${GREEN}✓${NC} Hooks registered successfully"

echo ""
echo "Verifying installation..."

verify_files=(
    "${HOOKS_DIR}/pre-compact-handoff.py"
    "${HOOKS_DIR}/session-end-handoff.py"
    "${HOOKS_DIR}/session-restore.sh"
    "${HOOKS_DIR}/handoff_core.py"
    "${HOOKS_DIR}/claude-handoff-supervisor.py"
)

missing=0
for file in "${verify_files[@]}"; do
    if [ -f "$file" ]; then
        echo -e "${GREEN}✓${NC} $(basename "$file") present"
    else
        echo -e "${RED}✗${NC} Missing $(basename "$file")"
        missing=1
    fi
done

if [ "$missing" -ne 0 ]; then
    exit 1
fi

if [ "$USE_JQ" = true ]; then
    if jq -e '.hooks.PreCompact' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} PreCompact hook registered"
    else
        echo -e "${RED}✗${NC} PreCompact hook not found"
        exit 1
    fi

    if jq -e '.hooks.SessionEnd' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} SessionEnd hook registered"
    else
        echo -e "${RED}✗${NC} SessionEnd hook not found"
        exit 1
    fi

    if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" >/dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} SessionStart hook registered"
    else
        echo -e "${RED}✗${NC} SessionStart hook not found"
        exit 1
    fi
fi

echo ""
echo "================================================"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code:"
echo "   ${YELLOW}exit${NC}"
echo "   ${YELLOW}claude${NC}"
echo ""
echo "2. Recommended launch mode (rewrites /compact -> /clear):"
echo "   ${YELLOW}${HOOKS_DIR}/claude-handoff-supervisor.py${NC}"
echo ""
echo "3. Trigger a clear and verify restore:"
echo "   ${YELLOW}/clear${NC}"
echo "   Check ${YELLOW}~/.claude/handoff/latest-handoff.md${NC}"
echo ""
echo "Backup location: ${BACKUP_FILE}"
echo ""
echo "To uninstall, run: ${YELLOW}./uninstall.sh${NC}"
echo "================================================"
