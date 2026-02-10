#!/usr/bin/env bash
# Test script for Claude Code Context Handoff
# Verifies installation and basic functionality

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

CLAUDE_DIR="${HOME}/.claude"
HOOKS_DIR="${CLAUDE_DIR}/hooks"
HANDOFF_DIR="${CLAUDE_DIR}/handoff"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"

echo "Claude Code Context Handoff - Test Suite"
echo "========================================"
echo ""

TESTS_PASSED=0
TESTS_FAILED=0

# Test 1: Check hook scripts exist
echo "Test 1: Hook scripts exist"
if [ -f "${HOOKS_DIR}/pre-compact-handoff.py" ] && [ -f "${HOOKS_DIR}/session-restore.sh" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} - Hook scripts not found"
    ((TESTS_FAILED++))
fi

# Test 2: Check scripts are executable
echo "Test 2: Scripts are executable"
if [ -x "${HOOKS_DIR}/pre-compact-handoff.py" ] && [ -x "${HOOKS_DIR}/session-restore.sh" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} - Scripts not executable"
    ((TESTS_FAILED++))
fi

# Test 3: Check handoff directory exists
echo "Test 3: Handoff directory exists"
if [ -d "$HANDOFF_DIR" ]; then
    echo -e "${GREEN}✓ PASS${NC}"
    ((TESTS_PASSED++))
else
    echo -e "${RED}✗ FAIL${NC} - Handoff directory not found"
    ((TESTS_FAILED++))
fi

# Test 4: Check settings.json has hooks registered
echo "Test 4: Hooks registered in settings.json"
if command -v jq &> /dev/null; then
    if jq -e '.hooks.PreCompact' "$SETTINGS_FILE" > /dev/null 2>&1 && \
       jq -e '.hooks.SessionStart' "$SETTINGS_FILE" > /dev/null 2>&1; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} - Hooks not registered"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC} - jq not installed"
fi

# Test 5: Test PreCompact hook with dummy data
echo "Test 5: PreCompact hook execution"
TEST_SESSION="test-$(date +%s)"
TEST_TRANSCRIPT="${CLAUDE_DIR}/projects/-Users-huluobo-workSpace-paper-produce/e9c03882-eb47-4261-995a-0a3938fe5950.jsonl"

if [ -f "$TEST_TRANSCRIPT" ]; then
    OUTPUT=$(echo "{\"session_id\":\"${TEST_SESSION}\",\"transcript_path\":\"${TEST_TRANSCRIPT}\"}" | \
             python3 "${HOOKS_DIR}/pre-compact-handoff.py" 2>&1)

    if echo "$OUTPUT" | grep -q "systemMessage"; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))

        # Check if handoff file was created
        if [ -f "${HANDOFF_DIR}/${TEST_SESSION}.md" ]; then
            echo "  → Handoff file created: ${TEST_SESSION}.md"
        fi
    else
        echo -e "${RED}✗ FAIL${NC} - PreCompact hook failed"
        echo "  Output: $OUTPUT"
        ((TESTS_FAILED++))
    fi
else
    echo -e "${YELLOW}⊘ SKIP${NC} - No test transcript available"
fi

# Test 6: Test SessionStart hook
echo "Test 6: SessionStart hook execution"
if [ -f "${HANDOFF_DIR}/${TEST_SESSION}.md" ]; then
    OUTPUT=$(echo "{\"session_id\":\"${TEST_SESSION}\"}" | \
             bash "${HOOKS_DIR}/session-restore.sh" 2>&1)

    if echo "$OUTPUT" | grep -q "additionalContext"; then
        echo -e "${GREEN}✓ PASS${NC}"
        ((TESTS_PASSED++))
    else
        echo -e "${RED}✗ FAIL${NC} - SessionStart hook failed"
        echo "  Output: $OUTPUT"
        ((TESTS_FAILED++))
    fi

    # Cleanup test file
    rm -f "${HANDOFF_DIR}/${TEST_SESSION}.md"
else
    echo -e "${YELLOW}⊘ SKIP${NC} - No handoff file to test"
fi

# Summary
echo ""
echo "========================================"
echo "Test Results:"
echo -e "  ${GREEN}Passed: ${TESTS_PASSED}${NC}"
if [ $TESTS_FAILED -gt 0 ]; then
    echo -e "  ${RED}Failed: ${TESTS_FAILED}${NC}"
else
    echo -e "  Failed: 0"
fi
echo "========================================"

if [ $TESTS_FAILED -eq 0 ]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed. Check installation.${NC}"
    exit 1
fi
