#!/usr/bin/env python3
"""Fail CI when generated files, local paths, or mutable actions are tracked."""

from __future__ import annotations

import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
GENERATED_PATH = re.compile(r"(^|/)(build|\.dart_tool|node_modules)/")
ACTION_USE = re.compile(r"\buses:\s*([^\s#]+)")
COMMIT_PIN = re.compile(r"^[^@]+@[0-9a-f]{40}$")
LOCAL_PATH_FIXTURES = {"test/utils/error_message_separation_test.dart"}


def tracked_files() -> list[str]:
    result = subprocess.run(
        ["git", "ls-files"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout.splitlines()


def main() -> int:
    failures: list[str] = []
    files = tracked_files()

    generated = [path for path in files if GENERATED_PATH.search(path)]
    failures.extend(f"tracked generated path: {path}" for path in generated)

    home_prefix = "/" + "Users/"
    for path in files:
        file_path = ROOT / path
        try:
            text = file_path.read_text(encoding="utf-8")
        except (OSError, UnicodeDecodeError):
            continue
        if home_prefix in text and path not in LOCAL_PATH_FIXTURES:
            failures.append(f"developer-local absolute path: {path}")

    for workflow in sorted((ROOT / ".github/workflows").glob("*.yml")):
        for line_number, line in enumerate(workflow.read_text().splitlines(), 1):
            match = ACTION_USE.search(line)
            if not match:
                continue
            reference = match.group(1)
            if reference.startswith("./") or COMMIT_PIN.fullmatch(reference):
                continue
            failures.append(
                f"mutable action reference: {workflow.relative_to(ROOT)}:{line_number}: {reference}"
            )

    if failures:
        print("Repository hygiene checks failed:")
        print("\n".join(f"- {failure}" for failure in failures))
        return 1

    print("Repository hygiene checks passed")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
