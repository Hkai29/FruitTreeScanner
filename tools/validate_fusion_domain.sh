#!/bin/bash
set -euo pipefail

# Compile every Domain source without App/Core/legacy sources.
task_repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
task_module_dir="$(mktemp -d "${TMPDIR:-/tmp}/fruit-scan-fusion.XXXXXX")"
trap 'rm -rf "$task_module_dir"' EXIT

export DEVELOPER_DIR="${DEVELOPER_DIR:-/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer}"
task_simulator_sdk="$(xcrun --sdk iphonesimulator --show-sdk-path)"
task_domain="$task_repo_root/FruitTreeScanner/Domain"
task_source_list="$task_module_dir/domain-sources"
# Include new subdirectories automatically; do not maintain an exclusion list.
if command -v rg >/dev/null; then
  rg --files --hidden --no-ignore --null --glob '*.swift' "$task_domain" > "$task_source_list"
else
  /usr/bin/find "$task_domain" \( -type f -o -type l \) -name '*.swift' -print0 > "$task_source_list"
fi
task_sources=()
while IFS= read -r -d '' task_source; do
  task_sources+=("$task_source")
done < "$task_source_list"

xcrun swiftc -emit-module -swift-version 5 \
  -module-name FruitScanDomain \
  -target arm64-apple-ios16.0-simulator -sdk "$task_simulator_sdk" \
  -emit-module-path "$task_module_dir/FruitScanDomain.swiftmodule" \
  "${task_sources[@]}"

printf 'Entire Domain compiled independently: %s sources, iOS 16 simulator, Swift 5.\n' "${#task_sources[@]}"
