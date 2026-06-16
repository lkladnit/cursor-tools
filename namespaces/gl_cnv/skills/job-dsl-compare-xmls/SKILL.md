---
name: job-dsl-compare-xmls
description: Compare Jenkins job XMLs between contra/cnv (current) and origin/master baseline. Produces the same summary and HTML report as GitLab CI. Use when the user asks to compare job XMLs, check jobdsl regression, or see what changed in generated jobs.
---

# job-dsl-compare-xmls

Compares generated Jenkins job XMLs the **same way as GitLab CI**: **baseline** = `contra/copy-of-cnv` at `origin/master`, **current** = `contra/cnv` (your tree). Uses `scripts/jobdsl/jobdsl-artifact-diff.sh`.

## When to use

- Check for regressions after Job DSL or execution-wrapper changes
- See exactly which job XMLs changed (same output as CI)
- Before/after comparing job generation locally

## Quick run

From the **contra/cnv** repo root:

```bash
scripts/compare-job-xmls.sh
```

Optional env (defaults in parentheses):

- `CNV_REPO` – current repo (directory containing the script)
- `COPY_REPO` – baseline repo (sibling `../copy-of-cnv`)
- `BASELINE_DIR` – directory for baseline XMLs (`$CNV_REPO/baseline-xmls`)
- `OUTPUT_HTML` – path for diff HTML report (`/tmp/jobdsl-diff.html`)

## What the script does

1. **Baseline (copy-of-cnv):** `git fetch origin && git reset --hard origin/master`; rebuilds if needed; copies `build/debug-xml/jobs/*.xml` into BASELINE_DIR.
2. **Current (cnv):** `rm -rf build && tox -e jobdsl`; XMLs stay in `build/debug-xml/jobs`.
3. **Comparison:** Runs `jobdsl-artifact-diff.sh`; prints [ADDED], [REMOVED], [MODIFIED], [UNCHANGED]; writes HTML report.

## Dependencies

- **diff2html-cli** for HTML report: script uses `npx --yes diff2html-cli` when not on PATH (Node/npm required).

## Script location

`contra/cnv/scripts/compare-job-xmls.sh`
