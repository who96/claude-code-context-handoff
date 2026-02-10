#!/usr/bin/env bash
# Claude Code Context Handoff - Installation Script
# Installs hooks and registers them in settings.json

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Paths
CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
BACKUP_FILE="${SETTINGS_FILE}.backup.$(date +%Y%m%d_%H%M%S)"

# Script directory (where install.sh is located)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo -e "${GREEN}Claude Code Context Handoff - Installer${NC}"
echo "================================================"
echo ""

# Check if Claude Code is installed
if [ ! -d "$CLAUDE_DIR" ]; then
    echo -e "${RED}Error: Claude Code directory not found at ${CLAUDE_DIR}${NC}"
    echo "Please install Claude Code first: https://claude.ai/code"
    exit 1
fi

# Check if jq is installed
if ! command -v jq &> /dev/null; then
    echo -e "${YELLOW}Warning: jq not found. Installing hooks without JSON validation.${NC}"
    echo "Install jq for better error checking: brew install jq (macOS) or apt-get install jq (Linux)"
    USE_JQ=false
else
    USE_JQ=true
fi

# Create directories
echo "Creating directories..."
mkdir -p "$HOOKS_DIR"
mkdir -p "$HANDOFF_DIR"
echo -e "${GREEN}✓${NC} Directories created"

# Copy hook scripts
echo ""
echo "Installing hook scripts..."

if [ ! -f "${SCRIPT_DIR}/hooks/pre-compact-handoff.py" ]; then
    echo -e "${RED}Error: Hook scripts not found in ${SCRIPT_DIR}/hooks/${NC}"
    exit 1
fi

cp "${SCRIPT_DIR}/hooks/pre-compact-handoff.py" "${HOOKS_DIR}/"
cp "${SCRIPT_DIR}/hooks/session-restore.sh" "${HOOKS_DIR}/"

# Make scripts executable
chmod +x "${HOOKS_DIR}/pre-compact-handoff.py"
chmod +x "${HOOKS_DIR}/session-restore.sh"

echo -e "${GREEN}✓${NC} Hook scripts installed to ${HOOKS_DIR}"

# Backup settings.json
echo ""
echo "Backing up settings.json..."
if [ -f "$SETTINGS_FILE" ]; then
    cp "$SETTINGS_FILE" "$BACKUP_FILE"
    echo -e "${GREEN}✓${NC} Backup created: ${BACKUP_FILE}"
else
    echo -e "${YELLOW}Warning: settings.json not found. Creating new one.${NC}"
    echo '{}' > "$SETTINGS_FILE"
fi

# Register hooks in settings.json
echo ""
echo "Registering hooks in settings.json..."

if [ "$USE_JQ" = true ]; then
    # Use jq for safe JSON manipulation
    TEMP_FILE=$(mktemp)

    jq --arg hooks_dir "$HOOKS_DIR" '
    .hooks.PreCompact = [
        {
            "matcher": "*",
            "hooks": [
                {
                    "type": "command",
                    "command": ($hooks_dir + "/pre-compact-handoff.py"),
                    "timeout": 30
                }
            ]
        }
    ] |
    .hooks.SessionStart = (.hooks.SessionStart // []) + [
        {
            "matcher": "compact",
            "hooks": [
                {
                    "type": "command",
                    "command": "bash " + ($hooks_dir + "/session-restore.sh"),
                    "timeout": 10
                }
            ]
        }
    ]
    ' "$SETTINGS_FILE" > "$TEMP_FILE"

    mv "$TEMP_FILE" "$SETTINGS_FILE"
    echo -e "${GREEN}✓${NC} Hooks registered successfully"
else
    # Fallback: manual JSON editing (less safe)
    echo -e "${YELLOW}Warning: Registering hooks without jq. Please verify settings.json manually.${NC}"

    # Simple append (may create invalid JSON if hooks already exist)
    python3 << EOF
import json
import sys

try:
    with open('$SETTINGS_FILE', 'r') as f:
        settings = json.load(f)
except:
    settings = {}

if 'hooks' not in settings:
    settings['hooks'] = {}

settings['hooks']['PreCompact'] = [
    {
        "matcher": "*",
        "hooks": [
            {
                "type": "command",
                "command": "$HOOKS_DIR/pre-compact-handoff.py",
                "timeout": 30
            }
        ]
    }
]

if 'SessionStart' not in settings['hooks']:
    settings['hooks']['SessionStart'] = []

settings['hooks']['SessionStart'].append({
    "matcher": "compact",
    "hooks": [
        {
            "type": "command",
            "command": "bash $HOOKS_DIR/session-restore.sh",
            "timeout": 10
        }
    ]
})

with open('$SETTINGS_FILE', 'w') as f:
    json.dump(settings, f, indent=2)

print("Hooks registered")
EOF

    echo -e "${GREEN}✓${NC} Hooks registered"
fi

# Verify installation
echo ""
echo "Verifying installation..."

if [ -f "${HOOKS_DIR}/pre-compact-handoff.py" ] && [ -f "${HOOKS_DIR}/session-restore.sh" ]; then
    echo -e "${GREEN}✓${NC} Hook scripts present"
else
    echo -e "${RED}✗${NC} Hook scripts missing"
    exit 1
fi

if [ "$USE_JQ" = true ]; then
    if jq -e '.hooks.PreCompact' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} PreCompact hook registered"
    else
        echo -e "${RED}✗${NC} PreCompact hook not found in settings.json"
    fi

    if jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓${NC} SessionStart hook registered"
    else
        echo -e "${RED}✗${NC} SessionStart hook not found in settings.json"
    fi
fi

# Success message
echo ""
echo "================================================"
echo -e "${GREEN}Installation complete!${NC}"
echo ""
echo "Next steps:"
echo "1. Restart Claude Code to activate hooks:"
echo "   ${YELLOW}exit${NC}  # Exit current session"
echo "   ${YELLOW}claude${NC}  # Start new session"
echo ""
echo "2. Test the installation:"
echo "   Run ${YELLOW}/compact${NC} in Claude Code"
echo "   Check ${YELLOW}~/.claude/handoff/${NC} for handoff files"
echo ""
echo "Backup location: ${BACKUP_FILE}"
echo ""
echo "To uninstall, run: ${YELLOW}./uninstall.sh${NC}"
echo "================================================"
