#!/usr/bin/env python3
"""Select a CI xcresult reader by its official, inspectable summary schema."""

import json
from pathlib import Path


SCHEMA_COMMAND = ("xcrun", "xcresulttool", "get", "test-results", "summary", "--schema")
MAXIMUM_SCHEMA_BYTES = 2 * 1024 * 1024


def _object(value, name):
    if not isinstance(value, dict):
        raise ValueError(f"missing or invalid schema object: {name}")
    return value


def _required_field(schema, field, name):
    required = schema.get("required")
    if not isinstance(required, list) or not all(isinstance(item, str) for item in required) or field not in required:
        raise ValueError(f"schema {name}.{field} is not required")
    return _object(_object(schema.get("properties"), f"{name}.properties").get(field), f"{name}.{field}")


def require_warning_schema(path):
    """Accept only the typed runtime-warning capability exposed by xcresulttool."""
    if path.stat().st_size > MAXIMUM_SCHEMA_BYTES:
        raise ValueError("summary schema exceeds the probe size limit")
    document = _object(json.loads(path.read_text()), "document")
    schemas = _object(document.get("schemas"), "schemas")
    summary = _object(schemas.get("Summary"), "Summary")
    if summary.get("type") != "object":
        raise ValueError("schema Summary must be an object")
    warnings = _required_field(summary, "runtimeWarnings", "Summary")
    if warnings.get("type") != "array":
        raise ValueError("schema Summary.runtimeWarnings must be an array")
    if _object(warnings.get("items"), "Summary.runtimeWarnings.items").get("$ref") != "#/schemas/Issue":
        raise ValueError("schema Summary.runtimeWarnings items must reference Issue")
    issue = _object(schemas.get("Issue"), "Issue")
    if issue.get("type") != "object" or _required_field(issue, "message", "Issue").get("type") != "string":
        raise ValueError("schema Issue.message must be a required string")


def _candidate_paths(compiler_dir, configured, explicit, candidates):
    if explicit:
        if not isinstance(configured, str) or not configured.strip():
            raise ValueError("Explicit FTS_XCRESULT_DEVELOPER_DIR must name a result reader toolchain")
        values = [configured]
    else:
        installed = candidates if candidates is not None else sorted(
            path for path in Path("/Applications").glob("Xcode*.app/Contents/Developer") if path.is_dir())
        values = [compiler_dir, *installed]
    seen = set()
    for value in values:
        if not isinstance(value, (str, Path)) or not str(value).strip():
            raise ValueError("Invalid result reader developer directory")
        directory = str(Path(value).expanduser().resolve())
        if directory not in seen:
            seen.add(directory)
            yield directory


def select_reader(run, compiler_dir, configured, explicit, run_command, candidates=None):
    """Probe using only a child developer directory; preserve all probe evidence.

    ``run_command`` is the evidence runner: it receives the compiler-independent
    developer directory and writes raw stdout/stderr under ``run``. A present
    explicit override is the only candidate, even when it is empty or invalid.
    An automatic choice starts with the compiling Xcode, then checks installed
    candidates by capability. It never modifies the environment of this process.
    """
    run = Path(run)
    probes = run / "reader-probes"
    selection_path = run / "reader-selection.json"
    if selection_path.exists():
        raise ValueError("Result reader selection evidence already exists for this attempt")
    probes.mkdir()
    manifest = {
        "compiler_developer_dir": str(compiler_dir), "explicit": explicit,
        "configured_developer_dir": configured, "developer_dir": None, "probes": [],
    }
    try:
        for index, directory in enumerate(_candidate_paths(compiler_dir, configured, explicit, candidates)):
            prefix = f"reader-probes/{index:02d}"
            probe = {"developer_dir": directory, "stdout": prefix + ".schema.json",
                     "stderr": prefix + ".stderr.log", "exit_code": None, "supported": False}
            manifest["probes"].append(probe)
            try:
                status = run_command(run, f"reader-summary-schema-{index:02d}", list(SCHEMA_COMMAND),
                                     probe["stdout"], stderr=probe["stderr"], developer_dir=directory)
                if type(status) is not int:
                    raise ValueError("schema probe returned no valid exit status")
                probe["exit_code"] = status
                if status:
                    raise ValueError(f"xcresulttool schema probe exited {status}")
                if not (run / probe["stderr"]).is_file():
                    raise ValueError("schema probe stderr evidence is unavailable")
                require_warning_schema(run / probe["stdout"])
            except (OSError, ValueError, RecursionError) as error:
                probe["rejection_reason"] = str(error)
                continue
            probe["supported"] = True
            manifest["developer_dir"] = directory
            break
        if manifest["developer_dir"] is None:
            if explicit:
                raise ValueError("Explicit result reader does not support the required runtimeWarnings schema")
            raise ValueError("No installed result reader supports the required runtimeWarnings schema")
        manifest["status"] = "selected"
    except (OSError, ValueError, RuntimeError) as error:
        manifest.update(status="failed", rejection_reason=str(error))
        raise ValueError(str(error)) from error
    finally:
        with selection_path.open("x") as handle:
            json.dump(manifest, handle, indent=2)
            handle.write("\n")
    return {"developer_dir": manifest["developer_dir"], "manifest": manifest,
            "manifest_path": str(selection_path)}
