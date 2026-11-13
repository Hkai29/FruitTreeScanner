#!/usr/bin/env python3
"""Preserve XCTest warning contexts and raw frames without inferring their cause.

The public summary omits unsymbolicated frames. Read the result database in
read-only mode and require its warning messages to match that same summary.
Unsupported database schemas fail explicitly; missing symbols are retained as
unknown, never interpreted as a missing stack or as application responsibility.
"""

import argparse
from collections import Counter
import json
import os
from pathlib import Path
import sqlite3
import subprocess
import sys


class EvidenceError(Exception):
    pass


def inspect(result_bundle, summary):
    warnings = summary.get("runtimeWarnings") if isinstance(summary, dict) else None
    if not isinstance(warnings, list) or any(
        not isinstance(w, dict) or not isinstance(w.get("message"), str) for w in warnings
    ):
        raise EvidenceError("Invalid runtime warning summary")
    database = Path(result_bundle).resolve() / "database.sqlite3"
    if not database.is_file():
        raise EvidenceError(f"Result database unavailable: {database}")
    try:
        connection = sqlite3.connect(database.as_uri() + "?mode=ro", uri=True)
        connection.row_factory = sqlite3.Row
        try:
            rows = connection.execute("""
                SELECT i.rowid AS issue_id, i.compactDescription AS message,
                       i.timestamp, i.sourceCodeContext_fk AS context_id,
                       i.testCaseRun_fk AS test_run_id, r.rowid AS found_test_run,
                       r.testCase_fk AS test_case_id, c.rowid AS found_test_case,
                       c.identifier AS test_identifier, c.identifierURL AS test_identifier_url
                FROM TestIssues i
                LEFT JOIN TestCaseRuns r ON i.testCaseRun_fk = r.rowid
                LEFT JOIN TestCases c ON r.testCase_fk = c.rowid
                WHERE i.issueType = 'Runtime Warning' ORDER BY i.timestamp, i.rowid
            """).fetchall()
            if Counter(row["message"] for row in rows) != Counter(w["message"] for w in warnings):
                raise EvidenceError("Runtime warning messages/count differ between summary and database")
            records = []
            for row in rows:
                record = dict(row)
                if (row["test_run_id"] is not None and (row["found_test_run"] is None
                        or row["test_case_id"] is None or row["found_test_case"] is None)):
                    raise EvidenceError(f"Missing test binding reference for warning {row['issue_id']}")
                del record["found_test_run"], record["found_test_case"]
                context = None
                frames = []
                if row["context_id"] is not None:
                    context = connection.execute("""
                        SELECT c.rowid, c.location_fk AS location_id, l.rowid AS found_location,
                               l.filePath AS file_path, l.lineNumber AS line
                        FROM SourceCodeContexts c
                        LEFT JOIN SourceCodeLocations l ON c.location_fk = l.rowid
                        WHERE c.rowid = ?
                    """, (row["context_id"],)).fetchone()
                    if context is None:
                        raise EvidenceError(f"Missing context for warning {row['issue_id']}")
                    if context["location_id"] is not None and context["found_location"] is None:
                        raise EvidenceError(f"Missing context source reference for warning {row['issue_id']}")
                    frames = [dict(frame) for frame in connection.execute("""
                        SELECT f.orderInContainer AS frame_index, f.address,
                               f.symbolInfo_fk AS symbol_info_id, s.rowid AS found_symbol,
                               s.location_fk AS location_id, l.rowid AS found_location,
                               s.symbolName AS symbol, s.imageName AS image,
                               l.filePath AS file_path, l.lineNumber AS line
                        FROM SourceCodeFrames f
                        LEFT JOIN SourceCodeSymbolInfos s ON f.symbolInfo_fk = s.rowid
                        LEFT JOIN SourceCodeLocations l ON s.location_fk = l.rowid
                        WHERE f.context_fk = ? ORDER BY f.orderInContainer, f.rowid
                    """, (row["context_id"],))]
                    for frame in frames:
                        if ((frame["symbol_info_id"] is not None and frame["found_symbol"] is None)
                                or (frame["location_id"] is not None and frame["found_location"] is None)):
                            raise EvidenceError(f"Missing frame source reference for warning {row['issue_id']}")
                        del frame["found_symbol"], frame["found_location"]
                record.update(
                    source_location={"location_id": context["location_id"], "file_path": context["file_path"], "line": context["line"]} if context else None,
                    frames=frames, frame_count=len(frames),
                    symbolicated_frame_count=sum(bool(f["symbol"]) for f in frames),
                    stack_status="frames_available" if frames else "context_without_frames" if context else "no_context",
                )
                records.append(record)
        finally:
            connection.close()
    except sqlite3.Error as error:
        raise EvidenceError(f"Cannot inspect runtime warning database/schema: {error}") from error
    return {
        "schema_version": 1, "result_bundle": str(Path(result_bundle).resolve()),
        "warning_count": len(records), "raw_frame_count": sum(w["frame_count"] for w in records),
        "warnings_without_frames": sum(not w["frames"] for w in records),
        "interpretation": "Test bindings record when a warning was reported; they do not establish its root cause. Unsymbolicated addresses remain stack evidence.",
        "warnings": records,
    }


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("result_bundle", type=Path)
    parser.add_argument("--summary", type=Path, help="Summary already read from this result by the workflow")
    args = parser.parse_args(argv)
    try:
        if args.summary:
            summary = json.loads(args.summary.read_text())
        else:
            env = dict(os.environ)
            env.setdefault("DEVELOPER_DIR", "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer")
            result = subprocess.run(["xcrun", "xcresulttool", "get", "test-results", "summary",
                "--path", str(args.result_bundle), "--compact"], capture_output=True, text=True, env=env)
            if result.returncode:
                raise EvidenceError("Cannot read runtime warning summary: " + result.stderr.strip())
            summary = json.loads(result.stdout)
        print(json.dumps(inspect(args.result_bundle, summary), indent=2, ensure_ascii=False))
        return 0
    except (EvidenceError, OSError, ValueError) as error:
        print(str(error), file=sys.stderr)
        return 2


if __name__ == "__main__":
    sys.exit(main())
