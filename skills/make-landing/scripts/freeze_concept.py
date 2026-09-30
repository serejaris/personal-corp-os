#!/usr/bin/env python3
"""Record or verify a design concept before implementation (local audit aid)."""
import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("action", choices=("freeze", "verify"))
    parser.add_argument("directory", type=Path, help="Owned variant directory containing design.md")
    args = parser.parse_args()
    concept = args.directory / "design.md"
    record = args.directory / "concept-freeze.json"
    if not concept.is_file() or not concept.read_text(encoding="utf-8").strip():
        parser.exit(1, "STOP: write a complete design.md before implementation.\n")
    digest = hashlib.sha256(concept.read_bytes()).hexdigest()
    if args.action == "freeze":
        payload = {
            "schema_version": 1,
            "concept": "design.md",
            "sha256": digest,
            "frozen_at_utc": datetime.now(timezone.utc).isoformat(),
            "stage": "before_implementation",
        }
        try:
            with record.open("x", encoding="utf-8") as out:
                json.dump(payload, out, ensure_ascii=False, indent=2)
                out.write("\n")
        except FileExistsError:
            parser.exit(1, "STOP: existing freeze cannot be overwritten; verify it and record QA amendments separately.\n")
        print(f"FROZEN {concept}: {digest}")
    else:
        try:
            payload = json.loads(record.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            parser.exit(1, f"STOP: valid concept-freeze.json required: {exc}\n")
        if not isinstance(payload, dict) or payload.get("schema_version") != 1 or payload.get("concept") != "design.md" or payload.get("sha256") != digest:
            parser.exit(1, "STOP: concept differs from freeze or record is invalid. Preserve original and use design-amendments.md.\n")
        try:
            stamp = datetime.fromisoformat(payload["frozen_at_utc"])
            if stamp.tzinfo is None or payload.get("stage") != "before_implementation":
                raise ValueError("missing UTC timestamp or stage")
        except (KeyError, TypeError, ValueError) as exc:
            parser.exit(1, f"STOP: invalid freeze metadata: {exc}\n")
        print(f"VERIFIED {concept}: {digest} (frozen {stamp.isoformat()})")


if __name__ == "__main__":
    main()
