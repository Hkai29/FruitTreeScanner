#!/usr/bin/env python3
"""Build human-only HTML and CSV review materials from semantic audit reports.

The tool is read-only with respect to the dataset. It writes HTML, CSV, and
Markdown review materials only; image tags in the HTML reference local source
files with lazy loading and do not create thumbnails or dataset copies.
"""

from __future__ import annotations

import argparse
import csv
import html
import re
from collections import Counter
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_QUEUE = "ml/audit_reports/manual_review_priority_queue.csv"
DEFAULT_INVALID_REVIEW = "ml/audit_reports/dataset_invalid_image_review.csv"
DEFAULT_SEMANTIC_REVIEW = "ml/audit_reports/dataset_semantic_image_review.csv"
DEFAULT_HTML_OUTPUT = "ml/audit_reports/manual_review_priority_queue.html"
DEFAULT_DECISIONS_OUTPUT = "ml/audit_reports/manual_review_decisions.csv"
DEFAULT_STATISTICS = "ml/audit_reports/review_statistics.md"
QUEUE_FIELDS = {
    "image_path",
    "class_name",
    "issue_type",
    "vision_signal",
    "risk_level",
    "recommended_action",
    "review_reason",
}
SOURCE_FIELDS = {
    "image_path",
    "current_class",
    "issue_type",
    "confidence",
    "recommended_action",
    "notes",
}
DECISION_FIELDS = [
    "image_path",
    "class_name",
    "issue_type",
    "risk_level",
    "vision_signal",
    "recommended_action",
    "approved_action",
    "notes",
]
ALLOWED_APPROVED_ACTIONS = {
    "pending_review",
    "keep",
    "exclude_from_training",
    "relabel_needed",
    "review_later",
}
VISION_SIGNAL_PATTERN = re.compile(r"^vision_.+_(0(?:\.\d+)?|1(?:\.0+)?)$")
STRONG_NONFRUIT_SCORE = 0.85
ASSISTANT_MARKER = "## Review Assistant Artifacts"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Generate a local HTML review page and a pending-only decisions CSV "
            "without changing the dataset."
        )
    )
    parser.add_argument(
        "--queue",
        default=DEFAULT_QUEUE,
        help=f"Priority queue CSV. Default: {DEFAULT_QUEUE}",
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
        "--html-output",
        default=DEFAULT_HTML_OUTPUT,
        help=f"HTML review page. Default: {DEFAULT_HTML_OUTPUT}",
    )
    parser.add_argument(
        "--decisions-output",
        default=DEFAULT_DECISIONS_OUTPUT,
        help=f"Human decisions CSV template. Default: {DEFAULT_DECISIONS_OUTPUT}",
    )
    parser.add_argument(
        "--statistics",
        default=DEFAULT_STATISTICS,
        help=f"Existing statistics Markdown. Default: {DEFAULT_STATISTICS}",
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


def read_csv(path: Path, required_fields: set[str]) -> list[dict[str, str]]:
    if not path.exists():
        raise ValueError(f"CSV not found: {display_path(path)}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        missing = sorted(required_fields - set(reader.fieldnames or []))
        if missing:
            raise ValueError(
                f"CSV missing fields ({', '.join(missing)}): {display_path(path)}"
            )
        return [{key: (value or "").strip() for key, value in row.items()} for row in reader]


def vision_score(value: str) -> float:
    match = VISION_SIGNAL_PATTERN.fullmatch(value)
    return float(match.group(1)) if match else 0.0


def source_matches(
    queue_rows: list[dict[str, str]],
    invalid_rows: list[dict[str, str]],
    semantic_rows: list[dict[str, str]],
) -> tuple[set[str], set[str]]:
    invalid_paths = {row["image_path"] for row in invalid_rows}
    semantic_paths = {row["image_path"] for row in semantic_rows}
    queue_paths = {row["image_path"] for row in queue_rows}
    missing_invalid = queue_paths - invalid_paths
    missing_semantic = queue_paths - semantic_paths
    if missing_invalid:
        raise ValueError(
            "Priority queue paths missing from invalid-image audit: "
            f"{', '.join(sorted(missing_invalid)[:3])}"
        )
    if missing_semantic:
        raise ValueError(
            "Priority queue paths missing from semantic audit: "
            f"{', '.join(sorted(missing_semantic)[:3])}"
        )
    return invalid_paths, semantic_paths


def recommended_action(row: dict[str, str]) -> str:
    if (
        row["issue_type"] == "vision_nonfruit_signal"
        and vision_score(row["vision_signal"]) >= STRONG_NONFRUIT_SCORE
    ):
        return "exclude_from_training_candidate"
    if row["issue_type"] == "vision_nonfruit_signal" and row["risk_level"] == "low":
        return "review_later"
    return "manual_review"


def image_src(image_path: str, html_path: Path) -> str:
    source = repo_path(image_path)
    if not source.is_file():
        raise ValueError(f"Review image not found: {image_path}")
    relative = source.relative_to(html_path.parent.resolve().parent)
    return "../" + relative.as_posix()


def write_html(path: Path, queue_rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    summaries = Counter(row["risk_level"] for row in queue_rows)
    recommendations = Counter(recommended_action(row) for row in queue_rows)
    groups = (("high", "High risk"), ("medium", "Medium risk"), ("low", "Low risk"))

    sections: list[str] = []
    for risk_level, heading in groups:
        rows = [row for row in queue_rows if row["risk_level"] == risk_level]
        cards = []
        for row in rows:
            src = image_src(row["image_path"], path)
            cards.append(
                "\n".join(
                    [
                        '<article class="review-card">',
                        '  <figure class="thumbnail">',
                        f'    <img loading="lazy" src="{html.escape(src, quote=True)}" '
                        f'alt="Review candidate: {html.escape(row["image_path"], quote=True)}">',
                        "    <figcaption>Local source image; no copy created.</figcaption>",
                        "  </figure>",
                        "  <dl>",
                        f"    <dt>image_path</dt><dd><code>{html.escape(row['image_path'])}</code></dd>",
                        f"    <dt>class_name</dt><dd>{html.escape(row['class_name'])}</dd>",
                        f"    <dt>issue_type</dt><dd><code>{html.escape(row['issue_type'])}</code></dd>",
                        f"    <dt>vision_signal</dt><dd><code>{html.escape(row['vision_signal'])}</code></dd>",
                        f"    <dt>risk_level</dt><dd><span class=\"badge {risk_level}\">{html.escape(row['risk_level'])}</span></dd>",
                        f"    <dt>recommended_action</dt><dd><code>{html.escape(recommended_action(row))}</code></dd>",
                        f"    <dt>review_reason</dt><dd>{html.escape(row['review_reason'])}</dd>",
                        "  </dl>",
                        "</article>",
                    ]
                )
            )
        sections.append(
            "\n".join(
                [
                    f'<section class="risk-group {risk_level}">',
                    f"  <h2>{heading} <span>{len(rows)}</span></h2>",
                    *cards,
                    "</section>",
                ]
            )
        )

    document = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Semantic Dataset Review Queue</title>
  <style>
    :root { color: #1c252b; background: #f4f6f7; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0 auto; max-width: 1180px; padding: 28px; }
    h1, h2, p { margin-top: 0; }
    p, dd { line-height: 1.45; }
    .notice { background: #fff3cd; border: 1px solid #d5a520; border-radius: 8px; padding: 14px; }
    .summary { display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(160px, 1fr)); margin: 20px 0 28px; }
    .summary div { background: #fff; border: 1px solid #d7dce1; border-radius: 8px; padding: 14px; }
    .summary strong { display: block; font-size: 1.55rem; }
    .risk-group { border-top: 4px solid #6e7e8a; margin: 34px 0; padding-top: 16px; }
    .risk-group.high { border-color: #ba3a32; }
    .risk-group.medium { border-color: #ad7a16; }
    .risk-group.low { border-color: #397b59; }
    h2 span { color: #5e6a73; font-size: 1rem; font-weight: 500; }
    .review-card { align-items: start; background: #fff; border: 1px solid #d7dce1; border-radius: 8px; display: grid; gap: 18px; grid-template-columns: minmax(180px, 240px) 1fr; margin: 14px 0; padding: 16px; }
    figure { margin: 0; }
    .thumbnail img { background: #e6eaed; display: block; height: 180px; object-fit: contain; width: 100%; }
    figcaption { color: #5e6a73; font-size: .82rem; margin-top: 6px; }
    dl { display: grid; gap: 8px 14px; grid-template-columns: 155px minmax(0, 1fr); margin: 0; }
    dt { color: #53616a; font-weight: 650; }
    dd { margin: 0; overflow-wrap: anywhere; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }
    .badge { border-radius: 999px; color: #fff; display: inline-block; font-weight: 700; padding: 3px 9px; }
    .badge.high { background: #ba3a32; }
    .badge.medium { background: #ad7a16; }
    .badge.low { background: #397b59; }
    @media (max-width: 640px) { body { padding: 16px; } .review-card { grid-template-columns: 1fr; } dl { grid-template-columns: 1fr; gap: 3px; } dt { margin-top: 8px; } }
  </style>
</head>
<body>
  <h1>Semantic Dataset Review Queue</h1>
  <p class="notice">These are local source-image thumbnails for human curation and may include unsuitable or incorrectly labelled content. The page does not confirm an image is invalid, apply a decision, or alter the dataset. Record approvals only in <code>manual_review_decisions.csv</code>.</p>
  <section class="summary">
    <div><strong>__TOTAL__</strong>total review rows</div>
    <div><strong>__HIGH__</strong>high risk</div>
    <div><strong>__MEDIUM__</strong>medium risk</div>
    <div><strong>__LOW__</strong>low risk</div>
    <div><strong>__EXCLUDE__</strong>exclude candidates</div>
    <div><strong>__MANUAL__</strong>keep/manual review</div>
  </section>
  __SECTIONS__
</body>
</html>
"""
    document = (
        document.replace("__TOTAL__", str(len(queue_rows)))
        .replace("__HIGH__", str(summaries["high"]))
        .replace("__MEDIUM__", str(summaries["medium"]))
        .replace("__LOW__", str(summaries["low"]))
        .replace("__EXCLUDE__", str(recommendations["exclude_from_training_candidate"]))
        .replace("__MANUAL__", str(recommendations["manual_review"]))
        .replace("__SECTIONS__", "\n\n  ".join(sections))
    )
    path.write_text(document, encoding="utf-8")


def read_existing_decisions(path: Path) -> dict[str, dict[str, str]]:
    if not path.exists():
        return {}
    rows = read_csv(path, set(DECISION_FIELDS))
    decisions: dict[str, dict[str, str]] = {}
    for row in rows:
        action = row.get("approved_action", "pending_review")
        if action not in ALLOWED_APPROVED_ACTIONS:
            raise ValueError(
                f"Unsupported approved_action {action!r} in {display_path(path)}"
            )
        decisions[row["image_path"]] = row
    return decisions


def write_decisions(path: Path, queue_rows: list[dict[str, str]]) -> None:
    existing = read_existing_decisions(path)
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as handle:
        writer = csv.DictWriter(
            handle,
            fieldnames=DECISION_FIELDS,
            lineterminator="\n",
        )
        writer.writeheader()
        for row in queue_rows:
            prior = existing.get(row["image_path"], {})
            writer.writerow(
                {
                    "image_path": row["image_path"],
                    "class_name": row["class_name"],
                    "issue_type": row["issue_type"],
                    "risk_level": row["risk_level"],
                    "vision_signal": row["vision_signal"],
                    "recommended_action": recommended_action(row),
                    "approved_action": prior.get("approved_action", "pending_review"),
                    "notes": prior.get("notes", ""),
                }
            )


def append_statistics(path: Path, queue_rows: list[dict[str, str]]) -> None:
    if not path.exists():
        raise ValueError(f"Statistics report not found: {display_path(path)}")
    current = path.read_text(encoding="utf-8").rstrip()
    if ASSISTANT_MARKER in current:
        current = current.split(ASSISTANT_MARKER, maxsplit=1)[0].rstrip()
    risk_counts = Counter(row["risk_level"] for row in queue_rows)
    high_count = risk_counts["high"]
    appendix = "\n".join(
        [
            ASSISTANT_MARKER,
            "",
            f"- HTML review page generated for the {len(queue_rows)} first-pass rows.",
            "- `manual_review_decisions.csv` was generated with every approval set to `pending_review`.",
            "- These materials support human approval only; they do not alter images, labels, or dataset membership.",
            "- Dataset status remains: not approved for training.",
            f"- Resolve all {high_count} first-pass high-risk samples before considering training approval.",
            "",
        ]
    )
    path.write_text(f"{current}\n\n{appendix}", encoding="utf-8")


def main() -> int:
    args = parse_args()
    queue_rows = read_csv(repo_path(args.queue), QUEUE_FIELDS)
    invalid_rows = read_csv(repo_path(args.invalid_review), SOURCE_FIELDS)
    semantic_rows = read_csv(repo_path(args.semantic_review), SOURCE_FIELDS)
    if not queue_rows:
        raise ValueError("Priority queue is empty")
    source_matches(queue_rows, invalid_rows, semantic_rows)

    html_output = repo_path(args.html_output)
    decisions_output = repo_path(args.decisions_output)
    statistics_path = repo_path(args.statistics)
    write_html(html_output, queue_rows)
    write_decisions(decisions_output, queue_rows)
    append_statistics(statistics_path, queue_rows)

    risk_counts = Counter(row["risk_level"] for row in queue_rows)
    print(f"Review rows: {len(queue_rows)}")
    print(f"High risk: {risk_counts['high']}")
    print(f"Medium risk: {risk_counts['medium']}")
    print(f"Low risk: {risk_counts['low']}")
    print(f"HTML written: {display_path(html_output)}")
    print(f"Decision template written: {display_path(decisions_output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
