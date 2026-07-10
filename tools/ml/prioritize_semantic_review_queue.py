#!/usr/bin/env python3
"""Create a bounded first-pass human review queue from semantic audit reports.

The tool is read-only with respect to the dataset. It reads existing audit CSVs
and writes only a compact priority queue plus a Markdown statistics report.
It never deletes, moves, copies, or relabels images.
"""

from __future__ import annotations

import argparse
import csv
import re
from collections import Counter, defaultdict
from dataclasses import dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_INVALID_REVIEW = "ml/audit_reports/dataset_invalid_image_review.csv"
DEFAULT_SEMANTIC_REVIEW = "ml/audit_reports/dataset_semantic_image_review.csv"
DEFAULT_QUEUE_OUTPUT = "ml/audit_reports/manual_review_priority_queue.csv"
DEFAULT_STATISTICS_OUTPUT = "ml/audit_reports/review_statistics.md"
DEFAULT_FIRST_PASS_LIMIT = 200
REQUIRED_FIELDS = {
    "image_path",
    "current_class",
    "issue_type",
    "confidence",
    "recommended_action",
    "notes",
}
QUEUE_FIELDS = [
    "image_path",
    "class_name",
    "issue_type",
    "vision_signal",
    "risk_level",
    "recommended_action",
    "review_reason",
]
VISION_SIGNAL_PATTERN = re.compile(r"^vision_(.+)_(0(?:\.\d+)?|1(?:\.0+)?)$")
STRONG_NONFRUIT_SCORE = 0.85
OBJECT_DOMINANT_SCORE = 0.70


@dataclass(frozen=True)
class QueueEntry:
    image_path: str
    class_name: str
    issue_type: str
    vision_signal: str
    confidence_score: float
    risk_level: str
    recommended_action: str
    review_reason: str
    priority_group: int


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Create a bounded, priority-sorted human semantic review queue without "
            "changing dataset files."
        )
    )
    parser.add_argument(
        "--invalid-review",
        default=DEFAULT_INVALID_REVIEW,
        help=f"Combined invalid-image review CSV. Default: {DEFAULT_INVALID_REVIEW}",
    )
    parser.add_argument(
        "--semantic-review",
        default=DEFAULT_SEMANTIC_REVIEW,
        help=f"Apple Vision semantic review CSV. Default: {DEFAULT_SEMANTIC_REVIEW}",
    )
    parser.add_argument(
        "--queue-output",
        default=DEFAULT_QUEUE_OUTPUT,
        help=f"First-pass queue CSV. Default: {DEFAULT_QUEUE_OUTPUT}",
    )
    parser.add_argument(
        "--statistics-output",
        default=DEFAULT_STATISTICS_OUTPUT,
        help=f"Markdown statistics report. Default: {DEFAULT_STATISTICS_OUTPUT}",
    )
    parser.add_argument(
        "--first-pass-limit",
        type=int,
        default=DEFAULT_FIRST_PASS_LIMIT,
        help=(
            "Target number of first-pass candidates. All high-risk entries are "
            f"retained even if this limit is exceeded. Default: {DEFAULT_FIRST_PASS_LIMIT}"
        ),
    )
    return parser.parse_args()


def repo_path(value: str) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (REPO_ROOT / path).resolve()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def read_review_csv(path: Path) -> list[dict[str, str]]:
    if not path.exists():
        raise ValueError(f"Review CSV not found: {display_path(path)}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fields = set(reader.fieldnames or [])
        missing = sorted(REQUIRED_FIELDS - fields)
        if missing:
            raise ValueError(
                f"Review CSV missing fields ({', '.join(missing)}): {display_path(path)}"
            )
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def parse_vision_signal(value: str) -> tuple[str, float]:
    match = VISION_SIGNAL_PATTERN.fullmatch(value)
    if match is None:
        return value or "unavailable", 0.0
    return match.group(1), float(match.group(2))


def semantic_signal(
    final_row: dict[str, str], semantic_by_path: dict[str, dict[str, str]]
) -> tuple[str, float, bool]:
    semantic_row = semantic_by_path.get(final_row["image_path"])
    if semantic_row is not None:
        signal, score = parse_vision_signal(semantic_row["confidence"])
        return semantic_row["confidence"] or signal, score, True
    signal, score = parse_vision_signal(final_row["confidence"])
    return final_row["confidence"] or signal, score, False


def classify_row(
    row: dict[str, str], semantic_by_path: dict[str, dict[str, str]]
) -> QueueEntry:
    vision_signal, score, semantic_match = semantic_signal(row, semantic_by_path)
    issue_type = row["issue_type"]

    if issue_type == "vision_fruit_class_disagreement":
        risk_level = "high"
        priority_group = 0
        reason = "Vision named a fruit category that conflicts with the current YOLO label."
    elif issue_type == "vision_nonfruit_signal" and score >= STRONG_NONFRUIT_SCORE:
        risk_level = "high"
        priority_group = 1
        reason = "High-confidence non-fruit Vision signal; verify that the image is usable."
    elif issue_type == "vision_nonfruit_signal" and score >= OBJECT_DOMINANT_SCORE:
        risk_level = "high"
        priority_group = 2
        reason = "A non-fruit object may dominate the frame; verify fruit evidence and label fit."
    elif issue_type == "vision_people_without_fruit_signal":
        risk_level = "medium"
        priority_group = 3
        reason = "Vision found people without a fruit signal; verify that fruit evidence is present."
    elif issue_type == "vision_nonfruit_signal":
        risk_level = "medium"
        priority_group = 4
        reason = "Weak non-fruit Vision signal; review after higher-risk semantic conflicts."
    else:
        risk_level = "low"
        priority_group = 5
        reason = "Weak or unavailable semantic signal; retain for later manual review."

    if not semantic_match:
        reason += " Semantic sidecar row was unavailable, so the combined audit signal was used."

    return QueueEntry(
        image_path=row["image_path"],
        class_name=row["current_class"] or "unknown",
        issue_type=issue_type,
        vision_signal=vision_signal,
        confidence_score=score,
        risk_level=risk_level,
        recommended_action="manual_review",
        review_reason=reason,
        priority_group=priority_group,
    )


def sort_key(entry: QueueEntry) -> tuple[int, float, str]:
    return entry.priority_group, -entry.confidence_score, entry.image_path


def class_names(value: str) -> list[str]:
    names = [name.strip() for name in value.split("|") if name.strip()]
    return names or ["unknown"]


def risk_percent(count: int, total: int) -> str:
    return f"{(count / total * 100):.1f}%" if total else "0.0%"


def write_queue(path: Path, entries: list[QueueEntry]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=QUEUE_FIELDS,
            lineterminator="\n",
        )
        writer.writeheader()
        for entry in entries:
            writer.writerow(
                {
                    "image_path": entry.image_path,
                    "class_name": entry.class_name,
                    "issue_type": entry.issue_type,
                    "vision_signal": entry.vision_signal,
                    "risk_level": entry.risk_level,
                    "recommended_action": entry.recommended_action,
                    "review_reason": entry.review_reason,
                }
            )


def write_statistics(
    path: Path,
    entries: list[QueueEntry],
    selected: list[QueueEntry],
    semantic_matches: int,
    first_pass_limit: int,
) -> None:
    risks = ("high", "medium", "low")
    by_group = Counter(entry.priority_group for entry in entries)
    by_risk = Counter(entry.risk_level for entry in entries)
    by_class: dict[str, Counter[str]] = defaultdict(Counter)
    for entry in entries:
        for name in class_names(entry.class_name):
            by_class[name]["total"] += 1
            by_class[name][entry.risk_level] += 1

    deferred = len(entries) - len(selected)
    high_count = by_risk["high"]
    medium_selected = sum(entry.risk_level == "medium" for entry in selected)
    lines = [
        "# Semantic Manual Review Statistics",
        "",
        "## Scope",
        "",
        "This report prioritizes existing `manual_review` rows only. It does not "
        "make dataset changes or confirm that an image is invalid. Apple Vision is "
        "a triage signal and requires human verification.",
        "",
        f"- Full manual-review population: {len(entries)} images",
        f"- Semantic sidecar matches: {semantic_matches}/{len(entries)} images",
        f"- First-pass queue target: {first_pass_limit} images",
        f"- Recommended first-pass review: {len(selected)} images",
        f"- Deferred after first pass: {deferred} images",
        "",
        "The first pass retains every high-risk entry, then fills remaining places "
        "with the highest-priority medium-risk entries. Deferred rows remain in the "
        "source audit CSV and are not approved for training by this report.",
        "",
        "## Risk Distribution",
        "",
        "| Risk level | Images | Share of manual-review population |",
        "| --- | ---: | ---: |",
    ]
    lines.extend(
        f"| {risk} | {by_risk[risk]} | {risk_percent(by_risk[risk], len(entries))} |"
        for risk in risks
    )
    lines.extend(
        [
            "",
            "## Priority Categories",
            "",
            "| Priority | Rule | Images |",
            "| --- | --- | ---: |",
            f"| 1 | Fruit-class disagreement | {by_group[0]} |",
            f"| 2 | Strong non-fruit signal (score >= {STRONG_NONFRUIT_SCORE:.2f}) | {by_group[1]} |",
            f"| 3 | Object-dominant non-fruit signal (score >= {OBJECT_DOMINANT_SCORE:.2f}) | {by_group[2]} |",
            f"| 4 | People without fruit signal | {by_group[3]} |",
            f"| 5 | Weak non-fruit signal | {by_group[4]} |",
            f"| Later | Weak or unavailable signal | {by_group[5]} |",
            "",
            "## Manual Review by Current Class",
            "",
            "Multi-label images are counted once for each listed current class, so this "
            "table can sum to more than the number of image rows.",
            "",
            "| Current class | Manual-review images | High | Medium | Low | High-risk share |",
            "| --- | ---: | ---: | ---: | ---: | ---: |",
        ]
    )
    for name, counts in sorted(by_class.items(), key=lambda item: (-item[1]["total"], item[0])):
        total = counts["total"]
        lines.append(
            f"| {name} | {total} | {counts['high']} | {counts['medium']} | "
            f"{counts['low']} | {risk_percent(counts['high'], total)} |"
        )
    lines.extend(
        [
            "",
            "## Recommended Review Order",
            "",
            f"Review the {high_count} high-risk images first. The bounded first-pass "
            f"queue then includes {medium_selected} medium-risk images to reach "
            f"{len(selected)} total items. Resolve class disagreements and likely "
            "non-fruit/object-dominant frames before reviewing people-only and weak "
            "signals. Do not delete, move, relabel, or train on any item solely from "
            "this automated triage.",
            "",
        ]
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines), encoding="utf-8")


def main() -> int:
    args = parse_args()
    if args.first_pass_limit <= 0:
        raise ValueError("--first-pass-limit must be positive")

    invalid_rows = read_review_csv(repo_path(args.invalid_review))
    semantic_rows = read_review_csv(repo_path(args.semantic_review))
    semantic_by_path = {row["image_path"]: row for row in semantic_rows}
    manual_rows = [
        row for row in invalid_rows if row["recommended_action"] == "manual_review"
    ]
    entries = sorted(
        (classify_row(row, semantic_by_path) for row in manual_rows), key=sort_key
    )
    semantic_matches = sum(entry.image_path in semantic_by_path for entry in entries)

    high_risk_entries = [entry for entry in entries if entry.risk_level == "high"]
    selection_size = max(args.first_pass_limit, len(high_risk_entries))
    selected = entries[:selection_size]

    queue_path = repo_path(args.queue_output)
    statistics_path = repo_path(args.statistics_output)
    write_queue(queue_path, selected)
    write_statistics(
        statistics_path,
        entries,
        selected,
        semantic_matches,
        args.first_pass_limit,
    )

    print(f"Full manual-review population: {len(entries)}")
    print(f"High-risk entries retained: {len(high_risk_entries)}")
    print(f"First-pass queue: {len(selected)}")
    print(f"Queue written: {display_path(queue_path)}")
    print(f"Statistics written: {display_path(statistics_path)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
