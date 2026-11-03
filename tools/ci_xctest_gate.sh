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
task_test_log="$task_build_root/xctest.log"
task_result_bundle="$task_build_root/tests.xcresult"
if [[ -z "${DEVELOPER_DIR:-}" ]]; then
  DEVELOPER_DIR="$(xcode-select -p)"
fi
export DEVELOPER_DIR

rm -rf "$task_result_bundle"

# 目的地必须是具体模拟器：generic 目的地跑不了测试。
# 优先用 FTS_CI_TEST_DESTINATION；否则从可用设备里挑一台 iPhone。
task_destination="${FTS_CI_TEST_DESTINATION:-}"
if [[ -z "$task_destination" ]]; then
  task_udid="$(python3 - <<'PY'
import json, subprocess, sys

raw = subprocess.run(["xcrun", "simctl", "list", "devices", "available", "-j"],
                     capture_output=True, text=True)
if raw.returncode != 0:
    sys.exit(0)
try:
    devices = json.loads(raw.stdout)
except Exception:
    sys.exit(0)

best = None
for runtime, entries in (devices.get("devices") or {}).items():
    if "iOS" not in runtime and "iPadOS" not in runtime:
        continue
    for device in entries:
        if not device.get("isAvailable"):
            continue
        name = device.get("name", "")
        if "iPhone" not in name and "iPad" not in name:
            continue
        candidate = (runtime, device.get("udid", ""))
        if best is None or candidate[0] > best[0]:
            best = candidate
if best:
    print(best[1])
PY
)"
  if [[ -z "$task_udid" ]]; then
    printf 'no available iOS simulator found for the XCTest gate\n' >&2
    exit 2
  fi
  task_destination="platform=iOS Simulator,id=$task_udid"
fi

printf 'XCTest destination: %s\n' "$task_destination"

# 模拟器先确认启动完成，避免冷启动时宿主场景没就绪（既有 workflow 的同一条要求）。
# 目的地是 UDID 就直接用；给的是名字就查一次；都拿不到就跳过这一步并说明
# （xcodebuild 自己对无效目的地会失败，不必在这里编一个错误原因）。
task_udid="$(printf '%s' "$task_destination" | sed -n 's/.*id=\([^,]*\).*/\1/p')"
if [[ -z "$task_udid" ]]; then
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
  if ! xcrun simctl bootstatus "$task_udid" -b; then
    printf 'simulator %s did not finish booting for the XCTest gate\n' "$task_udid" >&2
    exit 2
  fi
else
  printf 'could not resolve a simulator UDID from the destination; skipping the bootstatus precondition\n' >&2
fi

# A conditional preserves xcodebuild's status even under bash -e -o pipefail.
if xcodebuild test \
  -project "$task_repo_root/FruitTreeScanner.xcodeproj" \
  -scheme FruitTreeScanner \
  -configuration Debug \
  -destination "$task_destination" \
  -derivedDataPath "$task_build_root/DerivedData" \
  -resultBundlePath "$task_result_bundle" \
  -parallel-testing-enabled NO \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO \
  > "$task_test_log" 2>&1; then
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

# 判定只有这一份：摘要计数、零跳过、阻塞警告、声明类是否真的跑过。
python3 "$task_repo_root/tools/xctest_gate.py" "$task_result_bundle" --repo "$task_repo_root"
