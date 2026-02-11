#!/usr/bin/env python3
"""
Shared handoff extraction and serialization utilities.
"""

from __future__ import annotations

import json
import os
from datetime import datetime
from difflib import SequenceMatcher
from pathlib import Path
from typing import Dict, List, Optional, Set

HANDOFF_DIR = Path(os.path.expanduser("~/.claude/handoff"))
LATEST_HANDOFF_FILE = HANDOFF_DIR / "latest-handoff.md"
LATEST_META_FILE = HANDOFF_DIR / "latest-handoff.json"

DEFAULT_MAX_USER_MESSAGES = int(os.getenv("HANDOFF_MAX_USER_MESSAGES", "15"))
DEFAULT_MAX_ASSISTANT_CHARS = int(os.getenv("HANDOFF_MAX_ASSISTANT_CHARS", "800"))
DEFAULT_DEDUP_THRESHOLD = float(os.getenv("HANDOFF_DEDUP_THRESHOLD", "0.85"))

# Junk patterns to filter from assistant snippets
JUNK_PATTERNS = (
    "API Error:",
    "rate_limit",
    "invalid_request_error",
    "overloaded",
    "No response requested",
    "(no content)",
)

# Junk patterns to filter from user messages
USER_JUNK_PATTERNS = ("[Request interrupted by user]",)

# Strings that strongly suggest a shell command, not a file path.
COMMAND_LIKE_TOKENS = ("&&", "||", "|", ";", "$(", "`")


def dedup_messages(messages: List[str], threshold: float = DEFAULT_DEDUP_THRESHOLD) -> List[str]:
    """Remove near-duplicate messages using SequenceMatcher ratio."""
    if not messages:
        return messages

    result = [messages[0]]
    for msg in messages[1:]:
        is_duplicate = False
        for kept in result:
            ratio = SequenceMatcher(None, msg[:200], kept[:200]).ratio()
            if ratio >= threshold:
                is_duplicate = True
                break
        if not is_duplicate:
            result.append(msg)
    return result


def _collect_text_from_content(content: object) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        text_parts = []
        for part in content:
            if isinstance(part, dict) and part.get("type") == "text":
                text_parts.append(part.get("text", ""))
        return "\n".join(part for part in text_parts if part)
    return ""


def _looks_like_real_file_path(value: str) -> bool:
    if not value or not value.startswith("/"):
        return False
    if "\n" in value or "\r" in value:
        return False
    if any(token in value for token in COMMAND_LIKE_TOKENS):
        return False
    return True


def _collect_paths_recursive(obj: object, paths: Set[str]) -> None:
    if isinstance(obj, dict):
        for key, value in obj.items():
            if key in {"file_path", "path"} and isinstance(value, str):
                if _looks_like_real_file_path(value):
                    paths.add(value.strip())
            else:
                _collect_paths_recursive(value, paths)
    elif isinstance(obj, list):
        for item in obj:
            _collect_paths_recursive(item, paths)


def extract_context(
    transcript_path: str,
    max_user_messages: int = DEFAULT_MAX_USER_MESSAGES,
    max_assistant_chars: int = DEFAULT_MAX_ASSISTANT_CHARS,
    dedup_threshold: float = DEFAULT_DEDUP_THRESHOLD,
) -> Optional[Dict[str, List[str]]]:
    """Parse transcript JSONL and extract compact handoff context."""
    if not transcript_path or not os.path.exists(transcript_path):
        return None

    user_messages: List[str] = []
    assistant_snippets: List[str] = []
    files_mentioned: Set[str] = set()

    with open(transcript_path, "r", encoding="utf-8", errors="ignore") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue

            try:
                obj = json.loads(line)
            except json.JSONDecodeError:
                continue

            msg_type = obj.get("type")
            if msg_type == "user":
                message = obj.get("message", {})
                if isinstance(message, dict):
                    content = _collect_text_from_content(message.get("content", ""))
                    content = content.strip()
                    if content and not any(pattern in content for pattern in USER_JUNK_PATTERNS):
                        user_messages.append(content)

            elif msg_type == "assistant":
                message = obj.get("message", {})
                if isinstance(message, dict):
                    content = message.get("content", [])
                    if isinstance(content, list):
                        for part in content:
                            if not isinstance(part, dict):
                                continue
                            if part.get("type") == "text":
                                text = part.get("text", "").strip()
                                if text and not any(pattern in text for pattern in JUNK_PATTERNS):
                                    if len(text) > max_assistant_chars:
                                        text = text[:max_assistant_chars] + "..."
                                    assistant_snippets.append(text)
                            if part.get("type") == "tool_use":
                                _collect_paths_recursive(part.get("input", {}), files_mentioned)

    recent_user = dedup_messages(
        user_messages[-max_user_messages * 2 :], threshold=dedup_threshold
    )[-max_user_messages:]
    recent_assistant = assistant_snippets[-10:]
    recent_files = sorted(files_mentioned)[-20:]

    return {
        "user_messages": recent_user,
        "assistant_snippets": recent_assistant,
        "files_touched": recent_files,
    }


def write_handoff(
    context: Dict[str, List[str]],
    session_id: str,
    trigger: str,
    transcript_path: str = "",
    source_cwd: str = "",
) -> Dict[str, str]:
    """Write session handoff and update latest handoff pointer."""
    HANDOFF_DIR.mkdir(parents=True, exist_ok=True)

    timestamp = datetime.now().isoformat()
    handoff_file = HANDOFF_DIR / f"{session_id}.md"
    generated_from = transcript_path if transcript_path else "(unknown)"

    lines: List[str] = []
    lines.append("# Context Handoff")
    lines.append("")
    lines.append(f"- **Generated**: {timestamp}")
    lines.append(f"- **Session**: {session_id}")
    lines.append(f"- **Trigger**: {trigger}")
    lines.append(f"- **Transcript**: `{generated_from}`")
    if source_cwd:
        lines.append(f"- **CWD**: `{source_cwd}`")
    lines.append("")
    lines.append("## Recent User Requests")
    lines.append("")

    for idx, msg in enumerate(context.get("user_messages", []), start=1):
        if len(msg) > 500:
            msg = msg[:500] + "..."
        lines.append(f"### Turn {idx}")
        lines.append("```")
        lines.append(msg)
        lines.append("```")
        lines.append("")

    files_touched = context.get("files_touched", [])
    if files_touched:
        lines.append("## Files Touched")
        lines.append("")
        for path in files_touched:
            lines.append(f"- `{path}`")
        lines.append("")

    snippets = context.get("assistant_snippets", [])
    if snippets:
        lines.append("## Recent Assistant Context")
        lines.append("")
        for snippet in snippets[-5:]:
            lines.append(f"> {snippet[:300]}")
            lines.append("")

    markdown = "\n".join(lines)
    handoff_file.write_text(markdown, encoding="utf-8")
    LATEST_HANDOFF_FILE.write_text(markdown, encoding="utf-8")

    latest_meta = {
        "generated_at": timestamp,
        "trigger": trigger,
        "session_id": session_id,
        "cwd": source_cwd,
        "handoff_file": str(handoff_file),
    }
    LATEST_META_FILE.write_text(
        json.dumps(latest_meta, ensure_ascii=False, indent=2), encoding="utf-8"
    )

    return {
        "handoff_file": str(handoff_file),
        "latest_handoff_file": str(LATEST_HANDOFF_FILE),
        "latest_meta_file": str(LATEST_META_FILE),
    }
