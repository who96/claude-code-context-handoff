#!/usr/bin/env python3
"""
PreCompact Hook: Extract key context before auto-compact or /compact.
Writes a handoff document so post-compact session can recover critical info.
"""

import json
import sys
import os
from datetime import datetime
from difflib import SequenceMatcher

HANDOFF_DIR = os.path.expanduser("~/.claude/handoff")
MAX_USER_MESSAGES = 15
MAX_ASSISTANT_CHARS = 800

# Junk patterns to filter from assistant snippets
JUNK_PATTERNS = (
    "API Error:", "rate_limit", "invalid_request_error", "overloaded",
    "No response requested", "(no content)",
)

# Junk patterns to filter from user messages
USER_JUNK_PATTERNS = ("[Request interrupted by user]",)

def _dedup_messages(messages):
    """Remove near-duplicate messages (>85% similarity)."""
    if not messages:
        return messages
    result = [messages[0]]
    for msg in messages[1:]:
        is_dup = False
        for kept in result:
            ratio = SequenceMatcher(None, msg[:200], kept[:200]).ratio()
            if ratio > 0.85:
                is_dup = True
                break
        if not is_dup:
            result.append(msg)
    return result


def extract_context(transcript_path):
    """Parse transcript JSONL, extract recent user messages and assistant summaries."""
    user_messages = []
    assistant_snippets = []
    files_mentioned = set()

    if not os.path.exists(transcript_path):
        return None

    with open(transcript_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type")

            if msg_type == "user":
                # Extract user message text
                message = obj.get("message", {})
                if isinstance(message, dict):
                    content = message.get("content", "")
                    if isinstance(content, list):
                        # Multi-part content
                        text_parts = []
                        for part in content:
                            if isinstance(part, dict) and part.get("type") == "text":
                                text_parts.append(part.get("text", ""))
                        content = "\n".join(text_parts)
                    if isinstance(content, str) and content.strip():
                        if not any(p in content for p in USER_JUNK_PATTERNS):
                            user_messages.append(content.strip())

            elif msg_type == "assistant":
                message = obj.get("message", {})
                if isinstance(message, dict):
                    content = message.get("content", [])
                    if isinstance(content, list):
                        for part in content:
                            if isinstance(part, dict):
                                if part.get("type") == "text":
                                    text = part.get("text", "")
                                    if text.strip():
                                        assistant_snippets.append(text.strip())
                                # Track files from tool use (only file_path/path, not commands)
                                if part.get("type") == "tool_use":
                                    tool_input = part.get("input", {})
                                    for key in ("file_path", "path"):
                                        val = tool_input.get(key, "")
                                        if isinstance(val, str) and val.startswith("/"):
                                            files_mentioned.add(val)

    # Take last N user messages, deduplicated
    recent_user = _dedup_messages(user_messages[-MAX_USER_MESSAGES * 2:])[-MAX_USER_MESSAGES:]

    # Take last few assistant snippets, filtered and truncated
    recent_assistant = []
    for snippet in assistant_snippets[-20:]:
        if any(p in snippet for p in JUNK_PATTERNS):
            continue
        if len(snippet) > MAX_ASSISTANT_CHARS:
            snippet = snippet[:MAX_ASSISTANT_CHARS] + "..."
        recent_assistant.append(snippet)
    recent_assistant = recent_assistant[-10:]

    # Take last 20 files
    recent_files = sorted(files_mentioned)[-20:]

    return {
        "user_messages": recent_user,
        "assistant_snippets": recent_assistant,
        "files_touched": recent_files,
    }


def write_handoff(context, session_id):
    """Write handoff markdown document, keyed by session_id."""
    os.makedirs(HANDOFF_DIR, exist_ok=True)
    handoff_file = os.path.join(HANDOFF_DIR, f"{session_id}.md")

    lines = []
    lines.append(f"# Context Handoff")
    lines.append(f"")
    lines.append(f"- **Generated**: {datetime.now().isoformat()}")
    lines.append(f"- **Session**: {session_id}")
    lines.append(f"- **Trigger**: PreCompact (auto-compact or /compact)")
    lines.append(f"")

    lines.append(f"## Recent User Requests")
    lines.append(f"")
    for i, msg in enumerate(context["user_messages"], 1):
        # Truncate very long messages
        if len(msg) > 500:
            msg = msg[:500] + "..."
        lines.append(f"### Turn {i}")
        lines.append(f"```")
        lines.append(msg)
        lines.append(f"```")
        lines.append(f"")

    if context["files_touched"]:
        lines.append(f"## Files Touched")
        lines.append(f"")
        for fp in context["files_touched"]:
            lines.append(f"- `{fp}`")
        lines.append(f"")

    lines.append(f"## Recent Assistant Context")
    lines.append(f"")
    for snippet in context["assistant_snippets"][-5:]:
        lines.append(f"> {snippet[:300]}")
        lines.append(f"")

    with open(handoff_file, "w") as f:
        f.write("\n".join(lines))

    return handoff_file


def main():
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    session_id = data.get("session_id", "unknown")
    transcript_path = data.get("transcript_path", "")

    if not transcript_path:
        sys.exit(0)

    context = extract_context(transcript_path)
    if not context or not context["user_messages"]:
        sys.exit(0)

    handoff_path = write_handoff(context, session_id)

    # Output JSON for Claude Code to inject as system message
    output = {
        "systemMessage": (
            f"[PreCompact Handoff] Context snapshot saved to {handoff_path}. "
            f"Captured {len(context['user_messages'])} user messages and "
            f"{len(context['files_touched'])} file references. "
            f"This context will be auto-restored after compaction."
        )
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
