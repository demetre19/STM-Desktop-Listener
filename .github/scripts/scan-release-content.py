#!/usr/bin/env python3
import re
import sys
from pathlib import Path

PERSONAL_PATTERN = re.compile(
    rb"/Users/[A-Za-z0-9._-]+|[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}"
)
PATTERNS = {
    "personal": PERSONAL_PATTERN,
    "personal-binary": PERSONAL_PATTERN,
    "credential": re.compile(
        rb"-----BEGIN [A-Z ]*PRIVATE KEY-----|github_pat_[A-Za-z0-9_]+|"
        rb"gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|"
        rb"Bearer[\t\n\r ]+[A-Za-z0-9._~-]{16,}"
    ),
}


def is_ignored_vendor_path(data: bytes, match: re.Match[bytes]) -> bool:
    return (
        match.group(0) == b"/Users/runner"
        and data[match.start():].startswith(b"/Users/runner/work/sherpa-onnx/")
    )


def main() -> int:
    if len(sys.argv) < 3 or sys.argv[1] not in PATTERNS:
        return 2
    kind = sys.argv[1]
    pattern = PATTERNS[kind]
    try:
        for raw_path in sys.argv[2:]:
            path = Path(raw_path)
            if not path.is_file():
                return 2
            data = path.read_bytes()
            for match in pattern.finditer(data):
                if kind == "personal-binary" and is_ignored_vendor_path(data, match):
                    continue
                return 0
    except OSError:
        return 2
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
