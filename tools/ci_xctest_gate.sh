#!/bin/bash
# FruitTreeScanner · CI 门禁：跑完整 XCTest，并按共享判定放行
#
# 用法：bash tools/ci_xctest_gate.sh
#
# 门禁规则只有一份：tools/xctest_gate.py（与本地全量关卡 code_improvement_workflow.py
# 共用同一份判定）。本脚本只负责「跑」和「把退出码传出去」：
#   - xcodebuild 的失败原样传出，不重试、不放行；
#   - 结果包缺失、读不出来、判定不过 → 同样非零退出；
#   - 零跳过、阻塞级 SwiftUI 警告、声明的测试类没有真实通过用例 → 判定不过。
set -euo pipefail

task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_build_root="${FTS_CI_BUILD_DIR:-${RUNNER_TEMP:-${TMPDIR:-/tmp}}/FruitTreeScanner-ci-tests}"
mkdir -p "$task_build_root"
task_evidence_tool="$task_repo_root/tools/ci_evidence.py"
task_evidence_root="${FTS_CI_EVIDENCE_DIR:-$task_build_root/evidence}"
task_run_root="$(python3 "$task_evidence_tool" prepare --root "$task_evidence_root" \
  --build-root "$task_build_root" --repo "$task_repo_root" --phase tests)"
task_test_log="$task_run_root/xctest.log"
task_result_bundle="$task_run_root/tests.xcresult"

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
if [[ "${FTS_CI_XCTEST_MODE:-strict}" == "strict" ]]; then
  task_reader_directory="$(python3 "$task_evidence_tool" reader-directory "$task_run_root")"
  export FTS_XCRESULT_DEVELOPER_DIR="$task_reader_directory"
fi
task_work_root="$(mktemp -d "$task_build_root/work.XXXXXX")"

# Preserve an explicit caller destination. The default must use a runtime no
# newer than this Xcode's SDK, chosen from the already retained toolchain logs.
task_destination="$(python3 "$task_evidence_tool" destination "$task_run_root" \
  --override "${FTS_CI_TEST_DESTINATION:-}")"

printf 'XCTest destination: %s\n' "$task_destination"

# 模拟器先确认启动完成，避免冷启动时宿主场景没就绪（既有 workflow 的同一条要求）。
# 目的地是 UDID 就直接用；给的是名字就查一次；都拿不到就跳过这一步并说明
# （xcodebuild 自己对无效目的地会失败，不必在这里编一个错误原因）。
task_concrete_udid="$(python3 - "$task_destination" <<'PY'
import sys

fields = [part.partition("=") for part in sys.argv[1].split(",")]
platforms = [value.strip() for key, sep, value in fields if sep and key.strip() == "platform"]
ids = [value.strip() for key, sep, value in fields if sep and key.strip() == "id"]
has_name = any(sep and key.strip() == "name" for key, sep, _ in fields)
if platforms == ["iOS Simulator"] and len(ids) == 1 and not has_name:
    print(ids[0])
PY
)"
task_udid="$task_concrete_udid"
if [[ -z "$task_udid" && -z "${FTS_CI_HOST_APP_PATH:-}" && "${GITHUB_ACTIONS:-}" != "true" ]]; then
  task_name="$(printf '%s' "$task_destination" | sed -n 's/.*name=\([^,]*\).*/\1/p')"
  if [[ -n "$task_name" ]]; then
    task_udid="$(xcrun simctl list devices available -j 2>/dev/null | python3 -c '
import json, sys
try:
    devices = json.load(sys.stdin)
except Exception:
    raise SystemExit(0)
name = sys.argv[1]
for runtime, entries in (devices.get("devices") or {}).items():
    for device in entries:
        if device.get("name") == name and device.get("isAvailable"):
            print(device.get("udid", ""))
            raise SystemExit(0)
' "$task_name")"
  fi
fi
if [[ -n "$task_udid" ]]; then
  if ! python3 "$task_evidence_tool" run --name simulator-bootstatus --log simulator-bootstatus.log \
    "$task_run_root" -- xcrun simctl bootstatus "$task_udid" -b; then
    printf 'simulator %s did not finish booting for the XCTest gate\n' "$task_udid" >&2
    exit 2
  fi
else
  printf 'could not resolve a simulator UDID from the destination; skipping the bootstatus precondition\n' >&2
fi

# The permission and AX fixture must exist before XCTest can launch its host.
# Setup mutates only the concrete destination UUID, never a name-based guess.
if ! python3 "$task_evidence_tool" run --name ui-host-setup --log ui-host-setup.log "$task_run_root" -- \
  python3 "$task_repo_root/tools/ci_ui_host_setup.py" setup --app "${FTS_CI_HOST_APP_PATH:-}" \
    --simulator "$task_concrete_udid" --devices "$task_run_root/simulators.log" \
    --output "$task_run_root/ui-host"; then
  cat "$task_run_root/ui-host-setup.log" >&2
  exit 2
fi

# A conditional preserves xcodebuild's status even under bash -e -o pipefail.
if python3 "$task_evidence_tool" run --name xctest --log xctest.log "$task_run_root" -- xcodebuild test \
  -project "$task_repo_root/FruitTreeScanner.xcodeproj" \
  -scheme FruitTreeScanner \
  -configuration Debug \
  -destination "$task_destination" \
  -testLanguage zh-Hans \
  -derivedDataPath "$task_work_root/DerivedData" \
  -resultBundlePath "$task_result_bundle" \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO; then
  task_test_status=0
else
  task_test_status=$?
fi

printf 'xcodebuild test exit %s. Log: %s\n' "$task_test_status" "$task_test_log"
if (( task_test_status != 0 )); then
  grep -E "error:|failed \(|XCTAssert" "$task_test_log" | tail -n 60 || true
  exit "$task_test_status"
fi

if [[ ! -d "$task_result_bundle" ]]; then
  printf 'xcodebuild reported success but produced no result bundle: %s\n' "$task_result_bundle" >&2
  exit 2
fi

if [[ "${FTS_CI_XCTEST_MODE:-strict}" == "handoff" ]]; then
  printf 'XCTest executed; strict validation is pending in the mandatory verify job.\n'
  exit 0
fi

# 判定只有这一份：摘要计数、零跳过、阻塞警告、声明类是否真的跑过。
python3 "$task_evidence_tool" run --name xctest-gate --log gate.log "$task_run_root" -- \
  python3 "$task_repo_root/tools/xctest_gate.py" "$task_result_bundle" --repo "$task_repo_root"
