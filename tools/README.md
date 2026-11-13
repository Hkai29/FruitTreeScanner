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
and CI's final verification both call it, so there is no second, looser
standard. Standalone `tools/ci_xctest_gate.sh` runs it directly by default.

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

The XCTest default destination is selected numerically from the retained device
inventory, at or below the compiling Xcode's simulator SDK. `selection.json`
records the selected runtime and reason; `FTS_CI_TEST_DESTINATION` preserves an
explicit caller override. The Chinese golden baseline uses `-testLanguage
zh-Hans`, while existing independent English/Chinese localization tests remain.
`FTS_XCRESULT_DEVELOPER_DIR` optionally selects an official result-reader Xcode
only for result inspection and exports. Without it, the CI test entrypoint
probes installed Xcode candidates using the official summary schema and keeps
the probe output and reason in `reader-selection.json` and `reader-probes/`.
The compiling `DEVELOPER_DIR` and SDK stay unchanged. Missing warning fields
fail the shared gate; an explicitly configured unsupported reader is rejected.

CI separates execution from strict verification when the compatibility runner
has no reader exposing the required warning schema. The `build` job executes
the complete tests on `macos-15`, retains the original bundle and exports, and
marks `strict_gate_pending: true`. Its explicit handoff mode requires GitHub
run/attempt/SHA identities and the mandatory `verify` consumer. It does not
claim strict acceptance. The dependent `verify` job runs on the standard
`xcode-27` runner and displays the required check name `build`; the producer
displays `Execute compatibility XCTest`.

`ci_verify_xctest_artifact.py` downloads no external data itself. It checks the
same attempt's digest-verified artifact against the checkout SHA, rejects
missing or filtered execution evidence, compares original and fresh counters,
then calls the unchanged shared gate with a schema-capable reader. Both jobs
must pass. The original artifact is hashed before and after reading; separate
verification logs are always uploaded. Missing warnings, failed tests, skipped
tests, missing classes or unreadable evidence remain hard failures. Runner
availability alone is not proof of reader capability. The workflow wiring
regressions enforce this dependency and bind the old required check name to
strict verification.

The CI build records and hands off the actual unsigned simulator App. Before
the test host first launches, CI installs that App on the selected simulator,
grants its WhenInUse location fixture, and sets and reads back three AX inspection
preferences. `ui-host/report.json` retains the scope, App identity and command
evidence. A standalone run without an explicit host App path leaves simulator
preferences alone; explicit local setup also requires `FTS_CI_OWNED_SIMULATOR_ID`
to match the selected UUID.

The workflow always uploads only its dedicated evidence directory, with a unique
run/attempt artifact name and no overwrite. DerivedData and unsigned App products
remain in separate work directories and are not uploaded. This also preserves
the preceding simulator compilation log if XCTest never starts. The artifact
contains CI test fixtures and diagnostics; it is not a device acceptance report.

The simulator-build entrypoint builds an unsigned simulator app; the XCTest
entrypoint executes the tests. Neither produces a signed IPA or verifies
physical LiDAR quality.
