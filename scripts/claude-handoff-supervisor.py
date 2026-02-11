#!/usr/bin/env python3
"""
Terminal supervisor for Claude Code.

Primary purpose:
- Rewrite manual `/compact` commands into `/clear` before they reach Claude.
- Keep everything else transparent.

This is an external controller because hooks cannot rewrite slash commands.
"""

from __future__ import annotations

import argparse
import os
import pty
import select
import signal
import subprocess
import sys
from typing import List


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Launch Claude with input rewriting for handoff-friendly clears."
    )
    parser.add_argument(
        "--claude-bin",
        default=os.environ.get("CLAUDE_BIN", "claude"),
        help="Claude executable path (default: claude)",
    )
    parser.add_argument(
        "--no-rewrite",
        action="store_true",
        help="Disable /compact -> /clear rewrite.",
    )
    parser.add_argument(
        "--quiet",
        action="store_true",
        help="Suppress supervisor informational messages.",
    )
    args, unknown = parser.parse_known_args()
    args.claude_args = unknown
    return args


def log(msg: str, quiet: bool) -> None:
    if not quiet:
        sys.stdout.write(f"\n[handoff-supervisor] {msg}\n")
        sys.stdout.flush()


def rewrite_line_if_needed(line: bytes, enabled: bool) -> bytes:
    if not enabled:
        return line

    try:
        text = line.decode("utf-8", errors="ignore")
    except Exception:
        return line

    # Keep the check strict to avoid rewriting normal prose.
    if text.strip() == "/compact":
        newline = "\n" if text.endswith("\n") else ""
        return f"/clear{newline}".encode("utf-8")

    return line


def run_supervisor(cmd: List[str], rewrite_enabled: bool, quiet: bool) -> int:
    master_fd, slave_fd = pty.openpty()
    proc = subprocess.Popen(cmd, stdin=slave_fd, stdout=slave_fd, stderr=slave_fd, close_fds=True)
    os.close(slave_fd)

    stdin_fd = sys.stdin.fileno()
    stdout_fd = sys.stdout.fileno()

    # In canonical mode stdin is line-buffered by terminal, which is enough
    # for slash-command rewrite and keeps implementation stable.
    line_buffer = b""

    def forward_signal(signum: int, _frame: object) -> None:
        if proc.poll() is None:
            proc.send_signal(signum)

    signal.signal(signal.SIGINT, forward_signal)
    signal.signal(signal.SIGTERM, forward_signal)

    log("Supervisor active. /compact will be rewritten to /clear.", quiet)

    child_done = False
    while True:
        child_done = proc.poll() is not None
        read_fds = [master_fd]
        if not child_done:
            read_fds.append(stdin_fd)
        ready, _, _ = select.select(read_fds, [], [], 0.1)

        if master_fd in ready:
            try:
                output = os.read(master_fd, 8192)
            except OSError:
                output = b""
            if not output:
                break
            os.write(stdout_fd, output)

        if not child_done and stdin_fd in ready:
            try:
                data = os.read(stdin_fd, 4096)
            except OSError:
                data = b""
            if not data:
                break

            line_buffer += data
            while b"\n" in line_buffer:
                line, line_buffer = line_buffer.split(b"\n", 1)
                original = line + b"\n"
                rewritten = rewrite_line_if_needed(original, rewrite_enabled)
                if rewritten != original:
                    log("Replaced '/compact' with '/clear'.", quiet)
                os.write(master_fd, rewritten)

        # Child has exited and no more pty output is ready.
        if child_done and master_fd not in ready:
            break

    # Flush remaining buffered stdin content if any.
    if line_buffer and proc.poll() is None:
        rewritten = rewrite_line_if_needed(line_buffer, rewrite_enabled)
        if rewritten != line_buffer:
            log("Replaced trailing '/compact' with '/clear'.", quiet)
        os.write(master_fd, rewritten)

    try:
        os.close(master_fd)
    except OSError:
        pass

    return proc.wait()


def main() -> None:
    args = parse_args()
    passthrough = args.claude_args
    if passthrough and passthrough[0] == "--":
        passthrough = passthrough[1:]

    cmd = [args.claude_bin] + passthrough
    exit_code = run_supervisor(cmd, rewrite_enabled=not args.no_rewrite, quiet=args.quiet)
    raise SystemExit(exit_code)


if __name__ == "__main__":
    main()
