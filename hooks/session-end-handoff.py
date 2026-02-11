#!/usr/bin/env python3
"""
SessionEnd Hook: capture context right before /clear tears down the session.
"""

import json
import sys

from handoff_core import extract_context, write_handoff


def main() -> None:
    try:
        data = json.load(sys.stdin)
    except (json.JSONDecodeError, EOFError):
        sys.exit(0)

    # Usually this hook is matcher-scoped to "clear", but keep a defensive check.
    source = data.get("source", "")
    if source and source != "clear":
        sys.exit(0)

    session_id = data.get("session_id", "unknown")
    transcript_path = data.get("transcript_path", "")
    source_cwd = data.get("cwd", "")
    if not transcript_path:
        sys.exit(0)

    context = extract_context(transcript_path)
    if not context or (not context["user_messages"] and not context["files_touched"]):
        sys.exit(0)

    handoff_result = write_handoff(
        context=context,
        session_id=session_id,
        trigger="SessionEnd(clear)",
        transcript_path=transcript_path,
        source_cwd=source_cwd,
    )

    output = {
        "systemMessage": (
            "[SessionEnd Handoff] Saved clear-transition snapshot to "
            f"{handoff_result['handoff_file']}; latest pointer: "
            f"{handoff_result['latest_handoff_file']}."
        )
    }
    print(json.dumps(output))


if __name__ == "__main__":
    main()
