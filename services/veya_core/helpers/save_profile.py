#!/usr/bin/env python3
"""Save user profile JSON to ~/.veya/user_profile.json.
Called by the QML UI when onboarding completes or profile is edited.
Usage: python3 save_profile.py '<json_string>'
"""
from __future__ import annotations
import json
import sys
from pathlib import Path


def main() -> None:
    if len(sys.argv) != 2:
        print("Usage: save_profile.py '<json>'", file=sys.stderr)
        sys.exit(1)

    try:
        data = json.loads(sys.argv[1])
    except json.JSONDecodeError as e:
        print(f"Invalid JSON: {e}", file=sys.stderr)
        sys.exit(2)

    profile_dir = Path.home() / ".veya"
    profile_dir.mkdir(parents=True, exist_ok=True)
    profile_path = profile_dir / "user_profile.json"

    profile_path.write_text(json.dumps(data, indent=2))
    print(f"OK:{profile_path}")


if __name__ == "__main__":
    main()
