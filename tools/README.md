# Tools

Helper scripts are grouped by purpose:

```text
ml/       Dataset remapping, YOLO training/export, and point-cloud analysis
paper/    Markdown/Word paper generation utilities
legacy/   One-off historical migration scripts kept for reference
```

These tools are not part of the iOS app target. Prefer running them from the repository root so repo-relative paths resolve cleanly.

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

This builds an unsigned simulator app. It does not execute XCTest, produce a
signed IPA, or verify physical LiDAR quality.
