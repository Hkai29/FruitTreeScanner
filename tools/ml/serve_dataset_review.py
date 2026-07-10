#!/usr/bin/env python3
"""Serve a local-only, human-operated dataset review interface.

This server never changes images, labels, data.yaml, or dataset membership. It
only updates the approved_action column in a pre-existing decisions CSV after a
human selects an action in the local browser interface.
"""

from __future__ import annotations

import argparse
import csv
import html
import ipaddress
import json
import mimetypes
import os
import shutil
import sys
import tempfile
import threading
from collections import Counter
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse


REPO_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_QUEUE = "ml/audit_reports/manual_review_priority_queue.csv"
DEFAULT_DECISIONS = "ml/audit_reports/manual_review_decisions.csv"
DEFAULT_DATASET_ROOT = "ml/datasets/fruit_dataset_26"
DEFAULT_PROGRESS = "ml/audit_reports/manual_review_progress.md"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
ALLOWED_APPROVED_ACTIONS = {
    "pending_review",
    "keep",
    "exclude_from_training",
    "manual_review",
}
QUEUE_FIELDS = {
    "image_path",
    "class_name",
    "issue_type",
    "vision_signal",
    "risk_level",
    "recommended_action",
    "review_reason",
}
DECISION_FIELDS = {
    "image_path",
    "class_name",
    "issue_type",
    "risk_level",
    "vision_signal",
    "recommended_action",
    "approved_action",
    "notes",
}
MAX_REQUEST_BYTES = 32 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description=(
            "Serve a local human-review tool that updates only the approved_action "
            "column in a decisions CSV."
        )
    )
    parser.add_argument(
        "--queue",
        default=DEFAULT_QUEUE,
        help=f"Priority queue CSV. Default: {DEFAULT_QUEUE}",
    )
    parser.add_argument(
        "--decisions",
        default=DEFAULT_DECISIONS,
        help=f"Decisions CSV to update. Default: {DEFAULT_DECISIONS}",
    )
    parser.add_argument(
        "--dataset-root",
        default=DEFAULT_DATASET_ROOT,
        help=f"Dataset root containing images/. Default: {DEFAULT_DATASET_ROOT}",
    )
    parser.add_argument(
        "--progress-output",
        default=DEFAULT_PROGRESS,
        help=f"Progress Markdown report. Default: {DEFAULT_PROGRESS}",
    )
    parser.add_argument(
        "--host",
        default=DEFAULT_HOST,
        help="Loopback host only. Default: 127.0.0.1",
    )
    parser.add_argument(
        "--port",
        type=int,
        default=DEFAULT_PORT,
        help=f"TCP port. Default: {DEFAULT_PORT}",
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


def require_loopback_host(host: str) -> None:
    if host == "localhost":
        return
    try:
        if not ipaddress.ip_address(host).is_loopback:
            raise ValueError
    except ValueError as error:
        raise ValueError("--host must be a loopback address such as 127.0.0.1") from error


def read_csv(path: Path, required_fields: set[str]) -> tuple[list[str], list[dict[str, str]]]:
    if not path.is_file():
        raise ValueError(f"CSV not found: {display_path(path)}")
    with path.open(newline="", encoding="utf-8") as handle:
        reader = csv.DictReader(handle)
        fieldnames = reader.fieldnames or []
        missing = sorted(required_fields - set(fieldnames))
        if missing:
            raise ValueError(
                f"CSV missing columns ({', '.join(missing)}): {display_path(path)}"
            )
        rows = [{key: (value or "").strip() for key, value in row.items()} for row in reader]
    return fieldnames, rows


class ReviewStore:
    """Owns validated review records and serializes decision CSV updates."""

    def __init__(
        self,
        queue_path: Path,
        decisions_path: Path,
        dataset_root: Path,
        progress_path: Path,
    ) -> None:
        self.queue_path = queue_path
        self.decisions_path = decisions_path
        self.dataset_root = dataset_root.resolve()
        self.progress_path = progress_path
        self.lock = threading.RLock()

        if not self.dataset_root.is_dir():
            raise ValueError(f"Dataset root not found: {display_path(dataset_root)}")
        if not (self.dataset_root / "images").is_dir():
            raise ValueError(
                f"Dataset root has no images/ directory: {display_path(dataset_root)}"
            )

        _, queue_rows = read_csv(queue_path, QUEUE_FIELDS)
        self.decision_fieldnames, self.decision_rows = read_csv(
            decisions_path, DECISION_FIELDS
        )
        if not queue_rows:
            raise ValueError(f"Priority queue is empty: {display_path(queue_path)}")

        decisions_by_path: dict[str, dict[str, str]] = {}
        for row in self.decision_rows:
            image_path = row["image_path"]
            if not image_path:
                raise ValueError(f"Decisions CSV has an empty image_path: {display_path(decisions_path)}")
            if image_path in decisions_by_path:
                raise ValueError(f"Decisions CSV repeats image_path: {image_path}")
            action = row["approved_action"]
            if action not in ALLOWED_APPROVED_ACTIONS:
                allowed = ", ".join(sorted(ALLOWED_APPROVED_ACTIONS))
                raise ValueError(
                    f"Unsupported approved_action {action!r} for {image_path}; allowed: {allowed}"
                )
            decisions_by_path[image_path] = row

        queue_paths: set[str] = set()
        self.items: list[dict[str, Any]] = []
        for index, row in enumerate(queue_rows):
            image_path = row["image_path"]
            if not image_path:
                raise ValueError(f"Priority queue has an empty image_path: {display_path(queue_path)}")
            if image_path in queue_paths:
                raise ValueError(f"Priority queue repeats image_path: {image_path}")
            queue_paths.add(image_path)
            decision_row = decisions_by_path.get(image_path)
            if decision_row is None:
                raise ValueError(f"Queue image has no decision row: {image_path}")
            image_file = repo_path(image_path)
            try:
                image_file.relative_to(self.dataset_root)
            except ValueError as error:
                raise ValueError(
                    f"Queue image is outside --dataset-root: {image_path}"
                ) from error
            if not image_file.is_file():
                raise ValueError(f"Queue image not found: {image_path}")
            self.items.append(
                {
                    "id": index,
                    "image_path": image_path,
                    "image_file": image_file,
                    "class_name": row["class_name"],
                    "issue_type": row["issue_type"],
                    "vision_signal": row["vision_signal"],
                    "risk_level": row["risk_level"],
                    "recommended_action": row["recommended_action"],
                    "review_reason": row["review_reason"],
                    "decision_row": decision_row,
                }
            )

        extra_paths = set(decisions_by_path) - queue_paths
        if extra_paths:
            sample = ", ".join(sorted(extra_paths)[:3])
            raise ValueError(f"Decisions CSV contains rows outside the queue: {sample}")
        self.write_progress()

    def public_items(self) -> list[dict[str, Any]]:
        with self.lock:
            return [
                {
                    "id": item["id"],
                    "image_path": item["image_path"],
                    "class_name": item["class_name"],
                    "issue_type": item["issue_type"],
                    "vision_signal": item["vision_signal"],
                    "risk_level": item["risk_level"],
                    "recommended_action": item["recommended_action"],
                    "review_reason": item["review_reason"],
                    "approved_action": item["decision_row"]["approved_action"],
                }
                for item in self.items
            ]

    def progress(self) -> dict[str, Any]:
        with self.lock:
            actions = Counter(item["decision_row"]["approved_action"] for item in self.items)
            high_pending = sum(
                item["risk_level"] == "high"
                and item["decision_row"]["approved_action"] == "pending_review"
                for item in self.items
            )
            total = len(self.items)
            pending = actions["pending_review"]
            return {
                "total": total,
                "reviewed": total - pending,
                "pending": pending,
                "keep": actions["keep"],
                "exclude_from_training": actions["exclude_from_training"],
                "manual_review": actions["manual_review"],
                "high_risk_pending": high_pending,
                "training_blocked": pending > 0,
            }

    def image_for_id(self, item_id: int) -> Path:
        with self.lock:
            if item_id < 0 or item_id >= len(self.items):
                raise ValueError(f"Unknown review item id: {item_id}")
            return self.items[item_id]["image_file"]

    def apply_action(self, item_id: int, action: str) -> dict[str, Any]:
        if action not in ALLOWED_APPROVED_ACTIONS:
            allowed = ", ".join(sorted(ALLOWED_APPROVED_ACTIONS))
            raise ValueError(f"Unsupported action {action!r}; allowed: {allowed}")
        if action == "pending_review":
            raise ValueError("The UI cannot reset an item to pending_review")
        with self.lock:
            if item_id < 0 or item_id >= len(self.items):
                raise ValueError(f"Unknown review item id: {item_id}")
            item = self.items[item_id]
            if item["decision_row"]["approved_action"] != action:
                self._backup_decisions()
                item["decision_row"]["approved_action"] = action
                self._write_decisions()
                self.write_progress()
            return self.progress()

    def _backup_decisions(self) -> None:
        base = self.decisions_path.with_name(f"{self.decisions_path.name}.bak")
        backup = base
        if backup.exists():
            suffix = datetime.now().strftime("%Y%m%d-%H%M%S")
            backup = self.decisions_path.with_name(f"{self.decisions_path.name}.{suffix}.bak")
            sequence = 1
            while backup.exists():
                backup = self.decisions_path.with_name(
                    f"{self.decisions_path.name}.{suffix}-{sequence}.bak"
                )
                sequence += 1
        shutil.copy2(self.decisions_path, backup)

    def _write_decisions(self) -> None:
        temporary_path: Path | None = None
        try:
            with tempfile.NamedTemporaryFile(
                "w",
                newline="",
                encoding="utf-8",
                dir=self.decisions_path.parent,
                prefix=f".{self.decisions_path.name}.",
                suffix=".tmp",
                delete=False,
            ) as handle:
                temporary_path = Path(handle.name)
                writer = csv.DictWriter(
                    handle,
                    fieldnames=self.decision_fieldnames,
                    lineterminator="\n",
                )
                writer.writeheader()
                writer.writerows(self.decision_rows)
            os.replace(temporary_path, self.decisions_path)
        except OSError as error:
            if temporary_path is not None and temporary_path.exists():
                temporary_path.unlink()
            raise ValueError(f"Could not save decisions CSV: {error}") from error

    def write_progress(self) -> None:
        progress = self.progress()
        blocked = "yes" if progress["training_blocked"] else "no"
        lines = [
            "# Manual Review Progress",
            "",
            f"- Total rows: {progress['total']}",
            f"- Pending rows: {progress['pending']}",
            f"- Keep rows: {progress['keep']}",
            f"- Exclude from training rows: {progress['exclude_from_training']}",
            f"- Manual review rows: {progress['manual_review']}",
            f"- High-risk pending rows: {progress['high_risk_pending']}",
            f"- Training blocked: {blocked}",
            "",
            "This report reflects human-selected CSV actions only. It does not approve "
            "dataset changes, apply cleanup, or start training.",
            "",
        ]
        self.progress_path.parent.mkdir(parents=True, exist_ok=True)
        self.progress_path.write_text("\n".join(lines), encoding="utf-8")


PAGE = """<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <title>Dataset Review Tool</title>
  <style>
    :root { color: #20282e; background: #f4f6f7; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", sans-serif; }
    body { margin: 0 auto; max-width: 1200px; padding: 24px; }
    h1, h2, p { margin-top: 0; }
    .notice { background: #fff3cd; border: 1px solid #d5a520; border-radius: 8px; line-height: 1.45; padding: 14px; }
    .toolbar, .actions, .summary { display: flex; flex-wrap: wrap; gap: 10px; }
    .toolbar { align-items: end; margin: 20px 0; }
    label { display: grid; gap: 4px; font-weight: 650; }
    select, button { border: 1px solid #aeb8bf; border-radius: 6px; font: inherit; padding: 9px 12px; }
    button { background: #fff; cursor: pointer; font-weight: 650; }
    button:hover { background: #eef2f4; }
    button.exclude { background: #ba3a32; border-color: #ba3a32; color: #fff; }
    button.keep { background: #397b59; border-color: #397b59; color: #fff; }
    button.manual { background: #ad7a16; border-color: #ad7a16; color: #fff; }
    .summary { margin: 16px 0; }
    .summary div { background: #fff; border: 1px solid #d7dce1; border-radius: 8px; min-width: 112px; padding: 10px; }
    .summary strong { display: block; font-size: 1.35rem; }
    .card { align-items: start; background: #fff; border: 1px solid #d7dce1; border-radius: 8px; display: grid; gap: 22px; grid-template-columns: minmax(250px, 48%) 1fr; padding: 18px; }
    .card img { background: #e6eaed; display: block; height: min(58vh, 620px); object-fit: contain; width: 100%; }
    dl { display: grid; gap: 8px 16px; grid-template-columns: 155px minmax(0, 1fr); margin: 0; }
    dt { color: #53616a; font-weight: 700; }
    dd { line-height: 1.45; margin: 0; overflow-wrap: anywhere; }
    code { font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .88em; }
    .status { color: #53616a; margin: 12px 0; min-height: 1.4em; }
    .empty { background: #fff; border: 1px solid #d7dce1; border-radius: 8px; padding: 20px; }
    @media (max-width: 760px) { body { padding: 14px; } .card { grid-template-columns: 1fr; } dl { grid-template-columns: 1fr; gap: 3px; } dt { margin-top: 8px; } }
  </style>
</head>
<body>
  <h1>Dataset Review Tool</h1>
  <p class="notice">Human decisions only. Images may contain unsuitable or incorrectly labelled content. This tool updates only <code>approved_action</code> in the decisions CSV and creates a CSV backup before each saved action.</p>
  <section class="summary" aria-label="Review progress">
    <div><strong id="total">0</strong>total</div>
    <div><strong id="reviewed">0</strong>reviewed</div>
    <div><strong id="pending">0</strong>pending</div>
    <div><strong id="exclude">0</strong>exclude</div>
    <div><strong id="keep">0</strong>keep</div>
    <div><strong id="manual">0</strong>manual review</div>
  </section>
  <section class="toolbar" aria-label="Review filters">
    <label>Risk level
      <select id="risk-filter">
        <option value="all">All risks</option>
        <option value="high" selected>High risk</option>
        <option value="medium">Medium risk</option>
        <option value="low">Low risk</option>
      </select>
    </label>
    <label><span>Pending only</span><input id="pending-filter" type="checkbox" checked></label>
    <button id="previous" type="button">Previous</button>
    <button id="next" type="button">Next pending</button>
  </section>
  <p class="status" id="status" role="status"></p>
  <main id="review"></main>
  <script>
    let payload = null;
    let position = 0;
    const riskFilter = document.getElementById('risk-filter');
    const pendingFilter = document.getElementById('pending-filter');
    const review = document.getElementById('review');
    const status = document.getElementById('status');

    function filteredItems() {
      if (!payload) return [];
      return payload.items.filter(item =>
        (riskFilter.value === 'all' || item.risk_level === riskFilter.value) &&
        (!pendingFilter.checked || item.approved_action === 'pending_review')
      );
    }

    function updateSummary(progress) {
      document.getElementById('total').textContent = progress.total;
      document.getElementById('reviewed').textContent = progress.reviewed;
      document.getElementById('pending').textContent = progress.pending;
      document.getElementById('exclude').textContent = progress.exclude_from_training;
      document.getElementById('keep').textContent = progress.keep;
      document.getElementById('manual').textContent = progress.manual_review;
    }

    function render() {
      const items = filteredItems();
      if (!items.length) {
        review.innerHTML = '<section class="empty"><h2>No matching review items</h2><p>Adjust filters or continue the next pending category.</p></section>';
        status.textContent = 'No matching items.';
        return;
      }
      position = Math.max(0, Math.min(position, items.length - 1));
      const item = items[position];
      status.textContent = `Item ${position + 1} of ${items.length}. Current action: ${item.approved_action}.`;
      review.innerHTML = `
        <section class="card">
          <img src="/api/image/${item.id}" alt="Review candidate ${escapeHtml(item.image_path)}">
          <div>
            <dl>
              <dt>image_path</dt><dd><code>${escapeHtml(item.image_path)}</code></dd>
              <dt>class_name</dt><dd>${escapeHtml(item.class_name)}</dd>
              <dt>issue_type</dt><dd><code>${escapeHtml(item.issue_type)}</code></dd>
              <dt>vision_signal</dt><dd><code>${escapeHtml(item.vision_signal)}</code></dd>
              <dt>risk_level</dt><dd>${escapeHtml(item.risk_level)}</dd>
              <dt>recommended_action</dt><dd><code>${escapeHtml(item.recommended_action)}</code></dd>
              <dt>review_reason</dt><dd>${escapeHtml(item.review_reason)}</dd>
              <dt>approved_action</dt><dd><strong>${escapeHtml(item.approved_action)}</strong></dd>
            </dl>
            <div class="actions" style="margin-top:18px">
              <button class="keep" data-action="keep">Keep (K)</button>
              <button class="exclude" data-action="exclude_from_training">Exclude from training (E)</button>
              <button class="manual" data-action="manual_review">Manual review (M)</button>
              <button data-action="skip">Skip (S)</button>
            </div>
          </div>
        </section>`;
      review.querySelectorAll('[data-action]').forEach(button => {
        button.addEventListener('click', () => takeAction(item, button.dataset.action));
      });
    }

    function escapeHtml(value) {
      const element = document.createElement('span');
      element.textContent = value || '';
      return element.innerHTML;
    }

    async function takeAction(item, action) {
      if (action === 'skip') {
        position += 1;
        render();
        return;
      }
      try {
        const response = await fetch('/api/action', {
          method: 'POST',
          headers: {'Content-Type': 'application/json'},
          body: JSON.stringify({id: item.id, action})
        });
        const result = await response.json();
        if (!response.ok) throw new Error(result.error || 'Save failed');
        payload.items.find(candidate => candidate.id === item.id).approved_action = action;
        payload.progress = result.progress;
        updateSummary(payload.progress);
        render();
      } catch (error) {
        status.textContent = `Save error: ${error.message}`;
      }
    }

    function move(delta) {
      position += delta;
      render();
    }

    document.getElementById('previous').addEventListener('click', () => move(-1));
    function nextPending() {
      const current = filteredItems()[position];
      pendingFilter.checked = true;
      const pendingItems = filteredItems();
      const nextIndex = current
        ? pendingItems.findIndex(candidate => candidate.id > current.id)
        : 0;
      position = nextIndex >= 0 ? nextIndex : 0;
      render();
    }

    document.getElementById('next').addEventListener('click', nextPending);
    riskFilter.addEventListener('change', () => { position = 0; render(); });
    pendingFilter.addEventListener('change', () => { position = 0; render(); });
    document.addEventListener('keydown', event => {
      if (event.metaKey || event.ctrlKey || event.altKey) return;
      const key = event.key.toLowerCase();
      const items = filteredItems();
      const item = items[position];
      if (!item && key !== 'p' && key !== 'n') return;
      if (key === 'k') takeAction(item, 'keep');
      if (key === 'e') takeAction(item, 'exclude_from_training');
      if (key === 'm') takeAction(item, 'manual_review');
      if (key === 's') takeAction(item, 'skip');
      if (key === 'n') nextPending();
      if (key === 'p') move(-1);
    });

    fetch('/api/items')
      .then(response => response.json().then(body => ({response, body})))
      .then(({response, body}) => {
        if (!response.ok) throw new Error(body.error || 'Could not load review queue');
        payload = body;
        updateSummary(payload.progress);
        render();
      })
      .catch(error => { status.textContent = `Load error: ${error.message}`; });
  </script>
</body>
</html>
"""


class ReviewHTTPServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], store: ReviewStore) -> None:
        super().__init__(address, ReviewRequestHandler)
        self.store = store


class ReviewRequestHandler(BaseHTTPRequestHandler):
    server: ReviewHTTPServer

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path == "/":
            self._send_bytes(HTTPStatus.OK, PAGE.encode("utf-8"), "text/html; charset=utf-8")
            return
        if parsed.path == "/api/items":
            self._send_json(
                HTTPStatus.OK,
                {
                    "items": self.server.store.public_items(),
                    "progress": self.server.store.progress(),
                },
            )
            return
        if parsed.path == "/api/progress":
            self._send_json(HTTPStatus.OK, self.server.store.progress())
            return
        if parsed.path.startswith("/api/image/"):
            self._send_image(parsed.path)
            return
        self._send_error_json(HTTPStatus.NOT_FOUND, "Unknown route")

    def do_POST(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        if parsed.path != "/api/action":
            self._send_error_json(HTTPStatus.NOT_FOUND, "Unknown route")
            return
        try:
            content_length = int(self.headers.get("Content-Length", "0"))
            if content_length <= 0 or content_length > MAX_REQUEST_BYTES:
                raise ValueError("Request body is missing or too large")
            payload = json.loads(self.rfile.read(content_length).decode("utf-8"))
            if not isinstance(payload, dict):
                raise ValueError("Request body must be a JSON object")
            item_id = payload.get("id")
            action = payload.get("action")
            if isinstance(item_id, bool) or not isinstance(item_id, int):
                raise ValueError("id must be an integer")
            if not isinstance(action, str):
                raise ValueError("action must be a string")
            progress = self.server.store.apply_action(item_id, action)
            self._send_json(HTTPStatus.OK, {"progress": progress})
        except (UnicodeDecodeError, json.JSONDecodeError, ValueError) as error:
            self._send_error_json(HTTPStatus.BAD_REQUEST, str(error))

    def _send_image(self, path: str) -> None:
        try:
            item_id = int(path.rsplit("/", maxsplit=1)[-1])
            image_path = self.server.store.image_for_id(item_id)
            content_type = mimetypes.guess_type(image_path.name)[0] or "application/octet-stream"
            self._send_file(HTTPStatus.OK, image_path, content_type)
        except (OSError, ValueError) as error:
            self._send_error_json(HTTPStatus.NOT_FOUND, str(error))

    def _send_json(self, status: HTTPStatus, payload: dict[str, Any]) -> None:
        self._send_bytes(
            status,
            json.dumps(payload, ensure_ascii=False).encode("utf-8"),
            "application/json; charset=utf-8",
        )

    def _send_error_json(self, status: HTTPStatus, message: str) -> None:
        self._send_json(status, {"error": message})

    def _send_bytes(self, status: HTTPStatus, data: bytes, content_type: str) -> None:
        self.send_response(status.value)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def _send_file(self, status: HTTPStatus, path: Path, content_type: str) -> None:
        self.send_response(status.value)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(path.stat().st_size))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        with path.open("rb") as handle:
            shutil.copyfileobj(handle, self.wfile)

    def log_message(self, format: str, *args: object) -> None:
        sys.stderr.write(f"{self.address_string()} - {format % args}\n")


def main() -> int:
    args = parse_args()
    try:
        require_loopback_host(args.host)
        if not 1 <= args.port <= 65535:
            raise ValueError("--port must be between 1 and 65535")
        store = ReviewStore(
            repo_path(args.queue),
            repo_path(args.decisions),
            repo_path(args.dataset_root),
            repo_path(args.progress_output),
        )
        server = ReviewHTTPServer((args.host, args.port), store)
    except (OSError, ValueError) as error:
        print(f"Dataset review server error: {error}", file=sys.stderr)
        return 2

    address = f"http://{args.host}:{args.port}"
    print(f"Dataset review tool serving at {address}")
    print("Press Ctrl-C to stop. Review decisions are saved only after a button action.")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nStopping dataset review tool.")
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
