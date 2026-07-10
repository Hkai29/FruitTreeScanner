#!/usr/bin/env python3
"""Generate static six-class semantic-review materials without dataset writes."""

from __future__ import annotations

import argparse
import html
import os
from collections import Counter
from pathlib import Path
from urllib.parse import quote

from dataset_io import class_count_matches_names, load_data_yaml, read_csv_rows


REPO_ROOT = Path(__file__).resolve().parents[2]
CORE_CLASS_NAMES = {
    "apple",
    "orange",
    "pear",
    "persimmon",
    "grape",
    "strawberry",
}
DECISION_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "risk_level",
    "issue_type",
    "recommended_action",
    "approved_action",
    "notes",
]
GATE_FIELDS = [
    "image_path",
    "label_path",
    "class_names",
    "contains_core_class",
    "contains_only_non_core_classes",
    "appears_in_fixed_test_plan",
    "risk_level",
    "issue_type",
    "recommended_action",
    "current_approved_action",
    "blocks_six_class_apply",
    "block_reason",
]


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a static local page for six-class manual review."
    )
    parser.add_argument(
        "--decisions",
        default="ml/audit_reports/core_class_manual_review_decisions.csv",
        help="Six-class manual decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--gate",
        default="ml/audit_reports/core_class_review_gate.csv",
        help="Six-class review gate CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--gate-summary",
        default="ml/audit_reports/core_class_review_gate_summary.md",
        help="Six-class review gate summary. Default: %(default)s",
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Source YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--html-output",
        default="ml/audit_reports/core_class_manual_review.html",
        help="Static HTML output. Default: %(default)s",
    )
    parser.add_argument(
        "--guide-output",
        default="ml/audit_reports/core_class_manual_review_guide.md",
        help="Review guide output. Default: %(default)s",
    )
    parser.add_argument(
        "--progress-output",
        default="ml/audit_reports/core_class_manual_review_progress.md",
        help="Progress summary output. Default: %(default)s",
    )
    return parser.parse_args()


def repo_path(value: str | Path) -> Path:
    path = Path(value)
    return path.resolve() if path.is_absolute() else (REPO_ROOT / path).resolve()


def display_path(path: Path) -> str:
    try:
        return str(path.resolve().relative_to(REPO_ROOT))
    except ValueError:
        return str(path.resolve())


def validate_inputs(
    data_yaml: Path,
    gate_summary: Path,
    decisions: list[dict[str, str]],
    gate_rows: list[dict[str, str]],
) -> dict[str, dict[str, str]]:
    config, errors = load_data_yaml(data_yaml)
    if errors or not class_count_matches_names(config):
        raise ValueError("data.yaml could not be validated for six-class review")
    if not CORE_CLASS_NAMES.issubset({str(name) for name in config["names"]}):
        raise ValueError("data.yaml is missing a required core class")
    if not gate_summary.exists():
        raise ValueError(f"Gate summary not found: {display_path(gate_summary)}")
    if "Rows blocking six-class apply" not in gate_summary.read_text(encoding="utf-8"):
        raise ValueError("Gate summary does not contain six-class blocking counts")

    gate_by_path = {row["image_path"]: row for row in gate_rows}
    decision_paths = {row["image_path"] for row in decisions}
    blocking_paths = {
        row["image_path"]
        for row in gate_rows
        if row["blocks_six_class_apply"] == "yes"
    }
    if decision_paths != blocking_paths:
        raise ValueError("Decisions CSV does not exactly match six-class blocking gate rows")
    if len(gate_by_path) != len(gate_rows):
        raise ValueError("Gate CSV contains duplicate image paths")
    return gate_by_path


def image_src(image_path: str, html_output: Path) -> str:
    source = repo_path(image_path)
    if not source.is_file():
        raise ValueError(f"Review image not found: {image_path}")
    relative = Path(os.path.relpath(source, html_output.parent.resolve()))
    return quote(relative.as_posix(), safe="/")


def stat_counts(rows: list[dict[str, str]]) -> dict[str, int]:
    approved = Counter(row["approved_action"] for row in rows)
    risk = Counter(row["risk_level"] for row in rows)
    recommended = Counter(row["recommended_action"] for row in rows)
    return {
        "total": len(rows),
        "high": risk["high"],
        "medium": risk["medium"],
        "pending": approved["pending_review"],
        "keep": approved["keep"],
        "exclude": approved["exclude_from_training"],
        "manual": approved["manual_review"],
        "recommended_exclude": sum(
            count
            for action, count in recommended.items()
            if action.startswith("exclude_from_training")
        ),
        "recommended_keep": recommended["keep"],
    }


def card_html(
    row: dict[str, str],
    gate_row: dict[str, str],
    html_output: Path,
) -> str:
    risk_level = row["risk_level"]
    fields = [
        ("image_path", row["image_path"], True),
        ("label_path", row["label_path"], True),
        ("class_names", row["class_names"], False),
        ("risk_level", row["risk_level"], False),
        ("issue_type", row["issue_type"], True),
        ("recommended_action", row["recommended_action"], True),
        ("approved_action", row["approved_action"], True),
        ("notes", row["notes"] or "(empty)", False),
        ("appears_in_fixed_test_plan", gate_row["appears_in_fixed_test_plan"], True),
        ("high_risk", "yes" if risk_level == "high" else "no", True),
    ]
    details = []
    for label, value, code in fields:
        rendered = html.escape(value)
        details.append(
            f"<dt>{html.escape(label)}</dt><dd>{f'<code>{rendered}</code>' if code else rendered}</dd>"
        )
    source = image_src(row["image_path"], html_output)
    return "\n".join(
        [
            '<article class="review-card">',
            '  <figure class="thumbnail">',
            f'    <img loading="lazy" src="{html.escape(source, quote=True)}" '
            f'alt="Review candidate: {html.escape(row["image_path"], quote=True)}">',
            "    <figcaption>Local source image; no copy is created.</figcaption>",
            "  </figure>",
            "  <dl>",
            *[f"    {detail}" for detail in details],
            "  </dl>",
            "</article>",
        ]
    )


def write_html(
    path: Path,
    rows: list[dict[str, str]],
    gate_by_path: dict[str, dict[str, str]],
    counts: dict[str, int],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sections = []
    for risk_level, title in (("high", "High risk"), ("medium", "Medium risk"), ("low", "Low risk")):
        risk_rows = [row for row in rows if row["risk_level"] == risk_level]
        if not risk_rows:
            continue
        cards = [card_html(row, gate_by_path[row["image_path"]], path) for row in risk_rows]
        sections.append(
            "\n".join(
                [
                    f'<section class="risk-group {risk_level}">',
                    f"  <h2>{title} <span>{len(risk_rows)}</span></h2>",
                    *cards,
                    "</section>",
                ]
            )
        )
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Six-Class Manual Review</title>
  <style>
    :root {{ color: #1c252b; background: #f4f6f7; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    body {{ margin: 0 auto; max-width: 1180px; padding: 28px; }}
    h1, h2, p {{ margin-top: 0; }} p, dd {{ line-height: 1.45; }}
    .notice {{ background: #fff3cd; border: 1px solid #d5a520; border-radius: 8px; padding: 14px; }}
    .summary {{ display: grid; gap: 10px; grid-template-columns: repeat(auto-fit, minmax(150px, 1fr)); margin: 20px 0 28px; }}
    .summary div {{ background: #fff; border: 1px solid #d7dce1; border-radius: 8px; padding: 14px; }}
    .summary strong {{ display: block; font-size: 1.55rem; }}
    .risk-group {{ border-top: 4px solid #6e7e8a; margin: 34px 0; padding-top: 16px; }}
    .risk-group.high {{ border-color: #ba3a32; }} .risk-group.medium {{ border-color: #ad7a16; }} .risk-group.low {{ border-color: #397b59; }}
    h2 span {{ color: #5e6a73; font-size: 1rem; font-weight: 500; }}
    .review-card {{ align-items: start; background: #fff; border: 1px solid #d7dce1; border-radius: 8px; display: grid; gap: 18px; grid-template-columns: minmax(180px, 240px) 1fr; margin: 14px 0; padding: 16px; }}
    figure {{ margin: 0; }} .thumbnail img {{ background: #e6eaed; display: block; height: 180px; object-fit: contain; width: 100%; }}
    figcaption {{ color: #5e6a73; font-size: .82rem; margin-top: 6px; }}
    dl {{ display: grid; gap: 8px 14px; grid-template-columns: 180px minmax(0, 1fr); margin: 0; }}
    dt {{ color: #53616a; font-weight: 650; }} dd {{ margin: 0; overflow-wrap: anywhere; }}
    code {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }}
    @media (max-width: 640px) {{ body {{ padding: 16px; }} .review-card {{ grid-template-columns: 1fr; }} dl {{ grid-template-columns: 1fr; gap: 3px; }} dt {{ margin-top: 8px; }} }}
  </style>
</head>
<body>
  <h1>Six-Class Manual Review</h1>
  <p class="notice">This static page is for human review only. It does not change approvals, labels, images, splits, or dataset membership. Record final decisions only in <code>core_class_manual_review_decisions.csv</code>.</p>
  <section class="summary">
    <div><strong>{counts['total']}</strong>total rows</div>
    <div><strong>{counts['high']}</strong>high-risk rows</div>
    <div><strong>{counts['medium']}</strong>medium-risk rows</div>
    <div><strong>{counts['pending']}</strong>pending rows</div>
    <div><strong>{counts['recommended_exclude']}</strong>recommended exclude rows</div>
    <div><strong>{counts['recommended_keep']}</strong>recommended keep rows</div>
  </section>
  {' '.join(sections)}
</body>
</html>
"""
    path.write_text(document, encoding="utf-8")


def write_guide(path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        """# Six-Class Manual Review Guide

This guide supports human decisions in `core_class_manual_review_decisions.csv`.
It does not authorize image deletion, relabeling, dataset copying, or apply.

## When to use `keep`

- The image clearly contains a core fruit.
- People, hands, or background do not obscure the fruit subject.
- Fruit bounding boxes and category are broadly correct.
- A real orchard scene is suitable for retention.

## When to use `exclude_from_training`

- Pornographic or otherwise unsuitable content is present.
- A computer, animal, document, clothing, bedding, or another clearly non-fruit subject dominates the image.
- The image does not contain the target fruit.
- The label category is clearly wrong and no label correction is planned now.
- Fruit is too small or cannot be identified reliably.

## When to use `manual_review`

- It is uncertain whether the subject is the target fruit.
- The category may be wrong but needs a human label correction decision.
- Fruit is present but annotations may be materially incomplete.
- Multiple categories are mixed and the correct action is uncertain.
""",
        encoding="utf-8",
    )


def write_progress(path: Path, counts: dict[str, int]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(
        "\n".join(
            [
                "# Six-Class Manual Review Progress",
                "",
                f"- Total rows: {counts['total']}",
                f"- Pending review rows: {counts['pending']}",
                f"- Keep rows: {counts['keep']}",
                f"- Exclude from training rows: {counts['exclude']}",
                f"- Manual review rows: {counts['manual']}",
                f"- High-risk pending rows: {counts['high'] if counts['pending'] else 0}",
                "- Six-class apply still blocked: yes",
                "",
                "All rows remain pending. This page does not modify approvals. "
                "The fixed-test and duplicate approval gates remain separate blockers.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    decisions = read_csv_rows(repo_path(args.decisions), DECISION_FIELDS)
    gate_rows = read_csv_rows(repo_path(args.gate), GATE_FIELDS)
    if not decisions:
        raise ValueError("Six-class decisions CSV is empty")
    html_output = repo_path(args.html_output)
    gate_by_path = validate_inputs(
        repo_path(args.data_yaml),
        repo_path(args.gate_summary),
        decisions,
        gate_rows,
    )
    counts = stat_counts(decisions)
    write_html(html_output, decisions, gate_by_path, counts)
    write_guide(repo_path(args.guide_output))
    write_progress(repo_path(args.progress_output), counts)
    print(f"Review rows: {counts['total']}")
    print(f"Image references: {counts['total']}")
    print(f"HTML written: {display_path(html_output)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
