#!/usr/bin/env python3
"""Load user profile JSON from ~/.veya/user_profile.json.
Prints the JSON content to stdout. Prints empty JSON {} if file doesn't exist.
Exit codes: 0 = success (file exists or doesn't), non-zero = real error.
"""
import json
import sys
from pathlib import Path


def main():
    profile_path = Path.home() / ".veya" / "user_profile.json"

    if not profile_path.exists():
        print("{}")   # empty JSON means no profile, not an error
        sys.exit(0)

    try:
        data = json.loads(profile_path.read_text())
        print(json.dumps(data))
        sys.exit(0)
    except (json.JSONDecodeError, OSError) as e:
        print(json.dumps({"_error": str(e)}))
        sys.exit(0)   # still exit 0 so QML side gets the structured response


if __name__ == "__main__":
    main()
