# Interactive Dataset Review Tool

`tools/ml/serve_dataset_review.py` is a local-only, human-operated review
server for the first-round semantic image queue. It does not change source
images, labels, `data.yaml`, model files, or App code.

## Start the Tool

Run from the repository root:

```sh
python3 tools/ml/serve_dataset_review.py \
  --queue ml/audit_reports/manual_review_priority_queue.csv \
  --decisions ml/audit_reports/manual_review_decisions.csv \
  --dataset-root ml/datasets/fruit_dataset_26 \
  --host 127.0.0.1 \
  --port 8765
```

Open `http://127.0.0.1:8765` in a local browser. The server rejects non-loopback
hosts. It validates queue paths, decision rows, required columns, and allowed
approval values before serving the page.

## Review Actions

- `Keep` (`K`): the image is a valid example for its current labels.
- `Exclude from training` (`E`): the image should be omitted from a future
  reviewed training copy. This does not delete or move the source image.
- `Manual review` (`M`): the image needs follow-up because content, provenance,
  or labels remain uncertain.
- `Skip` (`S`): leave the item as `pending_review` and advance without writing.
- `Previous` (`P`) and `Next pending` (`N`): navigate within the current filter.

The tool accepts only `pending_review`, `keep`, `exclude_from_training`, and
`manual_review` as `approved_action` values. It never derives a decision from
Vision output or the suggested action.

## Saving and Resuming

Each decision writes only the `approved_action` column in
`ml/audit_reports/manual_review_decisions.csv`. Before a changed action is
saved, the tool creates `manual_review_decisions.csv.bak`; later saves use a
timestamped backup if that name already exists. Existing actions are loaded at
startup, so closing and restarting the server continues the previous review.

The tool also writes `ml/audit_reports/manual_review_progress.md` with totals,
pending and resolved actions, high-risk pending count, and the conservative
training-blocked state.

## Training Gate

Finish the high-risk review and record explicit human actions before proposing
any dataset cleanup or training task. A completed CSV is an approval record
only; cleanup, creation of a reviewed dataset copy, and model training still
require separate explicit tasks and review.
