---
name: jenkins-upload-dev-job
description: Create and upload a dev Jenkins job from Job DSL output. Use when the user asks to create a dev job, upload a dev job, or test changes before merge.
---

# jenkins-upload-dev-job

Creates a dev job XML (SCM pointed to user's fork and branch, triggers removed) and uploads it to Jenkins. Uses `scripts/create-dev-job.sh` and `scripts/update-job.sh`.

## Prerequisites

- **Jenkins token:** Jenkins → your user → Configure → API Token → Add new token. Set `JENKINS_USER` and `JENKINS_TOKEN` (see [skills/README.md](../README.md#prerequisites-jenkins-token-skills-45)).
- **Job XMLs:** Run `tox -e jobdsl` first if `build/debug-xml/jobs/` is missing.

## Instructions

When the user wants a dev job:

1. Ensure `tox -e jobdsl` has been run. If `build/debug-xml/jobs/` is empty, run it.
2. Run:
   ```bash
   export JENKINS_USER="your-user"
   export JENKINS_TOKEN="your-token"
   export REPO_OWNER="your-fork"    # optional; auto-detected from git origin
   export REPO_BRANCH="your-branch"  # optional; auto-detected from current branch
   ./scripts/create-dev-job.sh "JOB_NAME"
   ```
3. Dev job name: `dev-<JOB_NAME>-<USERNAME>` (USERNAME from `$USER` or `$BUILD_USER_ID`).
4. Dry run (no upload): `./scripts/create-dev-job.sh --dry-run "JOB_NAME"`

## Manual upload

If you already have a prepared XML:

```bash
./scripts/update-job.sh build/debug-xml/jobs/dev-JOB_NAME-USERNAME.xml
```

## Reference

[docs/HowToTestChanges.md](../../docs/HowToTestChanges.md)
