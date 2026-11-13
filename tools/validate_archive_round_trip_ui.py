#!/usr/bin/env python3
"""Close the native archive detail round trip in an invocation-owned simulator.

Seeds a controlled archive fixture (enough records to scroll, two plots, mixed
review statuses, two archives of the same tree) into the disposable simulator
created here, then drives the real root entry: filter -> scroll to a non-top
record -> open its detail -> **real system back button** -> filter, identity and
position restored, twice; plus the point-cloud and share sheets opened and
dismissed before going back.

The fixture is seeded only after the app under test has been installed and
terminated by the UI test itself (same handshake the batch-export runner uses),
so the install can never overwrite it.

Only the simulator created by this invocation is touched. No production launch
hook, no real history, no default user data, no global device setting, and no
commit or push.
"""
import argparse
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import time
import uuid
from datetime import datetime, timedelta
from pathlib import Path

sys.dont_write_bytecode = True
from validate_native_ui import REPOSITORY, snapshot
from code_improvement_workflow import validate_summary

APP_ID = "com.hkai29.fruitscanner"
RUNNER_ID = APP_ID + ".uitests.xctrunner"
TEST_CLASS = "ArchiveRoundTripUITests"
METHODS = [
    "testArchiveDetailRoundTripRestoresFilterScrollAndIdentity",
    "testArchiveDetailSurvivesPointCloudAndShareDismissal",
    "testArchiveSearchAndDateGroupsSurviveDetailRoundTrip",
]
PLOT = "北坡"
OTHER_PLOT = "南坡"
TARGET = "T-07_20261020_090000_lat31_lon121"
SAME_TREE_OTHER = "T-07_20261019_160000_lat31_lon122"
TARGET_TREE = "T-07"
# 不在「T-0」搜索命中范围内的那一份（用来证明搜索真的筛掉了别人）。
OTHER_ARCHIVE = "T-01_20261025_143000_lat31_lon121"
# 用稳定的记录号坐标段查询，跨月/跨年仍覆盖今天、昨天与更早的记录。
# 同树的另一份使用 lon122，确保宽查询仍会排除记录，而不是全部命中。
BROAD_QUERY = "_lat31_lon121"


def fixture_day_stamps():
    """把「今天 / 昨天」的扫描时间算出来。

    分组按 **Calendar 的那一天** 判定，所以这两条必须落在真的今天与真的昨天。
    时间取比现在早一点：落在未来的扫描日期会被明确降级成「日期异常」，
    那样就证明不了「今天」这一段了。
    """
    now = datetime.now()
    midnight = now.replace(hour=0, minute=0, second=0, microsecond=0)
    today = now - timedelta(minutes=3)
    if today.date() != now.date():
        # 刚过午夜：退回今天的第一秒，仍然是今天。
        today = midnight + timedelta(seconds=1)
    yesterday = (now - timedelta(days=1)).replace(hour=9, minute=0, second=0, microsecond=0)
    return today.strftime("%Y%m%d_%H%M%S"), yesterday.strftime("%Y%m%d_%H%M%S")


def fixture_archives():
    """夹具档案：够多行能滚动、两个地块、混合复核状态、同一棵树的两份，
    外加今天/昨天各一份（用来证明日期分组在真机里真的分组了）。

    返回 (档案列表, 今天的时间戳, 昨天的时间戳) —— 后两个用来算分组份数。
    """
    today_stamp, yesterday_stamp = fixture_day_stamps()
    archives = [
        ("T-01_20261025_143000_lat31_lon121", "T-01", PLOT, "已扫描", True),
        ("T-01_20261025_101500_lat31_lon121", "T-01", PLOT, "已扫描", True),
        ("T-02_20261024_160000_lat31_lon121", "T-02", OTHER_PLOT, "复查中", True),
        ("T-03_20261024_090000_lat31_lon121", "T-03", OTHER_PLOT, "已扫描", True),
        ("T-04_20261023_160000_lat31_lon121", "T-04", PLOT, "已扫描", True),
        ("T-05_20261023_090000_lat31_lon121", "T-05", PLOT, "已扫描", True),
        ("T-08_20261022_160000_lat31_lon121", "T-08", PLOT, "已扫描", True),
        ("T-09_20261022_090000_lat31_lon121", "T-09", PLOT, "已扫描", True),
        ("T-10_20261021_160000_lat31_lon121", "T-10", PLOT, "已扫描", True),
        ("T-11_20261021_090000_lat31_lon121", "T-11", PLOT, "已扫描", True),
        ("T-12_20261020_160000_lat31_lon121", "T-12", PLOT, "已扫描", True),
        (TARGET, TARGET_TREE, PLOT, "已扫描", True),
        (SAME_TREE_OTHER, TARGET_TREE, PLOT, "已扫描", True),
        # No result companion: the row must degrade to "unavailable", never to zero.
        ("T-13_20261019_090000_lat31_lon121", "T-13", PLOT, "已扫描", False),
        ("T-14_20261018_160000_lat31_lon121", "T-14", PLOT, "已扫描", True),
        # 今天 / 昨天：分组标题「今天 · N 份」「昨天 · N 份」要在真机里出现。
        ("T-15_%s_lat31_lon121" % today_stamp, "T-15", PLOT, "已扫描", True),
        ("T-16_%s_lat31_lon121" % today_stamp, "T-16", PLOT, "已扫描", True),
        ("T-17_%s_lat31_lon121" % yesterday_stamp, "T-17", PLOT, "已扫描", True),
    ]
    return archives, today_stamp, yesterday_stamp


def broad_query_counts(archives, today_stamp, yesterday_stamp, query, plot=PLOT):
    """一段记录号查询命中后，今天/昨天/更早各多少份。

    UI 用例靠这个数字断言「筛出来的正好是这些」—— 组标题上写着份数，
    比「某个行在不在无障碍树里」硬得多（行会被 LazyVStack 裁掉）。
    只算**当前地块**里的那些：UI 用例那一轮是带着地块筛选的。
    """
    hits = [entry for entry in archives if query in entry[0] and entry[2] == plot]
    today = sum(1 for entry in hits if today_stamp in entry[0])
    yesterday = sum(1 for entry in hits if yesterday_stamp in entry[0])
    return {"today": today, "yesterday": yesterday, "earlier": len(hits) - today - yesterday}


# (file stem, tree id, plot, review status, has result companion)
#
# 目标那一条（T-07_20261020_090000…）在「北坡」筛选下排在前面几份之后 ——
# 一屏只放得下几行，所以它一开始就在**折叠线以下**：
# 「滚到非顶部目标」这条验收必须是真滚动，不是恒真断言。
# 同树的另一份（T-07_20261019_160000…）紧挨在它下面 ——
# 恢复回来时必须仍停在这一份，而不是它。


def ply_bytes(point_count=12):
    header = [
        "ply",
        "format ascii 1.0",
        "element vertex %d" % point_count,
        "property float x",
        "property float y",
        "property float z",
        "property uchar red",
        "property uchar green",
        "property uchar blue",
        "end_header",
    ]
    body = []
    for index in range(point_count):
        body.append("%.3f %.3f %.3f %d %d %d" % (
            round(0.1 * index, 3), round(0.2 * index, 3), round(0.3 * index, 3),
            180 + index, 140 + index, 90 + index))
    return ("\n".join(header + body) + "\n").encode("utf-8")


def result_bytes(tree_id, fruit_count, yield_kg):
    # Legacy companion metadata: no exportRevision field, so the archive stays
    # a complete result (the same shape the batch-export fixture uses).
    payload = {
        "treeID": tree_id,
        "fruitCount": fruit_count,
        "yieldKg": yield_kg,
        "fruitType": "苹果",
        "confidence": "high",
    }
    return json.dumps(payload, ensure_ascii=False).encode("utf-8")


def tag_store_snapshot(plot_ids, archives):
    # TagStore persists one JSON snapshot in UserDefaults. Dates use the
    # default deferred-to-date strategy, i.e. seconds since 2001-01-01.
    created = 700000000.0
    return {
        "plots": [
            {"id": plot_ids[0], "name": PLOT, "colorHex": "#4D7588",
             "displayOrder": 0, "createdAt": created},
            {"id": plot_ids[1], "name": OTHER_PLOT, "colorHex": "#6F8F63",
             "displayOrder": 1, "createdAt": created},
        ],
        "tags": [],
        "assignments": [
            {"treeId": tree_id, "plotId": plot_ids[0 if plot == PLOT else 1],
             "tagIds": [], "status": status}
            for _, tree_id, plot, status, _ in archives
        ],
    }


def require(condition, message):
    """Fail loudly when a gate condition is not met.

    ``assert`` is not used for gates on purpose: ``python -O`` (or
    ``PYTHONOPTIMIZE=1``) strips asserts, which would silently switch a
    protection gate off instead of failing the run.
    """
    if not condition:
        raise AssertionError(message)


class SeededArchiveLost(AssertionError):
    """A seeded archive disappeared, changed, or could not be read.

    The failure report travels with the exception so the runner can still
    record *what* was lost instead of only an opaque assertion.
    """

    def __init__(self, report):
        super().__init__(report["archive_preservation_failure"])
        self.report = report


def inspect_seeded_archives(scans, source_hashes):
    """Compare the archive directory against the digests this run seeded.

    Every seeded archive must still be there with the same bytes. A seeded
    archive that is gone, whose bytes changed, or that cannot be read is a
    failure of this gate — not a footnote. Files the app created on its own
    are reported separately and never count as a change to the seeded
    archives; an empty seed map proves nothing and is therefore not preserved
    either.
    """
    missing = []
    unreadable = {}
    changed = {}
    for name, expected in sorted(source_hashes.items()):
        path = scans / name
        if not path.is_file():
            missing.append(name)
            continue
        try:
            digest = hashlib.sha256(path.read_bytes()).hexdigest()
        except OSError as error:
            unreadable[name] = repr(error)
            continue
        if digest != expected:
            changed[name] = digest
    try:
        added = sorted(entry.name for entry in scans.iterdir()
                       if entry.is_file() and entry.name not in source_hashes)
    except OSError as error:
        added = []
        unreadable.setdefault("<scans directory>", repr(error))
    if not source_hashes:
        missing.append("<no archives were seeded>")
    report = {
        "archive_preserved": not (missing or unreadable or changed),
        "archive_files_added_by_app": added,
        "archive_files_removed": sorted(missing),
        "archive_files_changed": sorted(changed),
        "archive_files_unreadable": sorted(unreadable),
    }
    reasons = []
    if missing:
        reasons.append("removed=" + repr(missing))
    if unreadable:
        reasons.append("unreadable=" + repr(unreadable))
    if changed:
        reasons.append("changed=" + repr(changed))
    report["archive_preservation_failure"] = (
        "The seeded archives must survive the run untouched: " + "; ".join(reasons)
        if reasons else "")
    return report


def verify_seeded_archives(scans, source_hashes):
    """Fail unless every seeded archive is still present with the same bytes."""
    report = inspect_seeded_archives(scans, source_hashes)
    if not report["archive_preserved"]:
        raise SeededArchiveLost(report)
    return report


def apply_preservation_verdict(report, scans, source_hashes):
    """Apply the seeded-archive verdict to the run report.

    A lost archive must never leave ``archive_preserved=true`` or
    ``result=passed`` behind, so the report is marked failed *before* the
    failure propagates.
    """
    try:
        report.update(verify_seeded_archives(scans, source_hashes))
    except SeededArchiveLost as error:
        report.update(error.report)
        report["archive_preserved"] = False
        report["result"] = "failed"
        raise
    return report


def case_result(tree, case_id):
    """结果树里这一条用例的结果（找不到就是 None）。"""
    stack = list(tree.get("testNodes", []))
    while stack:
        node = stack.pop()
        if node.get("nodeType") == "Test Case" and node.get("nodeIdentifier") == case_id:
            return node.get("result")
        stack.extend(node.get("children", []))
    return None


def evidence_passed(exit_code, summary, tree, expected_ids):
    """与共享门禁同一套判定，但要按**本类**的用例集合核对结果树。

    计数也必须与这次期望的用例集合一致：一份「总数 2 / 通过 2」但结果树里
    实际跑了 3 条的摘要，不是这次运行该有的证据。
    """
    return (exit_code == 0 and summary.get("result") == "Passed"
            and type(summary.get("passedTests")) is int and summary["passedTests"] > 0
            and type(summary.get("totalTestCount")) is int
            and summary["totalTestCount"] == summary["passedTests"]
            and summary["totalTestCount"] == len(expected_ids)
            and all(type(summary.get(key)) is int and summary[key] == 0
                    for key in ("failedTests", "skippedTests", "expectedFailures"))
            and all(case_result(tree, case_id) == "Passed" for case_id in expected_ids))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-root", type=Path, required=True)
    args = parser.parse_args()
    parent = args.output_root.resolve()
    if parent == REPOSITORY or REPOSITORY in parent.parents:
        parser.error("Evidence must be outside the repository")
    parent.mkdir(parents=True, exist_ok=True)
    output = Path(tempfile.mkdtemp(prefix="archive-roundtrip-ui-", dir=parent))
    print("Evidence directory: " + str(output), flush=True)
    env = dict(os.environ)
    env["DEVELOPER_DIR"] = "/Users/reece24/Downloads/Xcode-beta.app/Contents/Developer"
    before = snapshot()
    (output / "source-before.json").write_text(json.dumps(before, indent=2))

    def read(*command):
        return subprocess.check_output(command, env=env, cwd=REPOSITORY, text=True).strip()

    runtimes = json.loads(read("xcrun", "simctl", "list", "runtimes", "--json"))["runtimes"]
    runtime = max((r for r in runtimes if r.get("isAvailable") and r.get("platform") == "iOS"),
                  key=lambda r: tuple(int(v) for v in r["version"].split(".")))
    simulator = read("xcrun", "simctl", "create", "FruitTreeScanner-NativeUI-" + str(uuid.uuid4()),
                     "com.apple.CoreSimulator.SimDeviceType.iPhone-SE-3rd-generation", runtime["identifier"])
    token = str(uuid.uuid4())
    env["TEST_RUNNER_FRUIT_NATIVE_UI_SIMULATOR_ID"] = simulator
    env["TEST_RUNNER_FRUIT_ARCHIVE_UI_TOKEN"] = token
    plot_ids = [str(uuid.uuid4()).upper(), str(uuid.uuid4()).upper()]
    def yield_text(index):
        return "%.1f" % (1.5 + index * 0.75)

    # 夹具在**播种前一刻**才定下来：今天/昨天的扫描时间必须相对应用读档案那一刻成立。
    archives, today_stamp, yesterday_stamp = fixture_archives()
    target_index = [i for i, entry in enumerate(archives) if entry[0] == TARGET][0]
    sibling_index = [i for i, entry in enumerate(archives) if entry[0] == SAME_TREE_OTHER][0]
    today_archive = [entry for entry in archives if entry[1] == "T-15"][0][0]
    yesterday_archive = [entry for entry in archives if entry[1] == "T-17"][0][0]
    fixture = {
        "plot": PLOT,
        "otherPlot": OTHER_PLOT,
        "target": {"archiveID": TARGET + ".ply", "treeID": TARGET_TREE,
                   "yieldText": yield_text(target_index)},
        "sameTreeOtherArchive": {"archiveID": SAME_TREE_OTHER + ".ply", "treeID": TARGET_TREE,
                                 "yieldText": yield_text(sibling_index)},
        "otherArchiveID": OTHER_ARCHIVE + ".ply",
        "todayArchiveID": today_archive + ".ply",
        "yesterdayArchiveID": yesterday_archive + ".ply",
        "broadQuery": BROAD_QUERY,
        "broadCounts": broad_query_counts(archives, today_stamp, yesterday_stamp, BROAD_QUERY),
    }
    env["TEST_RUNNER_FRUIT_ARCHIVE_UI_FIXTURE"] = json.dumps(fixture, ensure_ascii=False)
    report = {"simulator": simulator, "runtime": runtime["identifier"], "token": token,
              "fixture": fixture, "result": "failed"}
    (output / "report.json").write_text(json.dumps(report, indent=2))
    common = ["-project", str(REPOSITORY / "FruitTreeScanner.xcodeproj"), "-scheme", "FruitTreeScannerUI",
              "-derivedDataPath", str(output / "DerivedData"), "CODE_SIGNING_ALLOWED=NO",
              "-destination", "platform=iOS Simulator,id=" + simulator, "-parallel-testing-enabled", "NO"]

    def run_build(command, filename):
        report[filename + "_command"] = command
        with (output / (filename + ".log")).open("w") as log:
            result = subprocess.run(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
        report[filename + "_exit_code"] = result.returncode
        if result.returncode:
            raise RuntimeError(filename + " failed; inspect its original log")

    process = None
    try:
        run_build(["xcodebuild", "build-for-testing", *common,
                   "-resultBundlePath", str(output / "build.xcresult")], "build")
        read("xcrun", "simctl", "boot", simulator)
        read("xcrun", "simctl", "bootstatus", simulator, "-b")

        command = ["xcodebuild", "test-without-building", *common,
                   "-resultBundlePath", str(output / "ui.xcresult"),
                   "-only-testing:FruitTreeScannerUITests/" + TEST_CLASS]
        report["ui_command"] = command
        coordination = None
        prepared = False
        scans = None
        source_hashes = {}
        with (output / "ui.log").open("w") as log:
            process = subprocess.Popen(command, cwd=REPOSITORY, env=env, stdout=log, stderr=subprocess.STDOUT)
            deadline = time.monotonic() + 900
            while process.poll() is None:
                if time.monotonic() > deadline:
                    raise TimeoutError("Native UI validation exceeded its bounded deadline")
                if coordination is None:
                    found = subprocess.run(
                        ["xcrun", "simctl", "get_app_container", simulator, RUNNER_ID, "data"],
                        cwd=REPOSITORY, env=env, capture_output=True, text=True)
                    if found.returncode == 0:
                        coordination = Path(found.stdout.strip()) / "Documents/ArchiveRoundTrip" / token
                        report["runner_container"] = found.stdout.strip()
                if coordination is not None and not prepared:
                    # The UI test has installed and terminated the app by now.
                    request = coordination / "request-fixture"
                    if request.exists():
                        container = Path(read("xcrun", "simctl", "get_app_container", simulator, APP_ID, "data"))
                        report["container"] = str(container)
                        scans = container / "Documents/scans"
                        scans.mkdir(parents=True, exist_ok=True)
                        require(not list(scans.iterdir()),
                                "Fixture must start from an empty archive directory")
                        for index, (stem, tree_id, _, _, has_result) in enumerate(archives):
                            (scans / (stem + ".ply")).write_bytes(ply_bytes())
                            if has_result:
                                (scans / (stem + "_result.json")).write_bytes(
                                    result_bytes(tree_id, 12 + index, round(1.5 + index * 0.75, 2)))
                        source_hashes = {p.name: hashlib.sha256(p.read_bytes()).hexdigest()
                                         for p in scans.iterdir()}
                        report["seeded_archives"] = sorted(source_hashes)

                        # The archive page filters by the tree's *current* plot
                        # assignment, so the fixture needs the tag store snapshot.
                        preferences = container / "Library/Preferences" / (APP_ID + ".plist")
                        preferences.parent.mkdir(parents=True, exist_ok=True)
                        payload = json.dumps(
                            tag_store_snapshot(plot_ids, archives), ensure_ascii=False).encode("utf-8")
                        # The preferences daemon caches the domain it last served and
                        # can serve that stale cache to the app, so a written file is
                        # not enough: the daemon's cache has to go. Stopping it is
                        # `launchctl stop` — the iOS simulator runtime has no
                        # `killall` (that call exits 2 and does nothing).
                        for attempt in range(1, 4):
                            stopped = subprocess.run(
                                ["xcrun", "simctl", "spawn", simulator, "launchctl", "stop",
                                 "com.apple.cfprefsd.xpc.daemon"],
                                env=env, capture_output=True, text=True)
                            if stopped.returncode != 0:
                                raise RuntimeError(
                                    "Could not stop the preferences daemon (exit %d): %s"
                                    % (stopped.returncode, stopped.stderr.strip()))
                            document = {}
                            if preferences.is_file():
                                with preferences.open("rb") as handle:
                                    document = plistlib.load(handle)
                            document["TagStore.snapshot.v1"] = payload
                            with preferences.open("wb") as handle:
                                plistlib.dump(document, handle, fmt=plistlib.FMT_BINARY)
                            time.sleep(0.8)
                            with preferences.open("rb") as handle:
                                written = plistlib.load(handle)
                            if written.get("TagStore.snapshot.v1") == payload:
                                report["seeded_preferences"] = str(preferences)
                                report["preferences_attempts"] = attempt
                                break
                        else:
                            raise RuntimeError("The tag store snapshot did not stick in the app preferences")
                        (coordination / "fixture-ready").write_text("fixture-ready")
                        prepared = True
                        print("Installed app fixture prepared before launch", flush=True)
                time.sleep(0.25)
        report["ui_exit_code"] = process.returncode
        ui_log = (output / "ui.log").read_text(errors="replace")
        report["fixture_not_effective"] = ("筛选菜单里必须有地块" in ui_log
                                           or "档案页必须带地块筛选" in ui_log)

        if not (output / "ui.xcresult").exists():
            raise RuntimeError("The UI run produced no result bundle")
        summary = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "summary",
                                  "--path", str(output / "ui.xcresult"), "--compact"))
        tree = json.loads(read("xcrun", "xcresulttool", "get", "test-results", "tests",
                                "--path", str(output / "ui.xcresult"), "--compact"))
        (output / "summary.json").write_text(json.dumps(summary, indent=2))
        (output / "tests.json").write_text(json.dumps(tree, indent=2))
        validate_summary(summary)
        methods = {}
        stack = list(tree.get("testNodes", []))
        while stack:
            node = stack.pop()
            if node.get("nodeType") == "Test Case":
                methods[node["nodeIdentifier"]] = node["result"]
            stack.extend(node.get("children", []))
        report["methods"] = methods
        expected = {TEST_CLASS + "/" + method + "()" for method in METHODS}
        # These are the **evidence gate**: the run must fail when the UI result
        # tree is not exactly what it has to be. They are explicit raises, not
        # ``assert`` — ``python -O`` strips asserts and would silently switch
        # this gate off.
        require(set(methods) == expected,
                "The result tree must contain exactly the round-trip cases: " + repr(methods))
        require(all(result == "Passed" for result in methods.values()), repr(methods))
        require(evidence_passed(process.returncode, summary, tree, expected),
                "The UI evidence did not pass: " + repr((summary, methods)))
        require(summary["totalTestCount"] == len(expected), repr(summary))
        require(prepared, "The fixture must have been seeded")
        # The seeded archives must survive the run untouched. A seeded archive
        # that disappeared, changed, or cannot be read fails this gate.
        # Files the app creates on its own are reported separately — they are
        # not a change to the seeded archives.
        apply_preservation_verdict(report, scans, source_hashes)
        report["result"] = "passed"
    except Exception as error:
        report["error"] = repr(error)
        raise
    finally:
        if process is not None and process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=15)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait(timeout=15)
        subprocess.run(["xcrun", "simctl", "shutdown", simulator], env=env, capture_output=True)
        deletion = subprocess.run(["xcrun", "simctl", "delete", simulator], env=env, capture_output=True)
        report["owned_simulator_deleted"] = deletion.returncode == 0
        report["sources_unchanged"] = before == snapshot()
        if not report["owned_simulator_deleted"] or not report["sources_unchanged"]:
            report["result"] = "failed"
        (output / "report.json").write_text(json.dumps(report, indent=2))
        print(json.dumps(report, ensure_ascii=False), flush=True)
    return 0 if report["result"] == "passed" else 1


if __name__ == "__main__":
    raise SystemExit(main())
