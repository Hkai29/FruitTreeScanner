#!/usr/bin/env python3
"""Generate a static local review page for unresolved duplicate conflicts only."""

from __future__ import annotations

import argparse
import html
import os
from collections import defaultdict
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
    "duplicate_group_id",
    "image_path",
    "label_path",
    "class_names",
    "bbox_count",
    "label_fingerprint",
    "recommended_action",
    "approved_action",
    "human_review_required",
    "notes",
]
UNRESOLVED_ACTIONS = {"pending_review", "review_label_conflict", "manual_review", ""}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Generate a static local page for unresolved duplicate conflicts."
    )
    parser.add_argument(
        "--decisions",
        default="ml/audit_reports/duplicate_cleanup_decisions.csv",
        help="Duplicate cleanup decision CSV. Default: %(default)s",
    )
    parser.add_argument(
        "--review-pack",
        default="ml/audit_reports/duplicate_review_pack.md",
        help="Existing duplicate review pack. Default: %(default)s",
    )
    parser.add_argument(
        "--visual-review",
        default="ml/audit_reports/duplicate_visual_review.html",
        help="Existing duplicate visual review. Default: %(default)s",
    )
    parser.add_argument(
        "--data-yaml",
        default="ml/datasets/fruit_dataset_26/data.yaml",
        help="Source YOLO data.yaml. Default: %(default)s",
    )
    parser.add_argument(
        "--html-output",
        default="ml/audit_reports/duplicate_conflict_review.html",
        help="Static HTML output. Default: %(default)s",
    )
    parser.add_argument(
        "--summary-output",
        default="ml/audit_reports/duplicate_conflict_review_summary.md",
        help="Markdown summary output. Default: %(default)s",
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


def image_src(image_path: str, html_output: Path) -> str:
    source = repo_path(image_path)
    if not source.is_file():
        raise ValueError(f"Review image not found: {image_path}")
    relative = Path(os.path.relpath(source, html_output.parent.resolve()))
    return quote(relative.as_posix(), safe="/")


def contains_core_class(class_names: str) -> bool:
    return bool({name.strip() for name in class_names.split("|")}.intersection(CORE_CLASS_NAMES))


def validate_inputs(data_yaml: Path, review_pack: Path, visual_review: Path) -> None:
    config, errors = load_data_yaml(data_yaml)
    if errors or not class_count_matches_names(config):
        raise ValueError("data.yaml could not be validated for duplicate review")
    if not CORE_CLASS_NAMES.issubset({str(name) for name in config["names"]}):
        raise ValueError("data.yaml is missing a required core class")
    for path, label in ((review_pack, "review pack"), (visual_review, "visual review")):
        if not path.exists():
            raise ValueError(f"Duplicate {label} not found: {display_path(path)}")


def row_html(row: dict[str, str], html_output: Path) -> str:
    core = "yes" if contains_core_class(row["class_names"]) else "no"
    details = [
        ("image_path", row["image_path"], True),
        ("label_path", row["label_path"], True),
        ("class_names", row["class_names"], False),
        ("duplicate_group_id", row["duplicate_group_id"], True),
        ("hash_group_id", row["label_fingerprint"], True),
        ("current_decision", row["approved_action"], True),
        ("recommended_action", row["recommended_action"], True),
        ("conflict_reason", row["notes"] or "(not recorded)", False),
        ("involves_six_class_core", core, True),
    ]
    rendered_details = []
    for label, value, code in details:
        escaped = html.escape(value)
        rendered_details.append(
            f"<dt>{html.escape(label)}</dt><dd>{f'<code>{escaped}</code>' if code else escaped}</dd>"
        )
    source = image_src(row["image_path"], html_output)
    return "\n".join(
        [
            '<article class="review-card">',
            f'  <img loading="lazy" src="{html.escape(source, quote=True)}" '
            f'alt="Duplicate conflict: {html.escape(row["image_path"], quote=True)}">',
            "  <dl>",
            *[f"    {detail}" for detail in rendered_details],
            "  </dl>",
            "</article>",
        ]
    )


def write_html(path: Path, groups: dict[str, list[dict[str, str]]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    sections = []
    for group_id, rows in sorted(groups.items()):
        cards = [row_html(row, path) for row in rows]
        sections.append(
            "\n".join(
                [
                    '<section class="conflict-group">',
                    f"  <h2>{html.escape(group_id)} <span>{len(rows)} unresolved rows</span></h2>",
                    '  <div class="cards">',
                    *cards,
                    "  </div>",
                    "</section>",
                ]
            )
        )
    document = f"""<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Duplicate Conflict Review</title>
  <style>
    :root {{ color: #1c252b; background: #f4f6f7; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }}
    body {{ margin: 0 auto; max-width: 1380px; padding: 28px; }}
    h1, h2, p {{ margin-top: 0; }} p, dd {{ line-height: 1.45; }}
    .notice {{ background: #fff3cd; border: 1px solid #d5a520; border-radius: 8px; padding: 14px; }}
    .conflict-group {{ border-top: 4px solid #ba3a32; margin: 30px 0; padding-top: 16px; }}
    h2 span {{ color: #5e6a73; font-size: 1rem; font-weight: 500; }}
    .cards {{ display: grid; gap: 18px; grid-template-columns: repeat(auto-fit, minmax(360px, 1fr)); }}
    .review-card {{ background: #fff; border: 1px solid #d7dce1; border-radius: 8px; padding: 16px; }}
    .review-card img {{ background: #e6eaed; display: block; height: 310px; object-fit: contain; width: 100%; }}
    dl {{ display: grid; gap: 8px 14px; grid-template-columns: 165px minmax(0, 1fr); margin: 16px 0 0; }}
    dt {{ color: #53616a; font-weight: 650; }} dd {{ margin: 0; overflow-wrap: anywhere; }}
    code {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }}
    @media (max-width: 640px) {{ body {{ padding: 16px; }} dl {{ grid-template-columns: 1fr; gap: 3px; }} dt {{ margin-top: 8px; }} }}
  </style>
</head>
<body>
  <h1>Duplicate Conflict Review</h1>
  <p class="notice">This static page is for human curation only. It does not change decisions, labels, source images, or dataset membership. Record any future decision only through the controlled duplicate approval process.</p>
  {' '.join(sections)}
</body>
</html>
"""
    path.write_text(document, encoding="utf-8")


def write_summary(
    path: Path,
    total_rows: int,
    unresolved_rows: list[dict[str, str]],
    groups: dict[str, list[dict[str, str]]],
) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    core_rows = sum(contains_core_class(row["class_names"]) for row in unresolved_rows)
    path.write_text(
        "\n".join(
            [
                "# Duplicate Conflict Review Summary",
                "",
                f"- Total duplicate cleanup decision rows: {total_rows}",
                f"- Unresolved conflict rows: {len(unresolved_rows)}",
                f"- Conflict groups: {', '.join(sorted(groups)) if groups else 'none'}",
                f"- Core-class affected rows: {core_rows}",
                "",
                "## Suggested Human Decision Options",
                "",
                "### `keep`",
                "",
                "Choose this when the image is the clearer sample in its duplicate group, "
                "has the correct category, and has better annotations.",
                "",
                "### `exclude_from_training`",
                "",
                "Choose this when the image is a duplicate, has an incorrect category or "
                "annotation, has poor quality, or a better group member can be retained.",
                "",
                "### `manual_review`",
                "",
                "Choose this when the better sample cannot be determined or a later human "
                "label correction is needed.",
                "",
                "This summary is a review aid only. It does not approve cleanup, remove "
                "source files, or authorize dataset apply.",
                "",
            ]
        ),
        encoding="utf-8",
    )


def main() -> int:
    args = parse_args()
    validate_inputs(
        repo_path(args.data_yaml),
        repo_path(args.review_pack),
        repo_path(args.visual_review),
    )
    decisions = read_csv_rows(repo_path(args.decisions), DECISION_FIELDS)
    unresolved_rows = [
        row for row in decisions if row["approved_action"] in UNRESOLVED_ACTIONS
    ]
    groups: dict[str, list[dict[str, str]]] = defaultdict(list)
    for row in unresolved_rows:
        groups[row["duplicate_group_id"]].append(row)
    html_output = repo_path(args.html_output)
    write_html(html_output, groups)
    write_summary(repo_path(args.summary_output), len(decisions), unresolved_rows, groups)
    print(f"Duplicate decision rows: {len(decisions)}")
    print(f"Unresolved conflict rows: {len(unresolved_rows)}")
    print(f"Conflict groups: {len(groups)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
