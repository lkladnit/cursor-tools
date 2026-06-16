#!/usr/bin/env python3
"""
Scan all Jenkins jobs from jobs.md, fetch latest results, and regenerate
both jobs.md and jobs.html with fresh data and a scan timestamp.

Usage:
    JENKINS_VERIFY_SSL=false python3 scan_jobs.py

Requires: httpx (install via mcp-server/requirements.txt)
"""

import asyncio
import json
import os
import re
from datetime import datetime
from urllib.parse import urlparse

SKILL_DIR = os.path.dirname(os.path.abspath(__file__))
JOBS_MD = os.path.join(SKILL_DIR, "jobs.md")
JOBS_DIR = os.path.join(SKILL_DIR, "jobs")

# Clipboard icon for HTML report (embedded at top of script before render()).
COPY_ICON_DATA_URI = (
    "data:image/svg+xml;base64,PHN2ZyB4bWxucz0iaHR0cDovL3d3dy53My5vcmcvMjAwMC9zdmciIHZpZXdCb3g9IjAgMCA0NDggNTEyIj48cGF0aCBmaWxsPSJ3aGl0ZSIgZD0iTTIwOCAwSDMzMi4xYzEyLjcgMCAyNC45IDUuMSAzMy45IDE0LjFsNjcuOSA2Ny45YzkgOSAxNC4xIDIxLjIgMTQuMSAzMy45VjMzNmMwIDI2LjUtMjEuNSA0OC00OCA0OEgyMDhjLTI2LjUgMC00OC0yMS41LTQ4LTQ4VjQ4YzAtMjYuNSAyMS41LTQ4IDQ4LTQ4ek00OCAxMjhoODB2NjRINjRWNDQ4SDI1NlY0MTZoNjR2NDhjMCAyNi41LTIxLjUgNDgtNDggNDhINDhjLTI2LjUgMC00OC0yMS41LTQ4LTQ4VjE3NmMwLTI2LjUgMjEuNS00OCA0OC00OHoiLz48L3N2Zz4="
)

VERIFY_SSL = os.environ.get("JENKINS_VERIFY_SSL", "true").lower() == "true"
USERNAME = os.environ.get("JENKINS_USER", "")
TOKEN = os.environ.get("JENKINS_TOKEN", "")

ROW_RE = re.compile(
    r"^\|"
    r"\s*(?P<cnv>[^|]*?)\s*\|"
    r"\s*(?P<job_col>.*?)\s*\|"
    r"\s*(?:.*?)\s*\|"
    r"\s*(?:.*?)\s*\|"
    r"\s*(?:.*?)\s*\|"
    r"\s*$"
)

JOB_LINK_RE = re.compile(r"\[(.+?)\]\((https?://[^)]+)\)")


def parse_jobs_md():
    with open(JOBS_MD) as f:
        lines = f.read().strip().split("\n")

    header_lines = []
    rows = []
    current_cnv = ""

    for i, line in enumerate(lines):
        m = ROW_RE.match(line)
        if not m:
            header_lines.append(line)
            continue
        cnv = m.group("cnv").strip()
        job_col = m.group("job_col").strip()
        if cnv in ("CNV", "") and not job_col:
            header_lines.append(line)
            continue
        if cnv.startswith("---") or job_col.startswith("---"):
            header_lines.append(line)
            continue

        if cnv:
            current_cnv = cnv

        jm = JOB_LINK_RE.match(job_col)
        if not jm:
            header_lines.append(line)
            continue

        rows.append({
            "line_idx": i,
            "cnv": current_cnv,
            "job_name": jm.group(1),
            "job_url": jm.group(2).rstrip("/") + "/",
            "job_link": job_col,
        })

    return lines, header_lines, rows


def _extract_rp_url(build_json: dict) -> str:
    """Extract ReportPortal launch URL from Jenkins badge actions."""
    for action in build_json.get("actions", []):
        if not isinstance(action, dict):
            continue
        text = action.get("text", "")
        if "reportportal" in text.lower():
            m = re.search(r'href="(https?://[^"]*reportportal[^"]*)"', text)
            if m:
                raw = m.group(1)
                base = re.sub(r'/\?.*$', '/', raw)
                return base.rstrip("/")
    return ""


def _param_str_value(p: dict) -> str:
    v = p.get("value")
    if v is None:
        return ""
    if isinstance(v, dict):
        return str(v.get("name") or v.get("value") or "").strip()
    return str(v).strip()


def _trim_short_cluster(val: str) -> str:
    """Normalize API host / FQDN to a short display name (first DNS label)."""
    s = (val or "").strip()
    if not s:
        return ""
    if "://" in s:
        try:
            netloc = urlparse(s).netloc.split("@")[-1]
            host = netloc.split(":")[0].strip("[]")
            if host:
                s = host
        except Exception:
            pass
    if "." in s and "/" not in s and " " not in s:
        return s.split(".")[0]
    return s


def _param_map_from_build(build_json: dict) -> dict[str, str]:
    """Jenkins build parameter names (lower) → string values."""
    by_lower: dict[str, str] = {}
    for action in build_json.get("actions", []):
        if not isinstance(action, dict):
            continue
        params = action.get("parameters")
        if not isinstance(params, list):
            continue
        for p in params:
            if not isinstance(p, dict):
                continue
            name = (p.get("name") or "").strip()
            if not name:
                continue
            val = _param_str_value(p)
            if val:
                by_lower[name.lower()] = val
    return by_lower


_CLUSTER_KEY_BLACKLIST = (
    "password",
    "token",
    "secret",
    "credential",
    "apikey",
    "user",
    "email",
    "repo",
    "branch",
    "commit",
    "gitlab",
    "github",
    "image",
    "namespace",
    "path",
    "json",
    "xml",
    "report",
    "slack",
    "channel",
)

# CNV operator index tags: rhel8 (older lanes) and rhel9; seen in params and console logs.
_CNV_BUNDLE_RE = re.compile(r"v\d+\.\d+\.\d+\.rhel[89]-\d+", re.IGNORECASE)
# Older index / image tags omit ``.rhelN-`` (e.g. ``v4.12.11-24``).
_CNV_BUNDLE_RE_ALT = re.compile(r"\bv4\.\d+\.\d+-\d+\b", re.IGNORECASE)


def _cnv_bundle_from_text(text: str) -> str:
    """First CNV index-like tag in ``text`` (strict ``.rhelN-`` form, then ``v4.x.y-z``)."""
    s = (text or "").strip()
    if not s:
        return ""
    m = _CNV_BUNDLE_RE.search(s)
    if m:
        return m.group(0)
    m = _CNV_BUNDLE_RE_ALT.search(s)
    if m:
        return m.group(0)
    return ""


def _cnv_bundle_param_key_hint(k: str) -> bool:
    kl = k.lower()
    return any(
        x in kl
        for x in (
            "cnv",
            "bundle",
            "hco",
            "virt",
            "kubevirt",
            "catalog",
            "operator",
            "index",
            "image",
            "channel",
            "subscription",
        )
    )


def _looks_like_cluster_short_token(val: str) -> bool:
    """True if value looks like a lab short cluster id (e.g. t1-small-422, bm08b-tlv2)."""
    s = val.strip().strip("'\"")
    if len(s) < 4 or len(s) > 56:
        return False
    if s.lower() in ("true", "false", "none", "null", "yes", "no"):
        return False
    if "://" in s or "/" in s or " " in s or "\n" in s:
        return False
    if _CNV_BUNDLE_RE.search(s) or _CNV_BUNDLE_RE_ALT.fullmatch(s):
        return False
    if re.fullmatch(r"\d+\.\d+\.\d+", s):
        return False
    if re.fullmatch(r"[0-9a-f]{8}-[0-9a-f-]{27,36}", s, re.I):
        return False
    if re.fullmatch(r"\d+\.\d+", s):
        return False
    if not re.fullmatch(r"[a-zA-Z0-9][a-zA-Z0-9.-]*[a-zA-Z0-9]", s):
        return False
    return True


def _cluster_key_ok_for_scan(k: str) -> bool:
    kl = k.lower()
    return not any(bad in kl for bad in _CLUSTER_KEY_BLACKLIST)


def _weak_param_cluster_guess(val: str) -> bool:
    """Extra filter when no parameter key matches cluster hints (lab naming)."""
    s = val.lower()
    if s.startswith("bm") or s.startswith("infd") or "small-" in s:
        return True
    if "cnvqe" in s or "tlv2" in s or "rdu2" in s:
        return True
    if "-" in val and any(c.isdigit() for c in val):
        return True
    return False


def _extract_short_cluster_from_map(by_lower: dict[str, str]) -> str:
    """Short cluster label from parameter map."""
    preferred = (
        "short_cluster_name",
        "shortclustername",
        "cluster_short_name",
        "cluster_short",
        "short_cluster",
        "shortcluster",
        "short_name",
        "cluster_short_label",
        "openshift_cluster_short",
        "ocp_cluster_short",
        "test_cluster_name",
        "test_cluster",
        "env_cluster",
        "infra_cluster",
        "cluster_hostname",
        "cluster_host",
        "cluster_label",
        "oc_cluster",
        "cluster_id",
        "clusterid",
    )
    fallback = (
        "cluster_name",
        "cluster",
        "ocp_cluster",
        "ocp_cluster_name",
        "target_cluster",
        "openshift_cluster",
        "openshift_cluster_name",
        "api_url",
        "apiurl",
    )
    for key in preferred:
        if key in by_lower:
            t = _trim_short_cluster(by_lower[key])
            if t:
                return t
    for key in fallback:
        if key in by_lower:
            t = _trim_short_cluster(by_lower[key])
            if t:
                return t
    for k, v in sorted(by_lower.items(), key=lambda kv: (len(kv[0]), kv[0])):
        if "short" in k and "cluster" in k:
            t = _trim_short_cluster(v)
            if t:
                return t
    for k, v in by_lower.items():
        if k in ("cluster_name", "cluster") or k.endswith("_cluster"):
            t = _trim_short_cluster(v)
            if t:
                return t

    hints = ("cluster", "ocp", "openshift", "host", "infra", "env", "lab", "short", "bm", "infd")
    scored: list[tuple[int, str, str]] = []
    for k, v in by_lower.items():
        if not _cluster_key_ok_for_scan(k):
            continue
        raw = (v or "").strip().strip("'\"")
        if not _looks_like_cluster_short_token(raw):
            continue
        score = sum(3 for h in hints if h in k.lower())
        scored.append((score, k, raw))
    hinted = [x for x in scored if x[0] > 0]
    pool = hinted if hinted else [x for x in scored if _weak_param_cluster_guess(x[2])]
    if pool:
        pool.sort(key=lambda x: (-x[0], -len(x[2]), x[1]))
        return _trim_short_cluster(pool[0][2])
    return ""


_CLUSTER_HASH_SUFFIX_RE = re.compile(r"-([a-z0-9]{5})$", re.IGNORECASE)


def _normalize_cluster_short_display(s: str) -> str:
    """Strip OpenShift-style infra suffix (e.g. ``...-hjlnc``) so rows match lane ids like ``t1-small-422``."""
    if not s:
        return ""
    t = s.strip()
    m = _CLUSTER_HASH_SUFFIX_RE.search(t)
    if not m:
        return t
    base = t[: m.start()]
    if len(base) < 4:
        return t
    if not _looks_like_cluster_short_token(base):
        return t
    return base


def _short_cluster_from_console_url(url: str) -> str:
    """Use the first label after ``apps.`` in the console URL when build params omit a short name."""
    if not url:
        return ""
    try:
        host = urlparse(url).netloc.split("@")[-1].split(":")[0].strip("[]")
    except Exception:
        return ""
    if not host:
        return ""
    parts = host.split(".")
    for i, part in enumerate(parts):
        if part.lower() == "apps" and i + 1 < len(parts):
            cand = parts[i + 1]
            if _looks_like_cluster_short_token(cand):
                return cand
            break
    return ""


def _extract_cluster_url_from_map(by_lower: dict[str, str]) -> str:
    """Console / bridge URL from build parameters when present."""
    url_keys = (
        "bridge_base_address",
        "openshift_console_url",
        "console_url",
        "cluster_console_url",
        "web_console_url",
    )
    for key in url_keys:
        if key not in by_lower:
            continue
        v = by_lower[key].strip().strip("'\"")
        if v.startswith("http://") or v.startswith("https://"):
            return v.rstrip("/")
    for _k, v in by_lower.items():
        v = v.strip().strip("'\"")
        if v.startswith("https://") and (
            "console-openshift" in v or ".apps." in v or "/console" in v.lower()
        ):
            return v.rstrip("/")
    return ""


def _extract_cnv_bundle_from_map(by_lower: dict[str, str]) -> str:
    """CNV index tag like ``v4.XX.0.rhel9-YY`` / ``...rhel8-...`` from last build parameters."""
    preferred_keys = (
        "cnv_bundle_version",
        "cnv_version",
        "cluster_cnv_version",
        "bundle_version",
        "full_cnv_version",
        "cnv_bundle",
        "virt_bundle",
        "kubevirt_bundle",
        "hco_bundle",
        "hco_index_image",
        "operator_bundle",
        "catalog_image",
        "index_image",
        "source_image",
    )
    for key in preferred_keys:
        if key not in by_lower:
            continue
        val = by_lower[key].strip().strip("'\"")
        found = _cnv_bundle_from_text(val)
        if found:
            return found
    for _k, v in by_lower.items():
        m = _CNV_BUNDLE_RE.search(v.strip())
        if m:
            return m.group(0)
    for k, v in by_lower.items():
        if not _cnv_bundle_param_key_hint(k):
            continue
        found = _cnv_bundle_from_text(v.strip())
        if found:
            return found
    return ""


def _extract_cluster_password_from_map(by_lower: dict[str, str]) -> str:
    """Kubeadmin / console password from build parameters when exposed."""
    keys = (
        "bridge_kubeadmin_password",
        "kubeadmin_password",
        "kube_admin_password",
        "openshift_kubeadmin_password",
    )
    for key in keys:
        if key not in by_lower:
            continue
        v = by_lower[key].strip().strip("'\"")
        if v and v not in ("****", "***", "${FROM_CREDENTIAL}"):
            return v
    return ""


async def _scan_console_for_hints(
    client,
    console_text_url: str,
    *,
    want_bridge: bool,
    want_bundle: bool,
    want_password: bool,
) -> tuple[str, str, str]:
    """Stream console log once; parse BRIDGE_*, CNV bundle tag, and kubeadmin password as needed."""
    import httpx

    bridge_re = re.compile(
        rb"BRIDGE_BASE_ADDRESS\s*[=:]\s*['\"]?([^\s'\"\\\n\r]+)",
        re.IGNORECASE,
    )
    pw_re = re.compile(
        rb"BRIDGE_KUBEADMIN_PASSWORD\s*[=:]\s*(?:'([^']*)'|\"([^\"]*)\"|([^\s'\"\\\n\r]+))",
        re.IGNORECASE,
    )
    bundle_re = re.compile(rb"v\d+\.\d+\.\d+\.rhel[89]-\d+", re.IGNORECASE)
    bundle_re_alt = re.compile(rb"\bv4\.\d+\.\d+-\d+\b", re.IGNORECASE)
    buf = b""
    bridge_url = ""
    cnv_bundle = ""
    kubeadmin_password = ""

    def have_all() -> bool:
        return (
            (not want_bridge or bool(bridge_url))
            and (not want_bundle or bool(cnv_bundle))
            and (not want_password or bool(kubeadmin_password))
        )

    try:
        async with client.stream(
            "GET",
            console_text_url,
            timeout=httpx.Timeout(60.0, read=120.0),
        ) as resp:
            resp.raise_for_status()
            async for chunk in resp.aiter_bytes():
                buf += chunk
                if want_bridge and not bridge_url:
                    m = bridge_re.search(buf)
                    if m:
                        raw = m.group(1).decode("utf-8", errors="replace").strip().strip("'\"")
                        if raw.startswith("http://") or raw.startswith("https://"):
                            bridge_url = raw.rstrip("/")
                if want_password and not kubeadmin_password:
                    m = pw_re.search(buf)
                    if m:
                        raw_g = m.group(1) or m.group(2) or m.group(3) or b""
                        kubeadmin_password = raw_g.decode("utf-8", errors="replace").strip()
                if want_bundle and not cnv_bundle:
                    m = bundle_re.search(buf) or bundle_re_alt.search(buf)
                    if m:
                        cnv_bundle = m.group(0).decode("utf-8", errors="replace")
                if have_all():
                    break
                if len(buf) > 2_500_000:
                    break
    except Exception:
        pass
    return bridge_url, cnv_bundle, kubeadmin_password


def framework_from_cnv(cnv: str) -> str:
    """Playwright for CNV 4.22+; Cypress for older lanes (QE convention)."""
    s = (cnv or "").strip()
    if not s:
        return "CY"
    try:
        ver = float(s)
    except ValueError:
        m = re.match(r"^(\d+\.\d+)", s)
        if not m:
            return "CY"
        ver = float(m.group(1))
    return "PW" if ver >= 4.22 else "CY"


async def fetch_job(client, url):
    try:
        r = await client.get(f"{url}api/json?tree=nextBuildNumber", timeout=15)
        r.raise_for_status()
        builds = r.json().get("nextBuildNumber", 1) - 1
    except Exception as e:
        print(f"  ERR {url}: {e}")
        builds = 0

    last_num = None
    last_date = "N/A"
    total = passed = failed = skipped = None
    build_result = ""
    rp_url = ""
    cluster_short = ""
    cluster_url = ""
    cnv_bundle = ""
    cluster_password = ""

    if builds > 0:
        try:
            r = await client.get(
                f"{url}lastBuild/api/json?tree=number,result,timestamp,actions[text,parameters[name,value]]",
                timeout=15,
            )
            r.raise_for_status()
            d = r.json()
            last_num = d.get("number")
            build_result = (d.get("result") or "").upper()
            ts = d.get("timestamp")
            if ts:
                last_date = datetime.fromtimestamp(ts / 1000).strftime("%Y-%m-%d %H:%M")
            rp_url = _extract_rp_url(d)
            pmap = _param_map_from_build(d)
            cluster_short = _extract_short_cluster_from_map(pmap)
            cluster_url = _extract_cluster_url_from_map(pmap)
            cnv_bundle = _extract_cnv_bundle_from_map(pmap)
            cluster_password = _extract_cluster_password_from_map(pmap)
        except Exception:
            pass

        try:
            r = await client.get(
                f"{url}lastBuild/testReport/api/json?tree=totalCount,passCount,failCount,skipCount",
                timeout=15,
            )
            r.raise_for_status()
            d = r.json()
            passed = d.get("passCount", 0)
            failed = d.get("failCount", 0)
            skipped = d.get("skipCount", 0)
            total = d.get("totalCount", 0)
            if total == 0:
                total = passed + failed + skipped
        except Exception:
            pass

        if last_num is not None and (
            not cluster_url or not cnv_bundle or not cluster_password
        ):
            console_url = f"{url.rstrip('/')}/{last_num}/consoleText"
            cu, cb, cpw = await _scan_console_for_hints(
                client,
                console_url,
                want_bridge=not bool(cluster_url),
                want_bundle=not bool(cnv_bundle),
                want_password=not bool(cluster_password),
            )
            if not cluster_url and cu:
                cluster_url = cu
            if not cnv_bundle and cb:
                cnv_bundle = cb
            if not cluster_password and cpw:
                cluster_password = cpw

        if not cluster_short and cluster_url:
            cluster_short = _short_cluster_from_console_url(cluster_url)
        cluster_short = _normalize_cluster_short_display(cluster_short)

    return (
        builds,
        last_num,
        last_date,
        total,
        passed,
        failed,
        skipped,
        build_result,
        rp_url,
        cluster_short,
        cluster_url,
        cnv_bundle,
        cluster_password,
    )


async def fetch_all(rows):
    import httpx

    auth = httpx.BasicAuth(USERNAME, TOKEN) if USERNAME and TOKEN else None
    sem = asyncio.Semaphore(10)

    async def limited(job_url: str):
        async with sem:
            return await fetch_job(client, job_url)

    async with httpx.AsyncClient(auth=auth, verify=VERIFY_SSL) as client:
        results = await asyncio.gather(*[limited(r["job_url"]) for r in rows])
    return results


def write_jobs_md(lines, rows, results):
    for row, (builds, last_num, last_date, total, passed, failed, skipped, _br, _rp_url, _cl, _cu, _cb, _cp) in zip(
        rows, results
    ):
        if builds > 0 and last_num is not None:
            builds_col = f"[{builds}]({row['job_url']}{last_num})"
        elif builds > 0:
            builds_col = str(builds)
        else:
            builds_col = "0"

        if total is not None:
            results_col = f"**{total}** \\| **{passed}** \\| **{failed}** \\| **{skipped}**"
        else:
            results_col = "-"

        cnv_display = row["cnv"] if row is rows[0] or row["cnv"] != rows[rows.index(row) - 1]["cnv"] else ""
        lines[row["line_idx"]] = f"| {cnv_display} | {row['job_link']} | {builds_col} | {last_date} | {results_col} |"

    with open(JOBS_MD, "w") as f:
        f.write("\n".join(lines) + "\n")


def build_html_data(rows, results):
    data = []
    for row, (
        builds,
        last_num,
        last_date,
        total,
        passed,
        failed,
        skipped,
        build_result,
        rp_url,
        cluster_short,
        cluster_url,
        cnv_bundle,
        cluster_password,
    ) in zip(rows, results):
        data.append({
            "cnv": row["cnv"],
            "job_name": row["job_name"],
            "job_url": row["job_url"],
            "builds": builds,
            "builds_url": f"{row['job_url']}{last_num}" if builds > 0 and last_num else "",
            "artifact_url": f"{row['job_url']}{last_num}/artifact/" if builds > 0 and last_num else "",
            "cluster_short": cluster_short,
            "cluster_url": cluster_url,
            "cnv_bundle": cnv_bundle,
            "cluster_password": cluster_password,
            "build_result": build_result,
            "framework": framework_from_cnv(row["cnv"]),
            "rp_url": rp_url,
            "last": last_date,
            "total": total,
            "passed": passed,
            "failed": failed,
            "skipped": skipped,
        })
    return data


def write_jobs_html(data, scan_time):
    os.makedirs(JOBS_DIR, exist_ok=True)
    filename = f"jobs-{scan_time.strftime('%Y-%m-%d-%H-%M-%S')}.html"
    html_path = os.path.join(JOBS_DIR, filename)
    data_json = json.dumps(data)
    copy_icon_js = json.dumps(COPY_ICON_DATA_URI)
    count = len(data)
    scan_str = scan_time.strftime("%Y-%m-%d %H:%M:%S")

    html = f"""<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title>Test jobs report</title>
<style>
  :root {{
    --bg: #1a1b26; --bg2: #24263a; --bg3: #2f3146;
    --text: #c0caf5; --text-dim: #565f89; --border: #3b3d57;
    --green: #9ece6a; --red: #f7768e; --yellow: #e0af68;
    --blue: #7aa2f7; --cyan: #7dcfff; --orange: #ff9e64;
  }}
  * {{ margin: 0; padding: 0; box-sizing: border-box; }}
  body {{
    font-family: 'SF Mono', 'Cascadia Code', 'JetBrains Mono', 'Fira Code', monospace;
    background: var(--bg); color: var(--text);
    padding: 2rem; line-height: 1.5;
  }}
  h1 {{
    font-size: 1.4rem; font-weight: 600;
    color: #fff; letter-spacing: -0.02em;
  }}
  h1 .count {{
    color: inherit; font-weight: 400; font-size: 0.85rem; margin-left: 0.8rem;
  }}
  h1 .scan-time {{
    color: inherit; font-size: 0.72rem; margin-left: 1rem; font-weight: 400;
  }}
  table {{
    width: 100%; border-collapse: collapse;
    font-size: 0.82rem;
  }}
  thead {{ position: sticky; top: 0; z-index: 10; }}
  th {{
    background: var(--bg2); color: var(--text);
    padding: 0.6rem 0.8rem; text-align: left;
    font-weight: 600; font-size: 0.72rem;
    text-transform: uppercase; letter-spacing: 0.08em;
    border-bottom: 2px solid var(--border);
    white-space: nowrap; user-select: none;
  }}
  th.sortable {{ cursor: pointer; }}
  th.sortable:hover {{ color: var(--cyan); }}
  th .arrow {{ display: inline-block; margin-left: 0.3rem; font-size: 0.65rem; opacity: 0.5; }}
  th.asc .arrow::after {{ content: '\\25B2'; opacity: 1; }}
  th.desc .arrow::after {{ content: '\\25BC'; opacity: 1; }}
  th:not(.asc):not(.desc) .arrow::after {{ content: '\\25B4'; }}
  td {{
    padding: 0.45rem 0.8rem;
    border-bottom: 1px solid var(--border);
    vertical-align: middle;
  }}
  tr.row-fail td {{ background: #0f0000; }}
  tr.row-pass td {{ background: #000700; }}
  tr.row-fail:hover td {{ background: #120000; }}
  tr.row-pass:hover td {{ background: #001200; }}
  tr:hover:not(.row-fail):not(.row-pass) td {{ background: var(--bg3); }}
  tr.cnv-first td {{ border-top: 2px solid var(--border); }}
  .cnv {{ font-weight: 700; color: var(--cyan); font-size: 0.9rem; }}
  a {{ color: var(--blue); text-decoration: none; }}
  a:hover {{ text-decoration: underline; color: var(--cyan); }}
  .builds {{ text-align: right; color: var(--text-dim); }}
  .builds a {{ color: var(--text-dim); }}
  .builds a:hover {{ color: var(--cyan); }}
  .last {{ white-space: nowrap; color: var(--text-dim); }}
  .last.recent {{ color: var(--green); }}
  .last.stale {{ color: var(--yellow); }}
  .last.old {{ color: var(--red); opacity: 0.7; }}
  .results {{ white-space: nowrap; }}
  .r-total {{ color: var(--text); font-weight: 600; }}
  .r-passed {{ color: var(--green); font-weight: 600; }}
  .r-failed {{ color: var(--red); font-weight: 600; }}
  .r-skipped {{ color: var(--yellow); font-weight: 600; }}
  .r-zero {{ opacity: 0.35; }}
  .na {{ color: var(--text-dim); opacity: 0.4; }}
  .copy-btn {{
    background: none; border: none; cursor: pointer;
    padding: 0 0 0 0.4rem; vertical-align: middle;
    opacity: 0.4; transition: opacity 0.15s;
    line-height: 1;
  }}
  .copy-btn:hover {{ opacity: 1; }}
  .copy-btn.copied {{ opacity: 1; }}
  .copy-btn img {{ width: 14px; height: 14px; display: inline-block; vertical-align: -2px; }}
  .rp a {{ color: var(--orange); font-weight: 600; font-size: 0.78rem; }}
  .rp a:hover {{ color: var(--cyan); }}
  .fw {{ text-align: center; font-weight: 700; font-size: 0.85rem; letter-spacing: 0.04em; }}
  .fw a {{ color: var(--cyan); text-decoration: none; }}
  .fw a:hover {{ text-decoration: underline; color: #fff; }}
  .cluster-short {{
    white-space: nowrap; max-width: 14rem; overflow: hidden; text-overflow: ellipsis;
    color: var(--text-dim); font-size: 0.8rem;
  }}
  a.cluster-link {{ color: var(--blue); }}
  a.cluster-link:hover {{ color: var(--cyan); }}
  .cluster-pw {{ display: none !important; }}
  .copy-pw-btn {{ margin: 0 0.15rem; vertical-align: -2px; }}
  .header-row {{ display: flex; align-items: center; gap: 1.5rem; margin-bottom: 1.5rem; flex-wrap: wrap; }}
  .header-row .toggle {{
    display: flex; align-items: flex-end; gap: 0.5rem; font-size: 0.78rem;
    color: var(--blue); cursor: pointer; user-select: none; white-space: nowrap;
    transition: color 0.15s ease;
  }}
  .header-row .toggle:hover {{ color: #fff; }}
  .header-row .toggle:hover .filter-count {{ color: #fff; opacity: 1; }}
  .filter-count {{ font-size: 0.72rem; opacity: 0.85; }}
  .switch {{ position: relative; width: 34px; height: 18px; flex-shrink: 0; }}
  .switch input {{ opacity: 0; width: 0; height: 0; }}
  .slider {{ position: absolute; inset: 0; background: var(--bg3); border-radius: 9px; transition: background 0.2s; }}
  .slider::before {{ content: ''; position: absolute; left: 2px; top: 2px; width: 14px; height: 14px; background: var(--text-dim); border-radius: 50%; transition: transform 0.2s, background 0.2s; }}
  .switch input:checked + .slider {{ background: var(--red); }}
  .switch input:checked + .slider::before {{ transform: translateX(16px); background: var(--text); }}
</style>
</head>
<body>
<div class="header-row">
<h1>Test jobs report <span class="count">{count} jobs</span><span class="scan-time">scanned {scan_str}</span></h1>
<label class="toggle"><span class="switch"><input type="checkbox" id="hidePass"><span class="slider"></span></span>Failures only <span id="failCount" class="filter-count"></span></label>
<label class="toggle"><span class="switch"><input type="checkbox" id="hideTiers"><span class="slider"></span></span>Hide tiers <span id="hideTiersCount" class="filter-count"></span></label>
<label class="toggle"><span class="switch"><input type="checkbox" id="hideGating"><span class="slider"></span></span>Hide gating <span id="hideGatingCount" class="filter-count"></span></label>
</div>
<table id="tbl">
<thead>
<tr>
  <th class="sortable" data-col="cnv" data-type="version">CNV <span class="arrow"></span></th>
  <th>Lane</th>
  <th>Cluster</th>
  <th>📦</th>
  <th>#</th>
  <th>RP</th>
  <th class="sortable" data-col="last" data-type="date">Last <span class="arrow"></span></th>
  <th>📁</th>
  <th>✅</th>
  <th class="sortable" data-col="failed" data-type="num">❌ <span class="arrow"></span></th>
  <th>⚠️</th>
</tr>
</thead>
<tbody id="tbody"></tbody>
</table>
<script>
const COPY_ICON = {copy_icon_js};
const DATA = {data_json};
const now = Date.now();
const DAY = 86400000;

function ageClass(dateStr) {{
  if (!dateStr || dateStr === 'N/A') return 'na';
  const d = new Date(dateStr.replace(' ', 'T'));
  const age = now - d.getTime();
  if (age < 2 * DAY) return 'recent';
  if (age < 14 * DAY) return '';
  if (age < 60 * DAY) return 'stale';
  return 'old';
}}

function numCell(val, cls) {{
  if (val === null || val === undefined) return '<span class="na">-</span>';
  const zeroClass = val === 0 ? ' r-zero' : '';
  return `<span class="${{cls}}${{zeroClass}}">${{val}}</span>`;
}}

function escapeHtml(s) {{
  return String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;');
}}

function clusterPasswordSpan(pw) {{
  const t = (pw != null && String(pw).trim() !== '') ? String(pw).trim() : '';
  if (!t) return '';
  return `<span class="cluster-pw" hidden aria-hidden="true">${{escapeHtml(t)}}</span>`;
}}

function copyClusterPassword(btn) {{
  let text = '';
  if (btn.dataset && btn.dataset.pw != null && btn.dataset.pw !== '') {{
    try {{ text = decodeURIComponent(btn.dataset.pw); }} catch (e) {{ text = ''; }}
  }}
  if (!text) {{
    const td = btn.closest('td');
    const span = td && td.querySelector('.cluster-pw');
    text = span && span.textContent ? span.textContent.trim() : '';
  }}
  if (!text) return;
  navigator.clipboard.writeText(text).then(() => {{
    btn.setAttribute('title', 'Copied');
    setTimeout(() => btn.setAttribute('title', 'Copy password'), 1400);
  }});
}}

function render(rows) {{
  const tbody = document.getElementById('tbody');
  let html = '';
  let prevCnv = '';
  for (const r of rows) {{
    const cnvFirst = r.cnv !== prevCnv;
    const buildFailed = (r.failed !== null && r.failed > 0)
      || (r.failed === null && r.build_result === 'FAILURE');
    const statusClass = buildFailed ? 'row-fail'
      : (r.failed !== null && r.failed === 0 ? 'row-pass' : '');
    const trClasses = [cnvFirst ? 'cnv-first' : '', statusClass].filter(Boolean).join(' ');
    const trAttr = trClasses ? ` class="${{trClasses}}"` : '';
    prevCnv = r.cnv;
    const cnvCell = r.cnv ? `<span class="cnv">${{r.cnv}}</span>` : '';
    const jobCell = `<a href="${{r.job_url}}" target="_blank">${{r.job_name}}</a>`;
    const clusterTitle = (r.cluster_short || r.cluster_url || '').replace(/"/g, '&quot;');
    const cnvVer = (r.cnv_bundle != null && String(r.cnv_bundle).trim() !== '') ? String(r.cnv_bundle).trim() : '';
    const cnvBracket = cnvVer ? (' [' + cnvVer + ']') : '';
    const pwRaw = (r.cluster_password != null && String(r.cluster_password).trim() !== '')
      ? String(r.cluster_password).trim() : '';
    const copyPwBtn = pwRaw
      ? `<button type="button" class="copy-btn copy-pw-btn" title="Copy password" aria-label="Copy password" data-pw="${{encodeURIComponent(pwRaw)}}" onclick="copyClusterPassword(this)"><img src="${{COPY_ICON}}" alt=""></button>`
      : '';
    let clusterCell;
    if (r.cluster_url) {{
      const label = r.cluster_short || (() => {{
        try {{ return new URL(r.cluster_url).hostname.split('.')[0] || 'console'; }}
        catch (e) {{ return 'console'; }}
      }})();
      clusterCell = `<a class="cluster-short cluster-link" href="${{r.cluster_url}}" target="_blank" rel="noopener noreferrer" title="${{clusterTitle}}">${{label}}</a>${{copyPwBtn}}${{cnvBracket}}`;
    }} else if (r.cluster_short) {{
      clusterCell = `<span class="cluster-short" title="${{clusterTitle}}">${{r.cluster_short}}</span>${{copyPwBtn}}${{cnvBracket}}`;
    }} else {{
      clusterCell = '<span class="na">-</span>' + copyPwBtn + cnvBracket;
    }}
    clusterCell += clusterPasswordSpan(r.cluster_password);
    const neverRan = !r.builds_url && r.last === 'N/A';
    const fwCell = neverRan
      ? '<span class="na">-</span>'
      : (r.artifact_url
        ? `<a href="${{r.artifact_url}}" target="_blank" title="Last build artifacts">${{r.framework}}</a>`
        : `<span title="No last build">${{r.framework}}</span>`);
    const copyBtn = r.builds_url
      ? `<button class="copy-btn" title="Copy URL" onclick="copyUrl(this,'${{r.builds_url}}')"><img src="${{COPY_ICON}}"></button>`
      : '';
    const buildsCell = neverRan
      ? '<span class="na">0</span>'
      : (r.builds_url
        ? `<a href="${{r.builds_url}}" target="_blank">${{r.builds}}</a>${{copyBtn}}`
        : (r.builds > 0 ? r.builds : '<span class="na">0</span>'));
    const rpCell = r.rp_url
      ? `<a href="${{r.rp_url}}" target="_blank">RP</a>`
      : '<span class="na">-</span>';
    const ac = ageClass(r.last);
    const lastCell = r.last === 'N/A'
      ? '<span class="na">N/A</span>'
      : `<span class="last ${{ac}}">${{r.last}}</span>`;
    html += `<tr${{trAttr}}>
      <td>${{cnvCell}}</td>
      <td>${{jobCell}}</td>
      <td>${{clusterCell}}</td>
      <td class="fw">${{fwCell}}</td>
      <td class="builds">${{buildsCell}}</td>
      <td class="rp">${{rpCell}}</td>
      <td>${{lastCell}}</td>
      <td class="results">${{buildFailed && r.total === null ? '<span class="r-failed">FAILED</span>' : numCell(r.total, 'r-total')}}</td>
      <td class="results">${{numCell(r.passed, 'r-passed')}}</td>
      <td class="results">${{numCell(r.failed, 'r-failed')}}</td>
      <td class="results">${{numCell(r.skipped, 'r-skipped')}}</td>
    </tr>`;
  }}
  tbody.innerHTML = html;
}}

function copyUrl(btn, url) {{
  navigator.clipboard.writeText(url).then(() => {{
    btn.classList.add('copied');
    btn.innerHTML = '&#x2713;';
    setTimeout(() => {{ btn.classList.remove('copied'); btn.innerHTML = `<img src="${{COPY_ICON}}">`; }}, 1200);
  }});
}}

let sortCol = null, sortDir = 'asc', sortType = null;
let hidePass = false;
let hideTiers = false;
let hideGating = false;

function isGating(r) {{
  return r.job_name.includes('[GATE]');
}}

function getRows() {{
  let rows = [...DATA];
  if (hidePass) rows = rows.filter(r =>
    (r.failed !== null && r.failed > 0) || (r.failed === null && r.build_result === 'FAILURE')
  );
  if (hideTiers) rows = rows.filter(r => isGating(r));
  if (hideGating) rows = rows.filter(r => !isGating(r));
  if (sortCol) {{
    rows.sort((a, b) => {{
      let va = a[sortCol], vb = b[sortCol];
      if (sortType === 'version') {{ va = parseFloat(va) || 0; vb = parseFloat(vb) || 0; }}
      else if (sortType === 'num') {{ va = (va ?? -1); vb = (vb ?? -1); }}
      else if (sortType === 'date') {{ va = va === 'N/A' ? '0' : va; vb = vb === 'N/A' ? '0' : vb; }}
      if (va < vb) return sortDir === 'asc' ? -1 : 1;
      if (va > vb) return sortDir === 'asc' ? 1 : -1;
      return 0;
    }});
  }}
  return rows;
}}

function refresh() {{
  const rows = getRows();
  document.querySelector('.count').textContent = `${{rows.length}} jobs`;
  document.getElementById('failCount').textContent = `[${{DATA.filter(r => r.failed !== null && r.failed > 0).length}}]`;
  document.getElementById('hideTiersCount').textContent = `[${{DATA.filter(r => isGating(r)).length}}]`;
  document.getElementById('hideGatingCount').textContent = `[${{DATA.filter(r => !isGating(r)).length}}]`;
  render(rows);
}}

function sortData(col, type) {{
  if (sortCol === col) {{ sortDir = sortDir === 'asc' ? 'desc' : 'asc'; }}
  else {{ sortCol = col; sortType = type; sortDir = 'desc'; }}
  document.querySelectorAll('th.sortable').forEach(th => {{
    th.classList.remove('asc', 'desc');
    if (th.dataset.col === col) th.classList.add(sortDir);
  }});
  refresh();
}}

document.querySelectorAll('th.sortable').forEach(th => {{
  th.addEventListener('click', () => sortData(th.dataset.col, th.dataset.type));
}});
document.getElementById('hidePass').addEventListener('change', (e) => {{
  hidePass = e.target.checked;
  refresh();
}});
document.getElementById('hideTiers').addEventListener('change', (e) => {{
  hideTiers = e.target.checked;
  refresh();
}});
document.getElementById('hideGating').addEventListener('change', (e) => {{
  hideGating = e.target.checked;
  refresh();
}});
refresh();
</script>
</body>
</html>"""

    with open(html_path, "w") as f:
        f.write(html)
    return html_path


async def main():
    scan_time = datetime.now()
    print(f"Scanning jobs at {scan_time.strftime('%Y-%m-%d %H:%M:%S')}...")

    lines, header_lines, rows = parse_jobs_md()
    print(f"Found {len(rows)} jobs in jobs.md")

    results = await fetch_all(rows)

    with_data = sum(1 for b, *_ in results if b > 0)
    print(f"Fetched data for {with_data}/{len(rows)} jobs")

    if with_data == 0:
        print("ERROR: No data fetched from Jenkins (network issue?). Files not updated.")
        return

    write_jobs_md(lines, rows, results)
    print(f"Updated {JOBS_MD}")

    html_data = build_html_data(rows, results)
    html_path = write_jobs_html(html_data, scan_time)
    print(f"Generated {html_path}")


if __name__ == "__main__":
    asyncio.run(main())
