#!/usr/bin/env python3
"""Inspect history; opt in to backed-up pruning/VACUUM after quitting Prism."""
import argparse
from datetime import datetime, timezone
from pathlib import Path
import sqlite3
from uuid import uuid4


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--database", type=Path, required=True)
    parser.add_argument("--apply", action="store_true", help="Back up and prune history; quit Prism first")
    parser.add_argument("--vacuum", action="store_true", help="Also reclaim free pages; requires --apply")
    args = parser.parse_args()
    if args.vacuum and not args.apply:
        parser.error("--vacuum requires --apply")
    path = args.database.expanduser().resolve()
    if not path.is_file():
        parser.error("Database file does not exist")
    connection = sqlite3.connect(path.as_uri() + ("?mode=rw" if args.apply else "?mode=ro"), uri=True, timeout=0.25)
    try:
        version = connection.execute("PRAGMA user_version").fetchone()[0]
        if version != 1:
            parser.error("Expected Prism schema version 1")
        def counts():
            return connection.execute("SELECT COUNT(*), COALESCE(SUM(length(CAST(payload AS BLOB))),0) FROM history").fetchone()
        print("History rows, payload bytes:", counts())
        if not args.apply:
            print("Inspection only. Quit Prism, then add --apply (and optionally --vacuum) to clean.")
            return
        backup = path.with_name(path.stem + ".pre-maintenance-" + datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ-") + uuid4().hex[:8] + ".sqlite3")
        with sqlite3.connect(backup) as destination:
            connection.backup(destination)
        print("Backup:", backup)
        with connection:
            connection.execute("BEGIN IMMEDIATE")
            connection.execute("""DELETE FROM history WHERE sequence IN (
              SELECT sequence FROM (SELECT sequence, ROW_NUMBER() OVER (
                PARTITION BY collection, lower(json_extract(payload,'$.id')) ORDER BY sequence DESC
              ) AS rank FROM history) WHERE rank > 5)""")
            connection.execute("""DELETE FROM history WHERE sequence IN (
              SELECT sequence FROM (SELECT sequence, ROW_NUMBER() OVER (ORDER BY sequence DESC) AS rank,
                SUM(length(CAST(payload AS BLOB))) OVER (ORDER BY sequence DESC) AS bytes
              FROM history) WHERE rank > 10000 OR bytes > 33554432)""")
        if args.vacuum:
            connection.execute("VACUUM")
            connection.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        print("Remaining history rows, payload bytes:", counts())
    finally:
        connection.close()


if __name__ == "__main__":
    main()
