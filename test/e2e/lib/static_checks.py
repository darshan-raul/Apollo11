#!/usr/bin/env python3
"""Opaque-box static, curriculum, schema, and manifest checks (T1-01..T1-10, T2-01..T2-06).

Uses ONLY Python stdlib + PyYAML (never jsonschema or pytest).
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
from decimal import Decimal, InvalidOperation
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
from typing import Any

import yaml


TRACKER_ID_RE = re.compile(
    r"\bG(?:[4-9]|[1-3][0-9])[a-z]?\b|\bG[1-3][a-z]\b|\btracker\s+G[0-9]+\b|\(G[1-3]\)"
)
TRACKER_META_RE = re.compile(
    r"(?i)(GAPS_TRACKER|AUDIT_GAPS_AND_EXPANSIONS|DOCS_IMPROVEMENT_REPORT|"
    r"GAP_CLOSURE|\bgap\s+tracker\b|\binternal\s+tracker\b|\btracker\s+ID\b|\btracker\s+[0-9]+)"
)

ALLOWED_CONTEXT_GUARD_PATTERNS = ("kind-apollo11", "kind-apollo11-dev")


def make_result(
    check_id: str,
    tier: str,
    status: str,
    summary: str,
    detail: str = "",
    tool_missing: bool = False,
) -> dict[str, Any]:
    return {
        "id": check_id,
        "tier": tier,
        "status": status,
        "summary": summary,
        "detail": detail,
        "tool_missing": tool_missing,
    }


def run_cmd(
    cmd: list[str],
    cwd: Path | None = None,
    env: dict[str, str] | None = None,
    timeout: int = 120,
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        cmd,
        cwd=str(cwd) if cwd else None,
        env=env,
        capture_output=True,
        text=True,
        timeout=timeout,
    )


def have_tool(tool: str) -> bool:
    path = shutil.which(tool)
    if not path:
        return False
    probe_args = {
        "bash": ["--version"],
        "shellcheck": ["--version"],
        "helm": ["version", "--short"],
        "kustomize": ["version"],
        "kubectl": ["version", "--client"],
        "promtool": ["--version"],
        "terraform": ["version"],
        "python3": ["--version"],
        "git": ["--version"],
        "go": ["version"],
        "trivy": ["--version"],
        "cosign": ["version"],
        "argocd": ["version", "--client"],
    }.get(tool, ["--version"])
    try:
        res = subprocess.run([tool, *probe_args], capture_output=True, text=True, timeout=10)
        return res.returncode == 0
    except (OSError, subprocess.TimeoutExpired):
        return False


def git_files(repo: Path, *pathspecs: str) -> list[Path]:
    cmd = ["git", "-C", str(repo), "ls-files", "--cached", "--others", "--exclude-standard"]
    if pathspecs:
        cmd.append("--")
        cmd.extend(pathspecs)
    res = run_cmd(cmd)
    if res.returncode != 0:
        return []
    out: list[Path] = []
    for line in res.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        if "node_modules/" in line or line.startswith("node_modules/"):
            continue
        p = repo / line
        if p.is_file():
            out.append(p)
    return sorted(set(out))


def load_yaml_docs(paths: list[Path]) -> tuple[list[tuple[Path, dict[str, Any]]], list[str]]:
    docs: list[tuple[Path, dict[str, Any]]] = []
    errors: list[str] = []
    for p in paths:
        try:
            text = p.read_text(encoding="utf-8")
        except OSError as exc:
            errors.append(f"{p}: read error: {exc}")
            continue
        try:
            for doc in yaml.safe_load_all(text):
                if isinstance(doc, dict):
                    docs.append((p, doc))
        except yaml.YAMLError as exc:
            errors.append(f"{p}: YAML parse error: {exc}")
    return docs, errors


def load_yaml_stream(text: str, source: str) -> tuple[list[dict[str, Any]], list[str]]:
    docs: list[dict[str, Any]] = []
    errors: list[str] = []
    try:
        for doc in yaml.safe_load_all(text):
            if isinstance(doc, dict):
                docs.append(doc)
    except yaml.YAMLError as exc:
        errors.append(f"{source}: YAML parse error: {exc}")
    return docs, errors


def walk_dict_keys(obj: Any, target_key: str) -> list[Any]:
    found: list[Any] = []
    if isinstance(obj, dict):
        for k, v in obj.items():
            if k == target_key:
                found.append(v)
            found.extend(walk_dict_keys(v, target_key))
    elif isinstance(obj, list):
        for item in obj:
            found.extend(walk_dict_keys(item, target_key))
    return found


def extract_containers(doc: dict[str, Any]) -> tuple[list[dict[str, Any]], list[dict[str, Any]]]:
    """Return (regular_containers, init_containers) from Pod/Workload/CronJob docs."""
    kind = doc.get("kind", "")
    spec = doc.get("spec")
    if not isinstance(spec, dict):
        return [], []
    pod_spec: dict[str, Any] | None = None
    if kind == "Pod":
        pod_spec = spec
    elif kind == "CronJob":
        jt = spec.get("jobTemplate", {})
        if isinstance(jt, dict):
            tpl = jt.get("spec", {}).get("template", {})
            if isinstance(tpl, dict):
                pod_spec = tpl.get("spec")
    else:
        tpl = spec.get("template")
        if isinstance(tpl, dict):
            pod_spec = tpl.get("spec")
    if not isinstance(pod_spec, dict):
        return [], []
    containers = [c for c in (pod_spec.get("containers") or []) if isinstance(c, dict)]
    inits = [c for c in (pod_spec.get("initContainers") or []) if isinstance(c, dict)]
    return containers, inits


def get_pod_template_annotations(doc: dict[str, Any]) -> dict[str, Any]:
    kind = doc.get("kind", "")
    spec = doc.get("spec")
    if not isinstance(spec, dict):
        return {}
    if kind == "Pod":
        ann = (doc.get("metadata") or {}).get("annotations")
        return ann if isinstance(ann, dict) else {}
    tpl = spec.get("template")
    if isinstance(tpl, dict):
        ann = (tpl.get("metadata") or {}).get("annotations")
        return ann if isinstance(ann, dict) else {}
    return {}


def normalize_lines(text: str) -> list[str]:
    out: list[str] = []
    for raw in text.splitlines():
        line = re.sub(r"\s+", " ", raw.strip())
        if not line:
            continue
        if re.fullmatch(r"[-|: ]+", line):
            continue
        out.append(line)
    return out


_QTY_FACTORS: dict[str, Decimal] = {
    "": Decimal("1"),
    "m": Decimal("0.001"),
    "Ki": Decimal("1024"),
    "Mi": Decimal(1024 ** 2),
    "Gi": Decimal(1024 ** 3),
    "Ti": Decimal(1024 ** 4),
    "K": Decimal("1000"),
    "k": Decimal("1000"),
    "M": Decimal(1000 ** 2),
    "G": Decimal(1000 ** 3),
    "T": Decimal(1000 ** 4),
}


def parse_k8s_qty(raw: Any) -> Decimal | None:
    if raw is None:
        return None
    s = str(raw).strip()
    m = re.fullmatch(r"([0-9]+(?:\.[0-9]+)?)\s*([a-zA-Z]*)", s)
    if not m:
        return None
    factor = _QTY_FACTORS.get(m.group(2))
    if factor is None:
        return None
    try:
        return Decimal(m.group(1)) * factor
    except InvalidOperation:
        return None


def container_has_guaranteed_qos(container: dict[str, Any]) -> bool:
    res = container.get("resources") or {}
    if not isinstance(res, dict):
        return False
    req = res.get("requests") or {}
    lim = res.get("limits") or {}
    if not isinstance(req, dict) or not isinstance(lim, dict):
        return False
    for key in ("cpu", "memory"):
        rv = parse_k8s_qty(req.get(key))
        lv = parse_k8s_qty(lim.get(key))
        if rv is None or lv is None or rv <= 0 or rv != lv:
            return False
    return True


# ---------------------------------------------------------------------------
# Tier 1 Checks (T1-01 .. T1-09)
# ---------------------------------------------------------------------------

def check_t1_01(repo: Path, **_kwargs: Any) -> list[dict[str, Any]]:
    tpl = repo / "learner-work" / "EVIDENCE_TEMPLATE.md"
    if not tpl.is_file():
        return [make_result("T1-01", "1", "FAIL", "learner-work/EVIDENCE_TEMPLATE.md missing")]
    text = tpl.read_text(encoding="utf-8")
    if not text.strip():
        return [make_result("T1-01", "1", "FAIL", "learner-work/EVIDENCE_TEMPLATE.md is empty")]
    low = text.lower()
    missing_sections: list[str] = []
    if "symptom" not in low:
        missing_sections.append("Symptom")
    if "command output" not in low and "evidence ladder" not in low:
        missing_sections.append("Command Output / Evidence Ladder")
    if "root cause" not in low:
        missing_sections.append("Root Cause")
    if "fix" not in low:
        missing_sections.append("Fix")
    if "takeaway" not in low:
        missing_sections.append("Takeaway")

    ignore_failures: list[str] = []
    unignored_targets = ["learner-work/EVIDENCE_TEMPLATE.md"]
    for st in (1, 3, 4, 5, 6, 7):
        unignored_targets.extend([
            f"learner-work/stage{st}/README.md",
            f"learner-work/stage{st}/check.sh",
            f"learner-work/stage{st}/starter/probe.yaml",
            f"learner-work/stage{st}/solution/probe.yaml",
        ])
    for rel in unignored_targets:
        res = run_cmd(["git", "-C", str(repo), "check-ignore", "-q", rel])
        if res.returncode == 0:
            ignore_failures.append(f"{rel} is git-ignored (expected tracked/un-ignored)")

    for st in (1, 3, 4, 5, 6, 7):
        work_rel = f"learner-work/stage{st}/work/test.md"
        res = run_cmd(["git", "-C", str(repo), "check-ignore", "-q", work_rel])
        if res.returncode != 0:
            ignore_failures.append(f"{work_rel} is NOT git-ignored (expected ignored)")

    problems = []
    if missing_sections:
        problems.append("missing sections: " + ", ".join(missing_sections))
    if ignore_failures:
        problems.append("gitignore issues: " + "; ".join(ignore_failures[:5]))
    if problems:
        return [make_result("T1-01", "1", "FAIL", "EVIDENCE_TEMPLATE / .gitignore check failed", " | ".join(problems))]
    return [make_result("T1-01", "1", "PASS", "EVIDENCE_TEMPLATE.md 5-rung structure & .gitignore verified")]


def check_t1_02(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    target_stages = [1, 3, 4, 5, 6, 7]
    if stages is not None:
        target_stages = [s for s in target_stages if s in stages]
        if not target_stages:
            return []

    failures: list[str] = []
    checked: list[str] = []
    has_shellcheck = have_tool("shellcheck")

    for st in target_stages:
        sdir = repo / "learner-work" / f"stage{st}"
        readme = sdir / "README.md"
        check_sh = sdir / "check.sh"
        starter = sdir / "starter"
        solution = sdir / "solution"

        if not sdir.is_dir():
            failures.append(f"stage{st}: directory learner-work/stage{st}/ missing")
            continue
        for req_f in (readme, check_sh):
            if not req_f.is_file() or not req_f.read_text(encoding="utf-8").strip():
                failures.append(f"stage{st}: {req_f.name} missing or empty")
        starter_files = [p for p in starter.rglob("*") if p.is_file()] if starter.is_dir() else []
        sol_files = [p for p in solution.rglob("*") if p.is_file()] if solution.is_dir() else []
        if not starter_files:
            failures.append(f"stage{st}: starter/ missing or has no files")
        if not sol_files:
            failures.append(f"stage{st}: solution/ missing or has no files")
        if not check_sh.is_file() or not starter_files or not sol_files:
            continue

        bn = run_cmd(["bash", "-n", str(check_sh)])
        if bn.returncode != 0:
            failures.append(f"stage{st}: bash -n failed: {bn.stderr.strip()}")
        if has_shellcheck:
            sc = run_cmd(["shellcheck", "-S", "warning", str(check_sh)])
            if sc.returncode != 0:
                failures.append(f"stage{st}: shellcheck failed: {sc.stdout.strip() or sc.stderr.strip()}")

        with tempfile.TemporaryDirectory(prefix=f"apollo-lw-s{st}-") as td:
            tpath = Path(td)
            for item in ("README.md", "check.sh", "starter", "solution"):
                src = sdir / item
                dst = tpath / item
                if src.is_dir():
                    shutil.copytree(src, dst)
                elif src.is_file():
                    shutil.copy2(src, dst)

            res_sol = run_cmd(["bash", str(tpath / "check.sh"), "--solution"], cwd=tpath)
            if res_sol.returncode != 0:
                failures.append(
                    f"stage{st}: check.sh --solution exited {res_sol.returncode}: "
                    f"{(res_sol.stdout + res_sol.stderr).strip()[:300]}"
                )

            # Negative check against starter/ (supports either `check.sh <dir>` or default `work/` dir)
            res_arg = run_cmd(["bash", str(tpath / "check.sh"), str(tpath / "starter")], cwd=tpath)
            if res_arg.returncode == 0:
                failures.append(f"stage{st}: check.sh starter/ unexpectedly exited 0")
            else:
                # Also verify via work/ directory in case check.sh rejects dir args with usage error
                work_dir = tpath / "work"
                if work_dir.exists():
                    shutil.rmtree(work_dir)
                shutil.copytree(tpath / "starter", work_dir)
                res_work_starter = run_cmd(["bash", str(tpath / "check.sh")], cwd=tpath)
                if res_work_starter.returncode == 0:
                    failures.append(f"stage{st}: check.sh on work/ copy of starter/ unexpectedly exited 0")

                shutil.rmtree(work_dir)
                shutil.copytree(tpath / "solution", work_dir)
                res_work_sol = run_cmd(["bash", str(tpath / "check.sh")], cwd=tpath)
                if res_work_sol.returncode != 0:
                    failures.append(
                        f"stage{st}: check.sh on work/ copy of solution/ exited {res_work_sol.returncode}"
                    )

        # Check starter/ vs solution/ differ
        starter_map = {
            str(p.relative_to(starter)): p.read_text(encoding="utf-8", errors="ignore").strip()
            for p in starter_files
        }
        sol_map = {
            str(p.relative_to(solution)): p.read_text(encoding="utf-8", errors="ignore").strip()
            for p in sol_files
        }
        if starter_map == sol_map:
            failures.append(f"stage{st}: starter/ and solution/ files are identical")

        # Opaque-box solution content checks
        sol_blob = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in sol_files)
        sol_low = sol_blob.lower()
        if st == 1:
            for tok in ("deployment", "service", "configmap", "booking"):
                if tok not in sol_low:
                    failures.append(f"stage1 solution missing '{tok}'")
            if re.search(r"nodeport|3008[0-4]", sol_low):
                failures.append("stage1 solution references NodePort or 30080-30084")
        elif st == 3:
            if "statefulset" not in sol_low:
                failures.append("stage3 solution missing StatefulSet")
            if "volumeclaimtemplates" not in sol_low:
                failures.append("stage3 solution missing volumeClaimTemplates")
            if not re.search(r"clusterip:\s*['\"]?none['\"]?", sol_low):
                failures.append("stage3 solution missing headless Service (clusterIP: None)")
        elif st == 4:
            for tok in ("startupprobe", "readinessprobe", "livenessprobe", "prestop", "poddisruptionbudget", "booking"):
                if tok not in sol_low:
                    failures.append(f"stage4 solution missing '{tok}'")
            s4_yamls = [p for p in sol_files if p.suffix in (".yaml", ".yml")]
            s4_docs, s4_errs = load_yaml_docs(s4_yamls)
            failures.extend(s4_errs)
            s4_workloads = [d for _p, d in s4_docs if d.get("kind") in ("Deployment", "StatefulSet", "Pod")]
            if not s4_workloads:
                failures.append("stage4 solution missing Deployment/StatefulSet YAML")
            for wl in s4_workloads:
                containers, _inits = extract_containers(wl)
                for c in containers:
                    if not container_has_guaranteed_qos(c):
                        failures.append(
                            f"stage4 solution container '{c.get('name')}' lacks Guaranteed QoS (requests == limits for cpu & memory)"
                        )
        elif st == 5:
            has_schema = any("schema" in p.name.lower() for p in sol_files) or "values.schema.json" in sol_low
            has_helm = any(p.suffix in (".tpl", ".yaml", ".yml") for p in sol_files) and (
                "define" in sol_low or "values" in sol_low or "_helpers" in sol_low
            )
            has_kust = "kustomization" in sol_low or "patch" in sol_low or "strategic" in sol_low
            if not (has_schema and has_helm and has_kust):
                failures.append("stage5 solution missing schema, Helm value/helper, or Kustomize patch artifact")
            for jp in [p for p in sol_files if p.suffix == ".json"]:
                try:
                    json.loads(jp.read_text(encoding="utf-8"))
                except (OSError, json.JSONDecodeError) as exc:
                    failures.append(f"stage5 solution invalid JSON {jp.name}: {exc}")
        elif st == 6:
            if "servicemonitor" not in sol_low:
                failures.append("stage6 solution missing ServiceMonitor")
            if "prometheusrule" not in sol_low:
                failures.append("stage6 solution missing PrometheusRule")
            if not any(tok in sol_low for tok in ("rule_files", "promql_expr_test", "alert_rule_test")):
                failures.append("stage6 solution missing promtool unit test")
            elif have_tool("promtool"):
                test_candidates = [
                    p for p in sol_files
                    if p.suffix in (".yaml", ".yml") and "rule_files" in p.read_text(encoding="utf-8", errors="ignore")
                ]
                if not test_candidates:
                    failures.append("stage6 solution missing promtool test YAML with rule_files")
                else:
                    with tempfile.TemporaryDirectory(prefix="apollo-lw-s6-prom-") as ptd:
                        ptpath = Path(ptd)
                        shutil.copytree(solution, ptpath / "solution")
                        for tc in test_candidates:
                            rel_tc = tc.relative_to(solution)
                            pt_res = run_cmd(["promtool", "test", "rules", str(ptpath / "solution" / rel_tc)], cwd=ptpath / "solution")
                            if pt_res.returncode != 0:
                                failures.append(
                                    f"stage6 solution promtool test rules {rel_tc} failed: "
                                    f"{(pt_res.stdout + pt_res.stderr).strip()[:300]}"
                                )
        elif st == 7:
            if "horizontalpodautoscaler" not in sol_low or "search" not in sol_low:
                failures.append("stage7 solution missing HorizontalPodAutoscaler targeting search")
            lw7_blob = (
                readme.read_text(encoding="utf-8", errors="ignore")
                + "\n"
                + check_sh.read_text(encoding="utf-8", errors="ignore")
            ).lower()
            if "kubectl top" not in lw7_blob:
                failures.append("stage7 learner-work README.md/check.sh missing 'kubectl top' validation")

        checked.append(f"stage{st}")

    if failures:
        return [make_result("T1-02", "1", "FAIL", f"learner-work checks failed ({len(failures)} issues)", "\n".join(failures))]
    return [make_result("T1-02", "1", "PASS", f"learner-work stages {', '.join(checked)} verified (--solution=0, starter!=0)")]


def check_t1_03(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    target_stages = [2, 6, 7, 8, 9]
    if stages is not None:
        target_stages = [s for s in target_stages if s in stages]
        if not target_stages:
            return []

    failures: list[str] = []
    for st in target_stages:
        readme = repo / "stages" / f"stage{st}" / "README.md"
        if not readme.is_file():
            failures.append(f"stage{st}: README.md missing")
            continue
        lines = readme.read_text(encoding="utf-8").splitlines()
        heading_idx = None
        for idx, line in enumerate(lines):
            if re.match(r"^##\s+Explain\b", line.strip(), re.IGNORECASE):
                heading_idx = idx
                break
        if heading_idx is None:
            failures.append(f"stage{st}: missing '## Explain' heading")
            continue
        body_lines = []
        for line in lines[heading_idx + 1:]:
            s = line.strip()
            if re.match(r"^##\s+", s):
                break
            if not s or re.fullmatch(r"[-*_]{3,}", s) or s.startswith("#"):
                continue
            body_lines.append(s)
        if len(body_lines) < 2:
            failures.append(f"stage{st}: '## Explain' section has <2 non-empty content lines")

    if failures:
        return [make_result("T1-03", "1", "FAIL", "Uniform '## Explain' check failed", "; ".join(failures))]
    return [make_result("T1-03", "1", "PASS", f"Uniform '## Explain' blocks verified for stages {target_stages}")]


def check_t1_04(repo: Path, stages: list[int] | None, include_global: bool, **_kwargs: Any) -> list[dict[str, Any]]:
    failures: list[str] = []
    https_doc = repo / "docs" / "local-https.md"
    ci_doc = repo / "docs" / "ci-images.md"

    check_global = stages is None or include_global
    shared_lines_sets: list[tuple[str, list[str]]] = []

    for doc_path, req_tokens in (
        (https_doc, ("apollo-tls-secret", "apollo-edge-tls", "generate-certs.sh", "curl --cacert", "mkcert")),
        (ci_doc, ("ghcr.io", "build-images.sh", "trivy", "10001", "101")),
    ):
        if not doc_path.is_file():
            if check_global:
                failures.append(f"missing {doc_path.relative_to(repo)}")
            continue
        content = doc_path.read_text(encoding="utf-8")
        if check_global:
            for tok in req_tokens:
                if tok not in content:
                    failures.append(f"{doc_path.relative_to(repo)} missing '{tok}'")
        shared_lines_sets.append((str(doc_path.relative_to(repo)), normalize_lines(content)))

    target_stages = [3, 4, 5, 6, 7]
    if stages is not None:
        target_stages = [s for s in target_stages if s in stages]

    if not check_global and not target_stages:
        return []

    for st in target_stages:
        readme = repo / "stages" / f"stage{st}" / "README.md"
        if not readme.is_file():
            failures.append(f"stages/stage{st}/README.md missing")
            continue
        text = readme.read_text(encoding="utf-8")
        if not re.search(r"docs/local-https\.md", text):
            failures.append(f"stages/stage{st}/README.md missing link to docs/local-https.md")
        if not re.search(r"docs/ci-images\.md", text):
            failures.append(f"stages/stage{st}/README.md missing link to docs/ci-images.md")

        joined_norm = " ".join(text.splitlines())
        if re.search(r"openssl\s+req\s+-x509.*-newkey\s+rsa:2048", joined_norm):
            failures.append(f"stages/stage{st}/README.md duplicates inline openssl cert-gen recipe")
        if "mkcert -cert-file" in text:
            failures.append(f"stages/stage{st}/README.md duplicates inline mkcert recipe")
        if re.search(r"base64\s+-d\s*>\s*/tmp/apollo-ca\.crt", text):
            failures.append(f"stages/stage{st}/README.md duplicates inline /tmp/apollo-ca.crt extraction recipe")

        stage_lines = normalize_lines(text)
        window = 8
        for shared_name, shared_lines in shared_lines_sets:
            if len(shared_lines) < window or len(stage_lines) < window:
                continue
            shared_windows = {
                tuple(shared_lines[i:i + window])
                for i in range(len(shared_lines) - window + 1)
            }
            for i in range(len(stage_lines) - window + 1):
                if tuple(stage_lines[i:i + window]) in shared_windows:
                    failures.append(
                        f"stages/stage{st}/README.md duplicates >= {window} consecutive lines from {shared_name}"
                    )
                    break

    if failures:
        return [make_result("T1-04", "1", "FAIL", "Shared docs / deduplication check failed", "; ".join(failures))]
    return [make_result("T1-04", "1", "PASS", "Shared docs (local-https.md, ci-images.md) & deduplication verified")]


def check_t1_05(repo: Path, **_kwargs: Any) -> list[dict[str, Any]]:
    readme = repo / "README.md"
    if not readme.is_file():
        return [make_result("T1-05", "1", "FAIL", "Root README.md missing")]
    text = readme.read_text(encoding="utf-8")
    low = text.lower()
    failures: list[str] = []

    required_rows = ["launchpad", "ignition"] + [f"stage {i}" for i in range(1, 10)]
    for row in required_rows:
        if row not in low:
            failures.append(f"matrix missing row for '{row}'")
    for col in ("ram", "cpu", "kind-apollo11-dev"):
        if col not in low:
            failures.append(f"matrix missing '{col}'")
    if not re.search(r"est\.\s*time|\btime\b", low):
        failures.append("matrix missing time column")

    if "macos" not in low or "wsl2" not in low:
        failures.append("missing macOS/WSL2 fallback section")
    if "kubectl port-forward" not in low:
        failures.append("macOS/WSL2 fallback missing 'kubectl port-forward'")
    if "cloud-provider-kind" not in low:
        failures.append("macOS/WSL2 fallback missing 'cloud-provider-kind'")

    if failures:
        return [make_result("T1-05", "1", "FAIL", "Root README.md matrix/OS fallback check failed", "; ".join(failures))]
    return [make_result("T1-05", "1", "PASS", "Root README.md compatibility matrix & macOS/WSL2 fallback verified")]


def check_t1_06(repo: Path, stages: list[int] | None, include_global: bool, **_kwargs: Any) -> list[dict[str, Any]]:
    failures: list[str] = []
    check_global = stages is None or include_global

    if check_global:
        maint = repo / "docs" / "maintainers"
        for req in ("GAPS_TRACKER.md", "AUDIT_GAPS_AND_EXPANSIONS.md", "DOCS_IMPROVEMENT_REPORT.md", "verification-runs"):
            if not (maint / req).exists():
                failures.append(f"docs/maintainers/{req} missing")
        for forbidden_root in (
            "GAPS_TRACKER.md",
            "AUDIT_GAPS_AND_EXPANSIONS.md",
            "DOCS_IMPROVEMENT_REPORT.md",
            "handoff.md",
            ".handoff.md",
            "verification-runs",
            "core.65318",
            "stages/stage7/.handoff.md",
        ):
            if (repo / forbidden_root).exists():
                failures.append(f"stale maintainer/dump path still exists: {forbidden_root}")

    if stages is not None:
        specs = [f"stages/stage{s}/**/*.md" for s in stages] + [f"stages/stage{s}/*.md" for s in stages]
        md_files = git_files(repo, *specs)
    else:
        md_files = git_files(repo, "stages/*.md", "stages/**/*.md")

    tracker_hits: list[str] = []
    for p in md_files:
        rel = str(p.relative_to(repo))
        try:
            lines = p.read_text(encoding="utf-8").splitlines()
        except OSError as exc:
            failures.append(f"{rel}: read error: {exc}")
            continue
        for lineno, line in enumerate(lines, start=1):
            m1 = TRACKER_ID_RE.search(line)
            m2 = TRACKER_META_RE.search(line)
            if m1 or m2:
                tok = (m1 or m2).group(0)
                tracker_hits.append(f"{rel}:{lineno}: '{tok}'")

    if tracker_hits:
        failures.append("tracker references in learner markdowns: " + ", ".join(tracker_hits[:10]))

    if failures:
        return [make_result("T1-06", "1", "FAIL", "Maintainer hygiene / tracker-ID strip failed", " | ".join(failures))]
    return [make_result("T1-06", "1", "PASS", f"Maintainer docs hygiene & zero tracker IDs verified ({len(md_files)} markdowns scanned)")]


def check_t1_07(repo: Path, stages: list[int] | None, include_global: bool, **_kwargs: Any) -> list[dict[str, Any]]:
    failures: list[str] = []
    check_global = stages is None or include_global

    if check_global:
        ls = run_cmd(["git", "-C", str(repo), "ls-files"])
        if ls.returncode == 0:
            dist_hits = [line for line in ls.stdout.splitlines() if re.search(r"(^|/)dist/", line)]
            if dist_hits:
                failures.append(f"tracked dist/ artifacts found: {', '.join(dist_hits[:5])}")

    if check_global or (stages is not None and 10 in stages):
        s10 = repo / "stages" / "stage10"
        if not s10.is_dir():
            failures.append("stages/stage10/ missing")
        else:
            entries = sorted(p.name for p in s10.iterdir())
            unexpected = [e for e in entries if e not in ("README.md", "missions")]
            if unexpected:
                failures.append(f"stages/stage10/ has unexpected entries: {', '.join(unexpected)}")
            for legacy in ("code", "k8s", "terraform", "scripts"):
                if (s10 / legacy).exists():
                    failures.append(f"stages/stage10/{legacy} legacy dir still present")

    if check_global or (stages is not None and 11 in stages):
        s11 = repo / "stages" / "stage11"
        if not s11.is_dir():
            failures.append("stages/stage11/ missing")
        else:
            entries = sorted(p.name for p in s11.iterdir())
            if entries != ["README.md"]:
                failures.append(f"stages/stage11/ expected only ['README.md'], got {entries}")

    if check_global or (stages is not None and 9 in stages):
        s9 = repo / "stages" / "stage9"
        for legacy in ("code", "k8s"):
            if (s9 / legacy).exists():
                failures.append(f"legacy library-era stages/stage9/{legacy} still exists")
        for tf in git_files(repo, "stages/stage9/**/*.tf", "stages/stage9/*.tf"):
            txt = tf.read_text(encoding="utf-8", errors="ignore")
            if re.search(r"\b(azurerm|google_container_cluster)\b", txt):
                failures.append(f"{tf.relative_to(repo)} contains non-EKS azurerm/google_container_cluster block")

    if not check_global and stages is not None and not any(s in stages for s in (9, 10, 11)):
        return []

    if failures:
        return [make_result("T1-07", "1", "FAIL", "Legacy cleanup / dist hygiene failed", "; ".join(failures))]
    return [make_result("T1-07", "1", "PASS", "Zero tracked dist/ & legacy Stage 9/10/11 cleanup verified")]


def check_t1_08(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and not any(s in stages for s in (4, 5, 6, 7)):
        return []

    failures: list[str] = []
    roadmap = repo / "ROADMAP.md"
    if not roadmap.is_file():
        return [make_result("T1-08", "1", "FAIL", "ROADMAP.md missing")]
    rm_text = roadmap.read_text(encoding="utf-8")
    rm_low = rm_text.lower()

    for tok in ("priorityclass", "taint", "affinity", "topology spread", "limitrange", "resourcequota"):
        if tok not in rm_low:
            failures.append(f"ROADMAP.md missing '{tok}'")
    if not re.search(r"scheduling.*stage\s*4|moves to stage\s*4", rm_low):
        failures.append("ROADMAP.md does not state scheduling moves to Stage 4")
    if "helm-only" not in rm_low or "--mode helm|kustomize" not in rm_low.replace("\\|", "|"):
        failures.append("ROADMAP.md missing Kustomize '--mode helm|kustomize' / Stage 8+ Helm-only contract")
    if "substage 5b" not in rm_low or "optional" not in rm_low:
        failures.append("ROADMAP.md missing Stage 5 optional Argo CD Substage 5B contract")

    if stages is None or 4 in stages:
        s4 = repo / "stages" / "stage4" / "README.md"
        if not s4.is_file():
            failures.append("stages/stage4/README.md missing")
        else:
            s4_low = s4.read_text(encoding="utf-8").lower()
            for tok in ("priorityclass", "affinity", "limitrange", "resourcequota"):
                if tok not in s4_low:
                    failures.append(f"stage4/README.md missing '{tok}'")
            if "taint" not in s4_low and "toleration" not in s4_low:
                failures.append("stage4/README.md missing taint/toleration")
            if "topologyspread" not in s4_low and "topology spread" not in s4_low:
                failures.append("stage4/README.md missing topologySpread")

    if stages is None or 7 in stages:
        s7 = repo / "stages" / "stage7" / "README.md"
        if not s7.is_file():
            failures.append("stages/stage7/README.md missing")
        else:
            s7_lines = s7.read_text(encoding="utf-8").splitlines()
            s7_low = "\n".join(s7_lines).lower()
            current_heading = ""
            for lineno, line in enumerate(s7_lines, start=1):
                if re.match(r"^#{2,4}\s+", line):
                    current_heading = line.lower()
                window = "\n".join(s7_lines[max(0, lineno - 4):min(len(s7_lines), lineno + 3)]).lower()
                if re.match(r"^#{2,3}\s+.*\b(scheduling|tolerations?|affinity|topology\s+spread|priorityclass)\b", line, re.IGNORECASE):
                    if "stage 4" not in window:
                        failures.append(f"stage7/README.md:{lineno}: has scheduling heading '{line.strip()}'")
                if re.search(r"\b(priorityclass|topologyspreadconstraints)\b", line, re.IGNORECASE):
                    if "stage 4" not in window and "stage 4" not in current_heading:
                        failures.append(
                            f"stage7/README.md:{lineno}: teaches scheduling resource without referencing Stage 4"
                        )
            for tok in ("redis", "k6", "hpa", "--with-vpa"):
                if tok not in s7_low:
                    failures.append(f"stage7/README.md missing '{tok}'")

    if stages is None or 5 in stages:
        s5 = repo / "stages" / "stage5" / "README.md"
        if not s5.is_file():
            failures.append("stages/stage5/README.md missing")
        else:
            s5_low = s5.read_text(encoding="utf-8").lower()
            if "optional" not in s5_low or "argocd" not in s5_low.replace(" ", ""):
                failures.append("stage5/README.md missing optional Argo CD track documentation")
            if "substage 5b" not in s5_low and "promot" not in s5_low:
                failures.append("stage5/README.md missing Substage 5B / dev-to-staging promotion documentation")
            if "staging" not in s5_low or "dev" not in s5_low:
                failures.append("stage5/README.md missing dev-to-staging promotion documentation")
            argo_docs = [
                repo / "stages" / "stage5" / "argocd" / "README.md",
                repo / "stages" / "stage5" / "argocd" / "DEMO.md",
            ]
            argo_blob = "\n".join(p.read_text(encoding="utf-8", errors="ignore").lower() for p in argo_docs if p.is_file())
            if not argo_blob or "dev" not in argo_blob or "staging" not in argo_blob or "promot" not in argo_blob:
                failures.append("stage5/argocd/{README.md,DEMO.md} missing dev-to-staging promotion lab")

    for st in (5, 6, 7):
        if stages is not None and st not in stages:
            continue
        readme = repo / "stages" / f"stage{st}" / "README.md"
        if readme.is_file():
            txt = readme.read_text(encoding="utf-8").lower().replace("\\|", "|")
            if "kustomize" not in txt or "helm" not in txt:
                failures.append(f"stage{st}/README.md missing Helm/Kustomize dual-mode documentation")
            if "--mode helm|kustomize" not in txt and not ("generated.yaml" in txt and "overlays/" in txt):
                failures.append(f"stage{st}/README.md missing '--mode helm|kustomize' or generated.yaml/overlays/ alignment")

    if failures:
        return [make_result("T1-08", "1", "FAIL", "ROADMAP / Stages 4-7 consistency check failed", "; ".join(failures))]
    return [make_result("T1-08", "1", "PASS", "ROADMAP.md & Stages 4-7 scheduling/Kustomize/ArgoCD consistency verified")]


def check_t1_09(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 1 not in stages:
        return []
    yaml_paths = git_files(repo, "stages/stage1/*.yaml", "stages/stage1/*.yml", "stages/stage1/**/*.yaml", "stages/stage1/**/*.yml")
    docs, parse_errs = load_yaml_docs(yaml_paths)
    failures = list(parse_errs)

    svc_count = 0
    for p, doc in docs:
        if doc.get("kind") != "Service":
            continue
        svc_count += 1
        rel = p.relative_to(repo)
        spec = doc.get("spec") or {}
        if isinstance(spec, dict):
            if spec.get("type") == "NodePort":
                failures.append(f"{rel}: Service {(doc.get('metadata') or {}).get('name')} has type NodePort")
            for port in spec.get("ports") or []:
                if isinstance(port, dict) and port.get("nodePort") is not None:
                    failures.append(f"{rel}: Service defines nodePort={port.get('nodePort')}")

    if svc_count == 0:
        failures.append("no Service manifests found in stages/stage1/")

    for sh in git_files(repo, "stages/stage1/**/*.sh", "stages/stage1/*.sh"):
        txt = sh.read_text(encoding="utf-8", errors="ignore")
        for lineno, line in enumerate(txt.splitlines(), start=1):
            if re.search(r"\b3008[0-4]\b|type[=:]\s*NodePort", line):
                failures.append(f"{sh.relative_to(repo)}:{lineno}: references NodePort or 30080-30084")

    s1_readme = repo / "stages" / "stage1" / "README.md"
    if not s1_readme.is_file():
        failures.append("stages/stage1/README.md missing")
    else:
        rtxt = s1_readme.read_text(encoding="utf-8")
        rlow = rtxt.lower()
        for lineno, line in enumerate(rtxt.splitlines(), start=1):
            if re.search(r"\b3008[0-4]\b|type[=:]\s*NodePort|exposes?\s+NodePort", line, re.IGNORECASE):
                failures.append(f"stages/stage1/README.md:{lineno}: references NodePort or 30080-30084")
        if "kubectl port-forward" not in rlow:
            failures.append("stages/stage1/README.md missing 'kubectl port-forward'")
        for tok in ("configmap", "secret", "rollout restart", "backofflimit"):
            if tok not in rlow:
                failures.append(f"stages/stage1/README.md missing F16 lab token '{tok}'")

    s1_verify = repo / "stages" / "stage1" / "scripts" / "verify.sh"
    if not s1_verify.is_file():
        failures.append("stages/stage1/scripts/verify.sh missing")
    else:
        vlow = s1_verify.read_text(encoding="utf-8", errors="ignore").lower()
        if "env-demo" not in vlow and "configmap" not in vlow:
            failures.append("stages/stage1/scripts/verify.sh missing env mutation lab check")
        if "backofflimit" not in vlow:
            failures.append("stages/stage1/scripts/verify.sh missing Job backoffLimit lab check")

    if failures:
        return [make_result("T1-09", "1", "FAIL", "Stage 1 ClusterIP-only & F16 lab check failed", "; ".join(failures))]
    return [make_result("T1-09", "1", "PASS", f"Stage 1 ClusterIP-only ({svc_count} Services, zero NodePorts) & F16 labs verified")]


def _parse_fault_ids(output: str) -> list[str]:
    ids: list[str] = []
    for raw in output.splitlines():
        line = raw.strip()
        if not line:
            continue
        low = line.lower()
        if low.startswith(("available ", "usage:", "options:", "actions:", "commands:")):
            continue
        line = re.sub(r"^[-*•]\s+", "", line)
        tok = re.split(r"[\s:]+", line, maxsplit=1)[0].strip()
        if tok and re.fullmatch(r"[a-z0-9][a-z0-9._-]{1,64}", tok):
            if tok not in ids:
                ids.append(tok)
    return ids


def check_t1_10(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    target_stages = [2, 4, 6]
    if stages is not None:
        target_stages = [s for s in target_stages if s in stages]
        if not target_stages:
            return []

    failures: list[str] = []
    verified: list[str] = []
    has_shellcheck = have_tool("shellcheck")

    for st in target_stages:
        drill = repo / "stages" / f"stage{st}" / "scripts" / "fault-drill.sh"
        readme = repo / "stages" / f"stage{st}" / "README.md"
        if not drill.is_file():
            failures.append(f"stage{st}: stages/stage{st}/scripts/fault-drill.sh missing")
            continue

        bn = run_cmd(["bash", "-n", str(drill)])
        if bn.returncode != 0:
            failures.append(f"stage{st}: fault-drill.sh bash -n failed: {bn.stderr.strip()}")
        if has_shellcheck:
            sc = run_cmd(["shellcheck", "-S", "warning", str(drill)])
            if sc.returncode != 0:
                failures.append(f"stage{st}: fault-drill.sh shellcheck failed: {sc.stdout.strip() or sc.stderr.strip()}")

        if not readme.is_file() or "fault-drill.sh" not in readme.read_text(encoding="utf-8", errors="ignore"):
            failures.append(f"stage{st}: stages/stage{st}/README.md does not reference fault-drill.sh")

        with tempfile.TemporaryDirectory(prefix=f"apollo-t1-10-s{st}-") as td:
            tdir = Path(td)
            call_log = tdir / "calls"
            fake_home = tdir / "home"
            fake_home.mkdir()

            kubectl_shim = tdir / "kubectl"
            kubectl_shim.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "echo \"kubectl $*\" >> \"$CALL_LOG\"\n"
                "if [[ \"${SHIM_MODE:-deny}\" == \"deny\" ]]; then\n"
                "  if [[ \"$*\" == \"config current-context\" ]]; then echo \"$FAKE_CONTEXT\"; exit 0; fi\n"
                "  exit 97\n"
                "fi\n"
                "if [[ \"$*\" == *\"-o jsonpath=\"* ]]; then\n"
                "  if [[ \"$*\" == *\"readyReplicas\"* ]]; then echo '0'; exit 0; fi\n"
                "  if [[ \"$*\" == *\"restartCount\"* ]]; then echo '1'; exit 0; fi\n"
                "  if [[ \"$*\" == *\".status.phase\"* ]]; then echo 'Pending'; exit 0; fi\n"
                "  if [[ \"$*\" == *\"get nodes\"* ]]; then echo 'apollo11-worker'; exit 0; fi\n"
                "  echo '127.0.0.1'; exit 0\n"
                "fi\n"
                "if [[ \"$*\" == *\"-o json\"* ]]; then echo '{}'; exit 0; fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            kubectl_shim.chmod(0o755)

            helm_shim = tdir / "helm"
            helm_shim.write_text(
                "#!/usr/bin/env bash\n"
                "set -euo pipefail\n"
                "echo \"helm $*\" >> \"$CALL_LOG\"\n"
                "if [[ \"${SHIM_MODE:-deny}\" == \"deny\" ]]; then exit 97; fi\n"
                "exit 0\n",
                encoding="utf-8",
            )
            helm_shim.chmod(0o755)

            base_env = dict(
                os.environ,
                PATH=f"{tdir}:{os.environ['PATH']}",
                HOME=str(fake_home),
                CALL_LOG=str(call_log),
                FAKE_CONTEXT="arn:aws:eks:unsafe",
                SHIM_MODE="deny",
            )
            base_env.pop("KUBE_CONTEXT", None)

            # 1. --help
            call_log.unlink(missing_ok=True)
            h_res = run_cmd(["bash", str(drill), "--help"], env=base_env)
            h_txt = h_res.stdout + h_res.stderr
            if h_res.returncode != 0:
                failures.append(f"stage{st}: fault-drill.sh --help exited {h_res.returncode}")
            if call_log.exists() and call_log.read_text(encoding="utf-8").strip():
                failures.append(f"stage{st}: fault-drill.sh --help invoked kubectl/helm")
            for flag in ("--list", "--inject", "--inject-id", "--verify", "--restore"):
                if flag not in h_txt:
                    failures.append(f"stage{st}: fault-drill.sh --help missing {flag}")

            # 2. --list
            call_log.unlink(missing_ok=True)
            l_res = run_cmd(["bash", str(drill), "--list"], env=base_env)
            if l_res.returncode != 0:
                failures.append(f"stage{st}: fault-drill.sh --list exited {l_res.returncode}")
            if call_log.exists() and call_log.read_text(encoding="utf-8").strip():
                failures.append(f"stage{st}: fault-drill.sh --list invoked kubectl/helm")
            fault_ids = _parse_fault_ids(l_res.stdout)
            if not fault_ids:
                failures.append(f"stage{st}: fault-drill.sh --list returned zero fault IDs")

            # 3. Unsafe context refusal
            call_log.unlink(missing_ok=True)
            u_res = run_cmd(["bash", str(drill), "--inject", "--context", "arn:aws:eks:unsafe"], env=base_env)
            if u_res.returncode == 0:
                failures.append(f"stage{st}: fault-drill.sh accepted unsafe context arn:aws:eks:unsafe")
            if call_log.exists():
                for line in call_log.read_text(encoding="utf-8").splitlines():
                    if any(mut in line for mut in ("delete", "apply", "patch", "scale", "taint", "cordon", "install", "upgrade", "uninstall")):
                        failures.append(f"stage{st}: fault-drill.sh made mutating call on unsafe context: {line}")

            # 4. --inject diagnostic guidance without root-cause spoiler leak
            if fault_ids:
                inject_env = dict(base_env, SHIM_MODE="mock_inject")
                tmp_root = Path(tempfile.gettempdir())
                before_tmp = {p for p in tmp_root.glob(f".apollo11-stage{st}-fault-drill-*")}
                try:
                    call_log.unlink(missing_ok=True)
                    i_res = run_cmd(
                        ["bash", str(drill), "--inject-id", fault_ids[0], "--context", "kind-apollo11"],
                        env=inject_env,
                        timeout=30,
                    )
                    i_out = i_res.stdout + i_res.stderr
                    if i_res.returncode != 0:
                        failures.append(
                            f"stage{st}: fault-drill.sh --inject-id {fault_ids[0]} exited {i_res.returncode}: {i_out.strip()[:250]}"
                        )
                    else:
                        i_low = i_out.lower()
                        guidance_tokens = ("rung", "status", "events", "describe", "logs", "prometheus", "grafana", "ladder")
                        if not any(tok in i_low for tok in guidance_tokens):
                            failures.append(f"stage{st}: fault-drill.sh --inject output missing diagnostic ladder/guidance")
                        leak = re.search(r"(?i)\b(?:root\s+cause|solution|answer)\s*:", i_out)
                        if leak:
                            failures.append(f"stage{st}: fault-drill.sh --inject output leaks '{leak.group(0)}'")
                finally:
                    after_tmp = {p for p in tmp_root.glob(f".apollo11-stage{st}-fault-drill-*")}
                    for created in after_tmp - before_tmp:
                        if created.is_dir():
                            shutil.rmtree(created, ignore_errors=True)
                        else:
                            created.unlink(missing_ok=True)

        verified.append(f"stage{st}")

    if failures:
        return [make_result("T1-10", "1", "FAIL", f"Blind troubleshooting fault-drill.sh checks failed ({len(failures)} issues)", "\n".join(failures))]
    return [make_result("T1-10", "1", "PASS", f"Blind troubleshooting fault-drill.sh verified for {', '.join(verified)}")]


# ---------------------------------------------------------------------------
# Tier 2 Checks (T2-01 .. T2-06)
# ---------------------------------------------------------------------------

def check_t2_01(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 3 not in stages:
        return []
    yaml_paths = git_files(repo, "stages/stage3/**/*.yaml", "stages/stage3/**/*.yml", "stages/stage3/*.yaml", "stages/stage3/*.yml")
    docs, failures = load_yaml_docs(yaml_paths)

    valid_cronjobs = 0
    working_inits = 0
    for p, doc in docs:
        kind = doc.get("kind")
        rel = p.relative_to(repo)
        if kind == "CronJob":
            spec = doc.get("spec") or {}
            schedule = spec.get("schedule")
            jt = (spec.get("jobTemplate") or {}).get("spec") or {}
            pod_spec = (jt.get("template") or {}).get("spec") or {}
            rp = pod_spec.get("restartPolicy")
            containers = [c for c in (pod_spec.get("containers") or []) if isinstance(c, dict)]
            cmd_blob = " ".join(
                str(x)
                for c in containers
                for x in ((c.get("command") or []) + (c.get("args") or []))
            ).lower()
            has_backup_logic = any(tok in cmd_blob for tok in ("pg_dump", "backup", "retention", "cleanup", "rm "))
            if isinstance(schedule, str) and schedule.strip() and rp in ("OnFailure", "Never") and has_backup_logic:
                valid_cronjobs += 1
        elif kind == "Deployment":
            _c, inits = extract_containers(doc)
            for ic in inits:
                if ic.get("name") and ic.get("image") and (ic.get("command") or ic.get("args")):
                    working_inits += 1
        elif kind == "StatefulSet":
            _c, inits = extract_containers(doc)
            for ic in inits:
                ic_blob = " ".join(str(x) for x in ((ic.get("command") or []) + (ic.get("args") or []))).lower()
                if "pg_isready" in ic_blob and ("127.0.0.1" in ic_blob or "localhost" in ic_blob):
                    failures.append(f"{rel}: StatefulSet has self-deadlocking pg_isready 127.0.0.1/localhost initContainer")

    if valid_cronjobs == 0:
        failures.append("no valid kind: CronJob with schedule, restartPolicy OnFailure/Never, and pg_dump/cleanup command found")
    if working_inits == 0:
        failures.append("no app Deployment with working initContainer (name, image, command/args) found")

    readme = repo / "stages" / "stage3" / "README.md"
    if not readme.is_file():
        failures.append("stages/stage3/README.md missing")
    else:
        txt = readme.read_text(encoding="utf-8").lower()
        for tok in ("nodeaffinity", "cordon", "pending", "uncordon", "initcontainer"):
            if tok not in txt:
                failures.append(f"stages/stage3/README.md missing token '{tok}'")
        if "identity-db-0" not in txt and "local-path" not in txt:
            failures.append("stages/stage3/README.md missing identity-db-0/local-path PV pinning reference")
        if "cronjob" not in txt and "pg_dump" not in txt:
            failures.append("stages/stage3/README.md missing CronJob/pg_dump documentation")

    for s2_md in git_files(repo, "stages/stage2/*.md", "stages/stage2/**/*.md"):
        s2_txt = s2_md.read_text(encoding="utf-8", errors="ignore")
        if re.search(
            r"stage\s*3.{0,120}(?:init\s*container|initcontainer).{0,120}(?:schema|init\.sql|postgres)",
            s2_txt,
            re.IGNORECASE,
        ):
            failures.append(f"{s2_md.relative_to(repo)}: stale claim that Stage 3 uses an initContainer for Postgres schema setup")

    if failures:
        return [make_result("T2-01", "2", "FAIL", "Stage 3 CronJob / initContainer / PV pinning failed", "; ".join(failures))]
    return [make_result("T2-01", "2", "PASS", f"Stage 3 verified ({valid_cronjobs} CronJob(s), {working_inits} app initContainer(s), PV pinning docs)")]


def check_t2_02(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 4 not in stages:
        return []
    yaml_paths = git_files(repo, "stages/stage4/**/*.yaml", "stages/stage4/**/*.yml", "stages/stage4/*.yaml", "stages/stage4/*.yml")
    docs, failures = load_yaml_docs(yaml_paths)

    kinds = {doc.get("kind") for _p, doc in docs}
    for req_kind in ("LimitRange", "ResourceQuota", "PriorityClass", "PodDisruptionBudget"):
        if req_kind not in kinds:
            failures.append(f"missing kind: {req_kind} in stages/stage4/")

    for gov_kind in ("LimitRange", "ResourceQuota"):
        gov_ns = {
            (doc.get("metadata") or {}).get("namespace")
            for _p, doc in docs
            if doc.get("kind") == gov_kind
        }
        for req_ns in ("apollo-airlines-apps", "apollo-airlines-ui"):
            if req_ns not in gov_ns:
                failures.append(f"{gov_kind} missing in namespace '{req_ns}'")

    app_deps = [
        (p, d)
        for p, d in docs
        if d.get("kind") == "Deployment"
        and (d.get("metadata") or {}).get("namespace") in ("apollo-airlines-apps", "apollo-airlines-ui")
    ]
    if not app_deps:
        failures.append("no app Deployments found in stages/stage4/ for apollo-airlines-apps/ui")
    for p, dep in app_deps:
        rel = p.relative_to(repo)
        dep_name = (dep.get("metadata") or {}).get("name")
        containers, _inits = extract_containers(dep)
        for c in containers:
            cname = c.get("name")
            for probe in ("startupProbe", "readinessProbe", "livenessProbe"):
                if not isinstance(c.get(probe), dict):
                    failures.append(f"{rel}: Deployment/{dep_name} container '{cname}' missing {probe}")
            prestop = ((c.get("lifecycle") or {}).get("preStop"))
            if not isinstance(prestop, dict):
                failures.append(f"{rel}: Deployment/{dep_name} container '{cname}' missing lifecycle.preStop")
            if not container_has_guaranteed_qos(c):
                failures.append(f"{rel}: Deployment/{dep_name} container '{cname}' lacks Guaranteed QoS (requests == limits)")

    all_dicts = [doc for _p, doc in docs]
    for key in ("tolerations", "nodeAffinity", "topologySpreadConstraints"):
        vals = [v for d in all_dicts for v in walk_dict_keys(d, key) if v]
        if not vals:
            failures.append(f"no non-empty '{key}' found in stages/stage4/ YAML")

    readme = repo / "stages" / "stage4" / "README.md"
    if not readme.is_file():
        failures.append("stages/stage4/README.md missing")
    else:
        txt = readme.read_text(encoding="utf-8").lower()
        for tok in ("endpointslice", "137", "oom", "prestop", "throttl"):
            if tok not in txt:
                failures.append(f"stages/stage4/README.md missing G20a/G20b lab token '{tok}'")
        if not any(tok in txt for tok in ("in-flight", "zero-drop", "zero dropped", "0 failed", "non-200")):
            failures.append("stages/stage4/README.md missing zero-drop in-flight preStop rolling restart proof")

    if failures:
        return [make_result("T2-02", "2", "FAIL", "Stage 4 scheduling / governance / G20a-b failed", "; ".join(failures))]
    return [make_result("T2-02", "2", "PASS", f"Stage 4 LimitRange, ResourceQuota, PriorityClass, PDB, {len(app_deps)} Guaranteed app Deployments & G20a/G20b verified")]


def check_t2_03(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    target_stages = [2, 5, 6]
    if stages is not None:
        target_stages = [s for s in target_stages if s in stages]
        if not target_stages:
            return []

    failures: list[str] = []

    if 2 in target_stages:
        s2_yamls = git_files(repo, "stages/stage2/**/*.yaml", "stages/stage2/**/*.yml", "stages/stage2/*.yaml", "stages/stage2/*.yml")
        docs, errs = load_yaml_docs(s2_yamls)
        failures.extend(errs)
        refgrants = [d for _p, d in docs if d.get("kind") == "ReferenceGrant"]
        if not refgrants:
            failures.append("stage2: missing kind: ReferenceGrant YAML")
        else:
            valid_rg = False
            for rg in refgrants:
                rg_ns = (rg.get("metadata") or {}).get("namespace")
                spec = rg.get("spec") or {}
                from_ok = any(
                    isinstance(fr, dict)
                    and fr.get("kind") == "HTTPRoute"
                    and fr.get("namespace") == "apollo-airlines-apps"
                    for fr in (spec.get("from") or [])
                )
                to_ok = any(
                    isinstance(to, dict)
                    and to.get("kind") == "Service"
                    and (to.get("namespace") in (None, "apollo-airlines-ui") and rg_ns == "apollo-airlines-ui")
                    for to in (spec.get("to") or [])
                )
                if from_ok and to_ok:
                    valid_rg = True
                    break
            if not valid_rg:
                failures.append("stage2: ReferenceGrant does not authorize apollo-airlines-apps HTTPRoute -> apollo-airlines-ui Service")
        httproutes = [d for _p, d in docs if d.get("kind") == "HTTPRoute"]
        has_redirect = any(
            isinstance(flt, dict) and flt.get("type") == "RequestRedirect"
            for hr in httproutes
            for flt in walk_dict_keys(hr, "filters")
            for flt in (flt if isinstance(flt, list) else [])
        )
        has_canary = any(
            isinstance(brefs, list) and len(brefs) >= 2 and any(isinstance(b, dict) and b.get("weight") is not None for b in brefs)
            for hr in httproutes
            for brefs in walk_dict_keys(hr, "backendRefs")
        )
        if not (has_redirect or has_canary):
            failures.append("stage2: no HTTPRoute with RequestRedirect filter or canary weight found")
        s2_readme = repo / "stages" / "stage2" / "README.md"
        if not s2_readme.is_file():
            failures.append("stage2: README.md missing")
        else:
            txt = s2_readme.read_text(encoding="utf-8")
            if "RefNotPermitted" not in txt:
                failures.append("stage2: README.md missing RefNotPermitted documentation")
            if "RequestRedirect" not in txt and "canary" not in txt.lower():
                failures.append("stage2: README.md missing RequestRedirect/canary documentation")

    if 5 in target_stages:
        schema_path = repo / "stages" / "stage5" / "helm" / "apollo11" / "values.schema.json"
        if not schema_path.is_file():
            failures.append("stage5: stages/stage5/helm/apollo11/values.schema.json missing")
        else:
            try:
                json.loads(schema_path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError) as exc:
                failures.append(f"stage5: values.schema.json invalid JSON: {exc}")
        s5_readme = repo / "stages" / "stage5" / "README.md"
        if not s5_readme.is_file():
            failures.append("stage5: README.md missing")
        else:
            txt = s5_readme.read_text(encoding="utf-8")
            low = txt.lower()
            if "test/ci.sh" not in txt:
                failures.append("stage5: README.md missing CI break/fix reference to test/ci.sh")
            if "values.schema.json" not in txt:
                failures.append("stage5: README.md missing values.schema.json CI break/fix lab")
            if not (("break" in low or "fail" in low or "violat" in low) and "fix" in low):
                failures.append("stage5: README.md missing interactive break/fix CI lab instructions")

    if 6 in target_stages:
        s6_readme = repo / "stages" / "stage6" / "README.md"
        s6_signals = repo / "stages" / "stage6" / "SIGNALS.md"
        combined = ""
        for f in (s6_readme, s6_signals):
            if f.is_file():
                combined += "\n" + f.read_text(encoding="utf-8")
        if not combined.strip():
            failures.append("stage6: README.md and SIGNALS.md missing")
        else:
            c_low = combined.lower()
            if "promtool test rules" not in combined:
                failures.append("stage6: missing 'promtool test rules' lab")
            if "histogram_quantile" not in combined:
                failures.append("stage6: missing PromQL 'histogram_quantile' authoring exercise")
            if "burn" not in c_low:
                failures.append("stage6: missing burn-rate PromQL exercise")
            if not any(tok in c_low for tok in ("error rate", "error_ratio", "5xx", 'status=~"5')):
                failures.append("stage6: missing error-rate PromQL authoring exercise")
            if s6_readme.is_file() and "promtool test rules" not in s6_readme.read_text(encoding="utf-8"):
                failures.append("stage6: README.md missing guided 'promtool test rules' lab section")

        slo_test = repo / "test" / "stage6_slo_rules_test.yaml"
        if not slo_test.is_file():
            failures.append("stage6: test/stage6_slo_rules_test.yaml missing")
        elif have_tool("promtool") and have_tool("helm"):
            s6_chart = repo / "stages" / "stage6" / "helm" / "apollo11"
            tmpl = run_cmd([
                "helm", "template", "apollo11", str(s6_chart),
                "--set", "gateway.envoy.bundleInstall=false",
                "--set", "metallb.bundleInstall=false",
            ])
            if tmpl.returncode != 0:
                failures.append(f"stage6: helm template for promtool failed: {tmpl.stderr.strip()}")
            else:
                s6_docs, s6_errs = load_yaml_stream(tmpl.stdout, "stage6-promtool")
                failures.extend(s6_errs)
                groups: list[Any] = []
                for d in s6_docs:
                    if d.get("kind") == "PrometheusRule":
                        groups.extend(((d.get("spec") or {}).get("groups") or []))
                if not groups:
                    failures.append("stage6: no PrometheusRule groups rendered from chart")
                else:
                    with tempfile.TemporaryDirectory(prefix="apollo-t2-03-prom-") as ptd:
                        ptdir = Path(ptd)
                        (ptdir / "rules.yaml").write_text(yaml.safe_dump({"groups": groups}), encoding="utf-8")
                        shutil.copy2(slo_test, ptdir / "tests.yaml")
                        pt_res = run_cmd(["promtool", "test", "rules", str(ptdir / "tests.yaml")], cwd=ptdir)
                        if pt_res.returncode != 0:
                            failures.append(f"stage6: promtool test rules failed: {(pt_res.stdout + pt_res.stderr).strip()[:300]}")

    if failures:
        return [make_result("T2-03", "2", "FAIL", "Stages 2/5/6 lab checks failed", "; ".join(failures))]
    return [make_result("T2-03", "2", "PASS", f"Stages {target_stages} lab contracts verified")]


def discover_stage7_vpa_set_args(chart_dir: Path, apply_sh: Path) -> list[str]:
    """Discover VPA enablement --set args from values.yaml / apply.sh without hardcoding one key."""
    values_file = chart_dir / "values.yaml"
    candidates: list[str] = []
    if apply_sh.is_file():
        apply_txt = apply_sh.read_text(encoding="utf-8", errors="ignore")
        for m in re.finditer(r"--set\s+([A-Za-z0-9_.-]*vpa[A-Za-z0-9_.-]*=(?:true|1))", apply_txt):
            candidates.append(m.group(1))
    if not candidates and values_file.is_file():
        try:
            vals = yaml.safe_load(values_file.read_text(encoding="utf-8")) or {}
        except yaml.YAMLError:
            vals = {}
        if isinstance(vals, dict) and isinstance(vals.get("vpa"), dict):
            vpa_cfg = vals["vpa"]
            if "enabled" in vpa_cfg:
                candidates.append("vpa.enabled=true")
            for sub_k, sub_v in vpa_cfg.items():
                if isinstance(sub_v, dict) and "enabled" in sub_v:
                    candidates.append(f"vpa.{sub_k}.enabled=true")
    if not candidates:
        candidates = ["vpa.search.enabled=true"]
    # Deduplicate preserving order
    seen: set[str] = set()
    unique: list[str] = []
    for c in candidates:
        if c not in seen:
            seen.add(c)
            unique.append(c)
    return unique


def check_t2_04(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 7 not in stages:
        return []
    if not have_tool("helm"):
        return [make_result("T2-04", "2", "FAIL", "helm tool missing for Stage 7 VPA template check", tool_missing=True)]

    apply_sh = repo / "stages" / "stage7" / "scripts" / "apply.sh"
    chart_dir = repo / "stages" / "stage7" / "helm" / "apollo11"
    values_dev = chart_dir / "values-dev.yaml"
    failures: list[str] = []

    if not apply_sh.is_file():
        failures.append("stages/stage7/scripts/apply.sh missing")
    else:
        help_res = run_cmd(["bash", str(apply_sh), "--help"])
        if help_res.returncode != 0:
            failures.append(f"apply.sh --help exited {help_res.returncode}")
        if "--with-vpa" not in (help_res.stdout + help_res.stderr):
            failures.append("apply.sh --help does not document --with-vpa")
        if "--with-vpa" not in apply_sh.read_text(encoding="utf-8", errors="ignore"):
            failures.append("apply.sh does not parse --with-vpa")

    if not chart_dir.is_dir() or not values_dev.is_file():
        failures.append("stages/stage7/helm/apollo11 or values-dev.yaml missing")
    else:
        default_render = run_cmd(["helm", "template", "apollo11", str(chart_dir), "-f", str(values_dev)])
        if default_render.returncode != 0:
            failures.append(f"helm template dev failed: {default_render.stderr.strip()}")
        else:
            docs, errs = load_yaml_stream(default_render.stdout, "stage7-dev-default")
            failures.extend(errs)
            default_vpas = [d for d in docs if d.get("kind") == "VerticalPodAutoscaler"]
            if default_vpas:
                failures.append(f"default dev render unexpectedly emitted {len(default_vpas)} VerticalPodAutoscaler(s)")

        set_args = discover_stage7_vpa_set_args(chart_dir, apply_sh)
        cmd = ["helm", "template", "apollo11", str(chart_dir), "-f", str(values_dev)]
        for s in set_args:
            cmd.extend(["--set", s])
        vpa_render = run_cmd(cmd)
        if vpa_render.returncode != 0:
            failures.append(f"helm template dev with VPA ({set_args}) failed: {vpa_render.stderr.strip()}")
        else:
            docs, errs = load_yaml_stream(vpa_render.stdout, "stage7-dev-vpa")
            failures.extend(errs)
            vpas = [d for d in docs if d.get("kind") == "VerticalPodAutoscaler"]
            if not vpas:
                failures.append(f"no VerticalPodAutoscaler rendered with --set {set_args}")
            for vpa in vpas:
                mode = ((vpa.get("spec") or {}).get("updatePolicy") or {}).get("updateMode")
                name = (vpa.get("metadata") or {}).get("name")
                if mode != "Off":
                    failures.append(f"VPA '{name}' updateMode={mode!r} (expected 'Off')")

    if failures:
        return [make_result("T2-04", "2", "FAIL", "Stage 7 --with-vpa check failed", "; ".join(failures))]
    return [make_result("T2-04", "2", "PASS", "Stage 7 --with-vpa flag & dev Off-mode VPA render verified")]


def check_t2_05(repo: Path, stages: list[int] | None, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 8 not in stages:
        return []

    s8 = repo / "stages" / "stage8"
    readme = s8 / "README.md"
    failures: list[str] = []

    if not readme.is_file():
        return [make_result("T2-05", "2", "FAIL", "stages/stage8/README.md missing")]

    readme_txt = readme.read_text(encoding="utf-8")
    if "status: not implemented" in readme_txt.lower():
        failures.append("stages/stage8/README.md still states 'Status: not implemented'")
    if not re.search(r"^##\s+Explain\b", readme_txt, re.IGNORECASE | re.MULTILINE):
        failures.append("stages/stage8/README.md missing '## Explain'")
    for tok in ("kubectl debug", "trivy", "cosign"):
        if tok not in readme_txt.lower():
            failures.append(f"stages/stage8/README.md missing '{tok}'")
    if "volume" not in readme_txt.lower() or "env" not in readme_txt.lower():
        failures.append("stages/stage8/README.md missing env vs volume-mount refresh docs")

    if (s8 / "overlays").exists():
        failures.append("stages/stage8/overlays/ exists (ROADMAP requires Stage 8+ to be Helm-only)")

    charts = sorted(s8.rglob("Chart.yaml"))
    if not charts:
        failures.append("stages/stage8/ missing Helm Chart.yaml")
        return [make_result("T2-05", "2", "FAIL", "Stage 8 security & Helm checks failed", "; ".join(failures))]

    if not have_tool("helm"):
        return [make_result("T2-05", "2", "FAIL", "helm missing for Stage 8 check", tool_missing=True)]

    rendered_docs: list[dict[str, Any]] = []
    for chart in charts:
        cdir = chart.parent
        lint = run_cmd(["helm", "lint", str(cdir)])
        if lint.returncode != 0:
            failures.append(f"helm lint {cdir.relative_to(repo)} failed: {lint.stdout.strip()} {lint.stderr.strip()}")
        val_files = sorted(cdir.glob("values*.yaml")) or [cdir / "values.yaml"]
        # Prefer values-dev.yaml or values.yaml to gather rendered docs
        render_targets = [vf for vf in val_files if vf.is_file()]
        if not render_targets:
            tmpl = run_cmd(["helm", "template", "apollo11", str(cdir)])
            if tmpl.returncode != 0:
                failures.append(f"helm template {cdir.relative_to(repo)} failed: {tmpl.stderr.strip()}")
            else:
                d, e = load_yaml_stream(tmpl.stdout, str(cdir.relative_to(repo)))
                failures.extend(e)
                rendered_docs.extend(d)
        else:
            for vf in render_targets:
                if vf.name == "values.yaml" and len(render_targets) > 1:
                    # Also lint with each env values file; render baseline values.yaml too
                    pass
                lint_vf = run_cmd(["helm", "lint", str(cdir), "-f", str(vf)])
                if lint_vf.returncode != 0:
                    failures.append(f"helm lint -f {vf.name} failed: {lint_vf.stderr.strip() or lint_vf.stdout.strip()}")
                tmpl = run_cmd(["helm", "template", "apollo11", str(cdir), "-f", str(vf)])
                if tmpl.returncode != 0:
                    failures.append(f"helm template -f {vf.name} failed: {tmpl.stderr.strip()}")
                elif vf.name in ("values.yaml", "values-dev.yaml") or not rendered_docs:
                    d, e = load_yaml_stream(tmpl.stdout, f"{cdir.relative_to(repo)}:{vf.name}")
                    failures.extend(e)
                    rendered_docs.extend(d)

    extra_yamls = [
        p for p in git_files(repo, "stages/stage8/**/*.yaml", "stages/stage8/**/*.yml", "stages/stage8/*.yaml", "stages/stage8/*.yml")
        if "/templates/" not in str(p) and p.name not in ("Chart.yaml", "Chart.lock", "values.schema.json")
        and not p.name.startswith("values")
    ]
    extra_docs, extra_errs = load_yaml_docs(extra_yamls)
    failures.extend(extra_errs)
    all_docs = rendered_docs + [d for _p, d in extra_docs]

    # RBAC checks
    roles = [d for d in all_docs if d.get("kind") == "Role"]
    rolebindings = [d for d in all_docs if d.get("kind") == "RoleBinding"]
    if not roles or not rolebindings:
        failures.append(f"Stage 8 RBAC incomplete (Role={len(roles)}, RoleBinding={len(rolebindings)})")
    for d in all_docs:
        if d.get("kind") == "ClusterRoleBinding":
            role_ref = (d.get("roleRef") or {}).get("name")
            if role_ref == "cluster-admin":
                for subj in d.get("subjects") or []:
                    ns = str((subj or {}).get("namespace", ""))
                    if ns.startswith("apollo-airlines"):
                        failures.append(f"ClusterRoleBinding grants cluster-admin to app namespace '{ns}'")

    # PSA restricted
    psa_restricted = False
    for d in all_docs:
        if d.get("kind") == "Namespace":
            labels = (d.get("metadata") or {}).get("labels") or {}
            if labels.get("pod-security.kubernetes.io/enforce") == "restricted":
                psa_restricted = True
    if not psa_restricted:
        failures.append("no Namespace with label pod-security.kubernetes.io/enforce=restricted")

    # Container hardening + initContainer + native sidecar
    hardened_app_containers = 0
    has_regular_init = False
    has_native_sidecar = False
    has_checksum_ann = False
    reloader_optin_deploys = 0

    for d in all_docs:
        kind = d.get("kind")
        name = str((d.get("metadata") or {}).get("name", ""))
        anns = get_pod_template_annotations(d)
        top_anns = (d.get("metadata") or {}).get("annotations") or {}
        combined_anns = {**top_anns, **anns}

        if any(str(k).startswith("checksum/") for k in anns):
            has_checksum_ann = True

        reloader_keys = [k for k in combined_anns if "reloader.stakater.com" in str(k)]
        if kind == "StatefulSet" and "db" in name.lower() and reloader_keys:
            failures.append(f"NEGATIVE CHECK FAILED: DB StatefulSet '{name}' has Reloader annotation(s): {reloader_keys}")
        if kind == "Deployment" and reloader_keys:
            reloader_optin_deploys += 1

        if kind in ("Deployment", "StatefulSet", "Pod", "CronJob", "Job"):
            containers, inits = extract_containers(d)
            for ic in inits:
                if ic.get("restartPolicy") == "Always":
                    has_native_sidecar = True
                else:
                    has_regular_init = True
            for c in containers:
                sc = c.get("securityContext") or {}
                pod_sc: dict[str, Any] = {}
                if kind == "Pod":
                    pod_sc = (d.get("spec") or {}).get("securityContext") or {}
                elif kind != "CronJob":
                    pod_sc = ((d.get("spec") or {}).get("template") or {}).get("spec", {}).get("securityContext") or {}
                run_non_root = sc.get("runAsNonRoot") is True or pod_sc.get("runAsNonRoot") is True
                no_priv_esc = sc.get("allowPrivilegeEscalation") is False
                ro_root = sc.get("readOnlyRootFilesystem") is True
                drops = ((sc.get("capabilities") or {}).get("drop") or [])
                seccomp = ((sc.get("seccompProfile") or {}).get("type") == "RuntimeDefault") or (
                    ((pod_sc.get("seccompProfile") or {}).get("type") == "RuntimeDefault")
                )
                if run_non_root and no_priv_esc and ro_root and "ALL" in drops and seccomp:
                    hardened_app_containers += 1

    if hardened_app_containers == 0:
        failures.append("no app container enforces full restricted securityContext (runAsNonRoot, allowPrivilegeEscalation=false, readOnlyRootFilesystem=true, drop ALL, RuntimeDefault seccomp)")
    if not has_regular_init:
        failures.append("Stage 8 missing working initContainer (without restartPolicy: Always)")
    if not has_native_sidecar:
        failures.append("Stage 8 missing native sidecar (initContainers entry with restartPolicy: Always)")

    # Calico + NetworkPolicy
    netpols = [d for d in all_docs if d.get("kind") == "NetworkPolicy"]
    if len(netpols) < 2:
        failures.append(f"Stage 8 expected >=2 NetworkPolicy docs, found {len(netpols)}")
    s8_text_blob = "\n".join(
        p.read_text(encoding="utf-8", errors="ignore")
        for p in git_files(repo, "stages/stage8/**/*", "stages/stage8/*")
    )
    if "calico" not in s8_text_blob.lower():
        failures.append("Stage 8 missing Calico CNI manifest/reference")

    # Vault + ESO + Reloader
    ext_secrets = [d for d in all_docs if d.get("kind") == "ExternalSecret"]
    secret_stores = [d for d in all_docs if d.get("kind") in ("SecretStore", "ClusterSecretStore")]
    if not ext_secrets or not secret_stores:
        failures.append(f"Stage 8 ESO incomplete (ExternalSecret={len(ext_secrets)}, SecretStore/ClusterSecretStore={len(secret_stores)})")
    if "--auto-reload-all=false" not in s8_text_blob:
        failures.append("Stage 8 Reloader missing '--auto-reload-all=false'")
    if reloader_optin_deploys == 0:
        failures.append("Stage 8 missing opt-in reloader.stakater.com annotation on app Deployment")
    if not has_checksum_ann:
        failures.append("Stage 8 missing checksum/* Pod-template annotation on Git-config workload")

    # Kyverno + Trivy + Cosign
    kyverno_policies = [d for d in all_docs if d.get("kind") in ("ClusterPolicy", "Policy") and "kyverno" in str(d.get("apiVersion", "")).lower()]
    if not kyverno_policies:
        failures.append("Stage 8 missing Kyverno ClusterPolicy/Policy")
    if "trivy" not in s8_text_blob.lower() or "cosign" not in s8_text_blob.lower():
        failures.append("Stage 8 missing Trivy/Cosign integration")

    # Stage 8 scripts: --help and foreign context rejection with fake kubectl/helm shims
    with tempfile.TemporaryDirectory(prefix="apollo-s8-guard-") as td:
        tdir = Path(td)
        call_log = tdir / "calls"
        for tool_name in ("kubectl", "helm"):
            shim = tdir / tool_name
            shim.write_text(
                f"#!/usr/bin/env bash\nset -euo pipefail\necho \"{tool_name} $*\" >> \"$CALL_LOG\"\n"
                "if [[ \"$*\" == \"config current-context\" ]]; then echo \"$FAKE_CONTEXT\"; exit 0; fi\nexit 97\n",
                encoding="utf-8",
            )
            shim.chmod(0o755)
        env = dict(os.environ, PATH=f"{tdir}:{os.environ['PATH']}", CALL_LOG=str(call_log), FAKE_CONTEXT="arn:aws:eks:unsafe")
        env.pop("KUBE_CONTEXT", None)

        for script_name in ("apply.sh", "verify.sh", "teardown.sh"):
            sp = s8 / "scripts" / script_name
            if not sp.is_file():
                failures.append(f"stages/stage8/scripts/{script_name} missing")
                continue
            call_log.unlink(missing_ok=True)
            h_res = run_cmd(["bash", str(sp), "--help"], env=env)
            if h_res.returncode != 0:
                failures.append(f"stage8/scripts/{script_name} --help exited {h_res.returncode}")
            if call_log.exists() and call_log.read_text(encoding="utf-8").strip():
                failures.append(f"stage8/scripts/{script_name} --help invoked kubectl/helm")

            call_log.unlink(missing_ok=True)
            c_res = run_cmd(["bash", str(sp), "--context", "arn:aws:eks:unsafe"], env=env)
            if c_res.returncode == 0:
                failures.append(f"stage8/scripts/{script_name} accepted foreign context arn:aws:eks:unsafe")
            if call_log.exists():
                for line in call_log.read_text(encoding="utf-8").splitlines():
                    if any(mut in line for mut in ("delete", "apply", "patch", "scale", "install", "upgrade", "uninstall")):
                        failures.append(f"stage8/scripts/{script_name} made mutating call under foreign context: {line}")

    if failures:
        return [make_result("T2-05", "2", "FAIL", f"Stage 8 security/Helm checks failed ({len(failures)} issues)", "\n".join(failures))]
    return [make_result("T2-05", "2", "PASS", "Stage 8 Helm-only, RBAC, PSA restricted, Calico, ESO/Reloader (DB STS excluded), Kyverno & native sidecar verified")]


def check_t2_06(repo: Path, stages: list[int] | None, strict_tools: bool = False, **_kwargs: Any) -> list[dict[str, Any]]:
    if stages is not None and 9 not in stages:
        return []

    results: list[dict[str, Any]] = []
    s9 = repo / "stages" / "stage9"
    readme = s9 / "README.md"
    failures: list[str] = []

    if not readme.is_file():
        return [make_result("T2-06", "2", "FAIL", "stages/stage9/README.md missing")]

    readme_txt = readme.read_text(encoding="utf-8")
    if "status: not implemented" in readme_txt.lower():
        failures.append("stages/stage9/README.md still states 'Status: not implemented'")
    if not re.search(r"^##\s+Explain\b", readme_txt, re.IGNORECASE | re.MULTILINE):
        failures.append("stages/stage9/README.md missing '## Explain'")

    s9_files = git_files(repo, "stages/stage9/**/*", "stages/stage9/*")
    s9_blob = "\n".join(p.read_text(encoding="utf-8", errors="ignore") for p in s9_files).lower()

    # Check required 11 Stage 9 capstone topics/artifacts
    topic_checks = {
        "cost/billable inventory": ("cost" in s9_blob and ("billable" in s9_blob or "inventory" in s9_blob)),
        "IRSA / workload identity": ("irsa" in s9_blob or "workload identity" in s9_blob),
        "EBS CSI": ("ebs" in s9_blob),
        "ownership-scoped teardown/residue sweep": ("teardown" in s9_blob and ("ownership" in s9_blob or "tag" in s9_blob)),
        "DNS / cert-manager / TLS": ("cert-manager" in s9_blob and "tls" in s9_blob),
        "Cluster Autoscaler": ("cluster autoscaler" in s9_blob or "autoscaler" in s9_blob),
        "PDB / node drain": ("pdb" in s9_blob and "drain" in s9_blob),
        "Kubernetes upgrade": ("upgrade" in s9_blob),
        "Velero backup/restore": ("velero" in s9_blob),
        "EKS-to-GKE portability": ("gke" in s9_blob),
        "production-gap analysis": ("production-shaped" in s9_blob or "gap analysis" in s9_blob),
    }
    for topic, ok in topic_checks.items():
        if not ok:
            failures.append(f"Stage 9 missing required capstone topic: {topic}")

    # Check Stage 9 teardown/ebs scripts require ownership tag filter
    for sh in [p for p in s9_files if p.suffix == ".sh" and any(k in p.name.lower() for k in ("ebs", "sweep", "teardown", "cleanup"))]:
        stxt = sh.read_text(encoding="utf-8", errors="ignore")
        if "tag:" not in stxt and "apollo11" not in stxt.lower() and "cluster" not in stxt.lower():
            failures.append(f"{sh.relative_to(repo)}: missing ownership/cluster tag scoping")

    # Helm charts under stages/stage9/
    charts = sorted(s9.rglob("Chart.yaml")) if s9.is_dir() else []
    if charts:
        if not have_tool("helm"):
            failures.append("helm missing for Stage 9 chart validation")
        else:
            for ch in charts:
                cdir = ch.parent
                l_res = run_cmd(["helm", "lint", str(cdir)])
                if l_res.returncode != 0:
                    failures.append(f"helm lint {cdir.relative_to(repo)} failed: {l_res.stderr.strip() or l_res.stdout.strip()}")
                for vf in sorted(cdir.glob("values*.yaml")) or [cdir / "values.yaml"]:
                    if vf.is_file():
                        t_res = run_cmd(["helm", "template", "apollo11", str(cdir), "-f", str(vf)])
                        if t_res.returncode != 0:
                            failures.append(f"helm template {cdir.relative_to(repo)} -f {vf.name} failed: {t_res.stderr.strip()}")

    # PyYAML validation of all non-chart-template YAMLs under stages/stage9/
    k8s_yamls = [
        p for p in git_files(repo, "stages/stage9/**/*.yaml", "stages/stage9/**/*.yml", "stages/stage9/*.yaml", "stages/stage9/*.yml")
        if "/templates/" not in str(p) and p.name not in ("Chart.yaml", "Chart.lock", "values.schema.json")
        and not p.name.startswith("values")
    ]
    k8s_docs, yaml_errs = load_yaml_docs(k8s_yamls)
    failures.extend(yaml_errs)
    for p, doc in k8s_docs:
        if "apiVersion" in doc or "kind" in doc:
            if not (doc.get("apiVersion") and doc.get("kind") and (doc.get("metadata") or {}).get("name")):
                failures.append(f"{p.relative_to(repo)}: K8s manifest missing apiVersion/kind/metadata.name")

    # Check test/stage9_test.sh
    s9_test = repo / "test" / "stage9_test.sh"
    if not s9_test.is_file():
        failures.append("test/stage9_test.sh missing")
    else:
        bn = run_cmd(["bash", "-n", str(s9_test)])
        if bn.returncode != 0:
            failures.append(f"test/stage9_test.sh bash -n failed: {bn.stderr.strip()}")
        if have_tool("shellcheck"):
            sc = run_cmd(["shellcheck", "-S", "warning", str(s9_test)])
            if sc.returncode != 0:
                failures.append(f"test/stage9_test.sh shellcheck failed: {sc.stdout.strip() or sc.stderr.strip()}")

    # Terraform directory discovery
    tf_files = [p for p in git_files(repo, "stages/stage9/**/*.tf", "stages/stage9/*.tf") if ".terraform/" not in str(p)]
    tf_dirs = sorted({p.parent for p in tf_files})
    if not tf_dirs:
        failures.append("stages/stage9/ has no *.tf Terraform files")
    for tf in tf_files:
        txt = tf.read_text(encoding="utf-8", errors="ignore")
        if re.search(r"\b(azurerm|google_container_cluster)\b", txt):
            failures.append(f"{tf.relative_to(repo)}: forbidden azurerm/google_container_cluster block")

    if failures:
        results.append(make_result("T2-06", "2", "FAIL", f"Stage 9 capstone checks failed ({len(failures)} issues)", "\n".join(failures)))
    else:
        results.append(make_result("T2-06", "2", "PASS", f"Stage 9 docs, {len(tf_dirs)} TF module dir(s), YAML & test/stage9_test.sh verified"))

    # T2-06-tf: Terraform init/validate in $TMPDIR
    if not tf_dirs:
        results.append(make_result("T2-06-tf", "2", "FAIL", "No Terraform modules found under stages/stage9/"))
    elif not have_tool("terraform"):
        status = "FAIL" if strict_tools else "SKIP"
        results.append(make_result(
            "T2-06-tf",
            "2",
            status,
            "terraform tool unavailable or inactive mise shim (run: mise use -g terraform)",
            tool_missing=True,
        ))
    else:
        tf_failures: list[str] = []
        with tempfile.TemporaryDirectory(prefix="apollo-s9-tf-") as td:
            root_copy = Path(td) / "stage9"
            shutil.copytree(s9, root_copy, ignore=shutil.ignore_patterns(".terraform", "*.tfstate*"))
            for orig_dir in tf_dirs:
                rel_dir = orig_dir.relative_to(s9)
                mod_dir = root_copy / rel_dir
                init_res = run_cmd(["terraform", "init", "-backend=false", "-input=false", "-no-color"], cwd=mod_dir)
                if init_res.returncode != 0:
                    tf_failures.append(f"{rel_dir}: terraform init failed: {init_res.stderr.strip() or init_res.stdout.strip()}")
                    continue
                val_res = run_cmd(["terraform", "validate", "-no-color"], cwd=mod_dir)
                if val_res.returncode != 0:
                    tf_failures.append(f"{rel_dir}: terraform validate failed: {val_res.stderr.strip() or val_res.stdout.strip()}")
        if tf_failures:
            results.append(make_result("T2-06-tf", "2", "FAIL", "Stage 9 terraform validate failed", "; ".join(tf_failures)))
        else:
            results.append(make_result("T2-06-tf", "2", "PASS", f"Stage 9 terraform validate passed in $TMPDIR across {len(tf_dirs)} module(s)"))

    # T2-06-dryrun: kubectl apply --dry-run=client gated on cluster reachability
    cluster_ok = False
    if have_tool("kubectl"):
        ci = run_cmd(["kubectl", "cluster-info", "--request-timeout=2s"])
        cluster_ok = ci.returncode == 0
    if not cluster_ok:
        status = "FAIL" if strict_tools else "SKIP"
        results.append(make_result(
            "T2-06-dryrun",
            "2",
            status,
            "No reachable Kubernetes API server for kubectl apply --dry-run=client (offline PyYAML checks still ran)",
            tool_missing=True,
        ))
    else:
        dr_failures: list[str] = []
        for p in k8s_yamls:
            if any(d.get("apiVersion") and d.get("kind") for dp, d in k8s_docs if dp == p):
                dr = run_cmd(["kubectl", "apply", "--dry-run=client", "-f", str(p)])
                if dr.returncode != 0:
                    dr_failures.append(f"{p.relative_to(repo)}: {dr.stderr.strip()}")
        if dr_failures:
            results.append(make_result("T2-06-dryrun", "2", "FAIL", "Stage 9 kubectl apply --dry-run=client failed", "; ".join(dr_failures)))
        else:
            results.append(make_result("T2-06-dryrun", "2", "PASS", "Stage 9 kubectl apply --dry-run=client passed"))

    return results


CHECKS = {
    "T1-01": check_t1_01,
    "T1-02": check_t1_02,
    "T1-03": check_t1_03,
    "T1-04": check_t1_04,
    "T1-05": check_t1_05,
    "T1-06": check_t1_06,
    "T1-07": check_t1_07,
    "T1-08": check_t1_08,
    "T1-09": check_t1_09,
    "T2-01": check_t2_01,
    "T2-02": check_t2_02,
    "T2-03": check_t2_03,
    "T2-04": check_t2_04,
    "T2-05": check_t2_05,
    "T2-06": check_t2_06,
}


def write_json_report(
    repo: Path,
    jsonl_path: Path,
    out_path: Path,
    flags_json: str,
    tools_json: str,
    exit_code: int,
) -> None:
    checks: list[dict[str, Any]] = []
    if jsonl_path.is_file():
        for line in jsonl_path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if line:
                checks.append(json.loads(line))
    passed = sum(1 for c in checks if c.get("status") == "PASS")
    failed = sum(1 for c in checks if c.get("status") == "FAIL")
    skipped = sum(1 for c in checks if c.get("status") == "SKIP")
    head_res = run_cmd(["git", "-C", str(repo), "rev-parse", "--short", "HEAD"])
    repo_head = head_res.stdout.strip() if head_res.returncode == 0 else "unknown"
    report = {
        "schema_version": "1.0",
        "timestamp_utc": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "repo_head": repo_head,
        "flags": json.loads(flags_json),
        "tools": json.loads(tools_json),
        "counts": {
            "total": len(checks),
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        },
        "exit_code": exit_code,
        "checks": checks,
    }
    out_path.parent.mkdir(parents=True, exist_ok=True)
    out_path.write_text(json.dumps(report, indent=2) + "\n", encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser(description="Apollo11 static E2E check runner")
    sub = parser.add_subparsers(dest="cmd", required=True)

    run_p = sub.add_parser("run", help="Run a static check ID")
    run_p.add_argument("--repo-root", required=True)
    run_p.add_argument("--check", required=True, choices=sorted(CHECKS))
    run_p.add_argument("--stages", default="")
    run_p.add_argument("--include-global", action="store_true")
    run_p.add_argument("--strict-tools", action="store_true")

    rep_p = sub.add_parser("report", help="Compile JSONL check results into structured JSON report")
    rep_p.add_argument("--repo-root", required=True)
    rep_p.add_argument("--jsonl", required=True)
    rep_p.add_argument("--out", required=True)
    rep_p.add_argument("--flags-json", required=True)
    rep_p.add_argument("--tools-json", required=True)
    rep_p.add_argument("--exit-code", type=int, required=True)

    args = parser.parse_args()
    repo = Path(args.repo_root).resolve()

    if args.cmd == "report":
        write_json_report(
            repo=repo,
            jsonl_path=Path(args.jsonl),
            out_path=Path(args.out),
            flags_json=args.flags_json,
            tools_json=args.tools_json,
            exit_code=args.exit_code,
        )
        return 0

    stages_list: list[int] | None = None
    if args.stages:
        stages_list = [int(x) for x in args.stages.split(",") if x.strip()]

    results = CHECKS[args.check](
        repo=repo,
        stages=stages_list,
        include_global=args.include_global,
        strict_tools=args.strict_tools,
    )
    print(json.dumps(results))
    return 0


if __name__ == "__main__":
    sys.exit(main())
