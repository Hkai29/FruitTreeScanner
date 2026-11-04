# Tools

Helper scripts are grouped by purpose:

```text
ml/       Dataset remapping, YOLO training/export, and point-cloud analysis
paper/    Markdown/Word paper generation utilities
legacy/   One-off historical migration scripts kept for reference
```

These tools are not part of the iOS app target. Prefer running them from the repository root so repo-relative paths resolve cleanly.

## Code improvement workflow

Run `python3 tools/code_improvement_workflow.py preflight` to record the current
working-tree baseline, then choose `fusion`, `storage`, `lifecycle`, `ui`, or
`full` for the changed behavior. Risk profiles can be combined. `quick` checks
Domain and Debug compilation; `full` runs all XCTest and a Release simulator
build. `--dry-run` prints commands without executing or creating output.

The runner uses Python 3 (standard library only), command-scoped Xcode settings,
and unique logs, patches, result bundles and a JSON report outside the checkout.
A passing test gate requires a successful process and nonempty XCTest results
with no failures or skips. Workspace changes invalidate a passing run. Code
review and relevant UI/device acceptance remain separate.

See the Chinese [iteration procedure and agent prompt](../docs/implementation/CODE_IMPROVEMENT_WORKFLOW.md).

Test the runner's failure handling without Xcode:
`PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests -v`.

## XCTest gate (CI and local share one judgement)

`tools/xctest_gate.py` is the single place that decides whether an XCTest
result bundle may pass. `tools/code_improvement_workflow.py` (local profiles)
and `tools/ci_xctest_gate.sh` (CI) both call it, so there is no second,
looser standard.

A bundle passes only when all of the following hold:

- the summary's counters are present and are non-negative integers (a `bool`
  is not an integer), `result == "Passed"`, `passedTests > 0`, and
  `totalTestCount == passedTests`;
- `failedTests`, `skippedTests` and `expectedFailures` are all `0` — **no
  skip whitelist exists**; a skipped test is an unverified test;
- `runtimeWarnings` is present and readable, and no warning matches
  `Publishing changes from within view updates is not allowed` (that one is
  blocking, because it means state published during a view update);
- the result tree contains a real passing case for **every declared XCTest
  class**, in the `FruitTreeScannerTests` bundle;
- the summary and the tree agree on how many tests passed;
- a payload containing multiple test runs is rejected outright.

Non-blocking warnings (for example the QoS priority-inversion diagnostics)
are printed and kept for review rather than swallowed.

Run it directly:

```sh
python3 tools/xctest_gate.py <path/to/tests.xcresult>
```

The gate's own regression matrix lives in `tools/tests/test_xctest_gate.py`
and runs with the rest of the tool tests:

```sh
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s tools/tests
```

## Domain dependency check

Run `bash tools/validate_fusion_domain.sh` from any directory to compile the
entire `FruitTreeScanner/Domain` tree as a separate iOS 16 simulator module in
Swift 5 mode. It discovers every Swift source recursively, preferring `rg` and
falling back to the system `find`, including new and hidden subdirectories.
Results, mass and diagnostic values, evidence identities, plans, lifecycle,
observations, configuration and fusion all participate.
App/Core sources, settings capture/stores, display labels, legacy detection
adapters and pixel buffers are excluded. Temporary module output is removed
after the check. This script requires the configured local Xcode.

This checks Domain source independence. The app still uses its existing target;
the check does not create a production framework or package. Compiling
ScanSession does not prove thread safety. This does not run tests or validate
physical LiDAR quality. Set `DEVELOPER_DIR` for a different local Xcode.

## CI simulator compilation

The iOS Build workflow runs the Domain gate before simulator compilation for
matching pushes to `main`, pull requests targeting `main`, or manual runs. Both
tool scripts are included in the workflow's path filters. The workflow uses the
runner's selected Xcode through job environment; it does not change system
selection. Failure to select Xcode stops the workflow before compilation.

Run `DEVELOPER_DIR=/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer bash tools/ci_simulator_build.sh`
locally to use the project Xcode. Set `FTS_CI_BUILD_DIR` for a dedicated output
directory; by default it uses runner/system temporary storage. The script keeps
the compiler log, propagates its actual exit status, and writes a bounded error
and warning summary when GitHub's reporting paths are present. A compilation
failure remains a failure even if report writing also fails. Report writing
failure also returns a nonzero status after successful compilation.

Both CI Bash entrypoints use `ci_evidence.py` to create a new attempt directory
under `FTS_CI_EVIDENCE_DIR` (default: `<build-directory>/evidence`). Existing
attempts are never deleted or reused. Each attempt retains the full compiler or
XCTest log, command arguments and actual exits, selected Xcode/SDK versions,
and a final `report.json`. XCTest attempts also retain the real `tests.xcresult`
and independently export raw `summary.json` / `tree.json`, including each
export's stderr and status even after a failed test build. A missing result or
unavailable summary is recorded explicitly; it is never replaced with a passing
payload. The shared XCTest gate still decides acceptance. An original compiler
failure remains authoritative; missing required evidence after success fails CI.

The workflow always uploads only its dedicated evidence directory, with a unique
run/attempt artifact name and no overwrite. DerivedData and unsigned App products
remain in separate work directories and are not uploaded. This also preserves
the preceding simulator compilation log if XCTest never starts. The artifact
contains CI test fixtures and diagnostics; it is not a device acceptance report.

This builds an unsigned simulator app. It does not execute XCTest, produce a
signed IPA, or verify physical LiDAR quality.
