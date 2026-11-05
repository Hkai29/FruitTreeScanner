#!/bin/bash
set -euo pipefail

task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_build_root="${FTS_CI_BUILD_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/FruitTreeScanner-ci-build}"
mkdir -p "$task_build_root"
task_evidence_tool="$task_repo_root/tools/ci_evidence.py"
task_evidence_root="${FTS_CI_EVIDENCE_DIR:-$task_build_root/evidence}"
task_run_root="$(python3 "$task_evidence_tool" prepare --root "$task_evidence_root" \
  --build-root "$task_build_root" --repo "$task_repo_root" --phase build)"
task_build_log="$task_run_root/simulator-build.log"
finish_ci_evidence() {
  task_primary_status=$?
  trap - EXIT
  set +e
  python3 "$task_evidence_tool" finish "$task_run_root" --status "$task_primary_status"
  task_evidence_status=$?
  if (( task_primary_status != 0 )); then exit "$task_primary_status"; fi
  exit "$task_evidence_status"
}
trap finish_ci_evidence EXIT
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  DEVELOPER_DIR="$(xcode-select -p)"
fi
export DEVELOPER_DIR
python3 "$task_evidence_tool" toolchain "$task_run_root"
task_work_root="$(mktemp -d "$task_build_root/work.XXXXXX")"

# A conditional preserves the compiler's status even under bash -e -o pipefail.
if python3 "$task_evidence_tool" run --name simulator-build --log simulator-build.log "$task_run_root" -- xcodebuild -quiet \
  -project "$task_repo_root/FruitTreeScanner.xcodeproj" \
  -scheme FruitTreeScanner \
  -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath "$task_work_root/DerivedData" \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  build; then
  task_build_status=0
else
  task_build_status=$?
fi

task_report_status=0
if [[ -n "${GITHUB_ENV:-}" ]]; then
  if ! printf 'EXIT_CODE=%s\n' "$task_build_status" >> "$GITHUB_ENV"; then
    task_report_status=1
  fi
fi
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  if {
    printf '### Simulator compilation\n\nExit code: %s\n\n' "$task_build_status" &&
    printf 'This checks compilation. XCTest execution, physical LiDAR and signed IPA packaging need separate evidence.\n\n' &&
    printf 'Compiler errors (first 30):\n\n```text\n' &&
    awk '/error:/ { if (count++ < 30) print } END { if (!count) print "No compiler error lines; the exit code above is authoritative." }' "$task_build_log" &&
    printf '```\n\nWarnings (first 10):\n\n```text\n' &&
    awk '/warning:/ { if (count++ < 10) print }' "$task_build_log" &&
    printf '```\n'
  } >> "$GITHUB_STEP_SUMMARY"; then
    :
  else
    task_report_status=1
  fi
fi

printf 'Simulator compilation exit %s. Full log: %s\n' "$task_build_status" "$task_build_log"
if (( task_build_status != 0 )); then
  tail -n 80 "$task_build_log" || true
  exit "$task_build_status"
fi
# A successful compiler run must also report failures writing CI evidence.
if (( task_report_status != 0 )); then exit "$task_report_status"; fi
task_host_app="$task_work_root/DerivedData/Build/Products/Debug-iphonesimulator/FruitTreeScanner.app"
python3 "$task_evidence_tool" run --name publish-host-app --log publish-host-app.log "$task_run_root" -- \
  python3 "$task_repo_root/tools/ci_ui_host_setup.py" publish --app "$task_host_app" \
    --receipt "$task_run_root/host-app.json" --github-env "${GITHUB_ENV:-}"
