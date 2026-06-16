# Ticket Lifecycle: Multi-Version Process Checklist

Analyze a Jira ticket and produce a structured process checklist covering version verification, backport status, build availability, and validation steps to follow — output as a markdown file for manual reading.

## Input

```
/ticket-lifecycle <CNV-XXXXX> [options]
```

- **Single ticket**: `/ticket-lifecycle CNV-91234`
- **With coverage check**: `/ticket-lifecycle CNV-91234 --coverage`

### Options

| Option | Effect |
|--------|--------|
| *(none)* | Full analysis: version matrix → clone status → build verification → process checklist |
| `--coverage` | Also check what existing test automation coverage the framework has for this area |

Examples:
```
/ticket-lifecycle CNV-91234
/ticket-lifecycle CNV-91234 --coverage
```

## Workflow

---

### Phase 0: Ticket Fetch & Version Matrix

1. **Fetch the Jira ticket**:
   - Call `get_ticket` from `kubevirt-ui-mcp`
   - **Fallback**:
     ```bash
     curl -s -L "https://issues.redhat.com/rest/api/2/issue/{TICKET_KEY}" | python3 -c "
     import sys, json
     data = json.load(sys.stdin)
     fields = data.get('fields', {})
     print(f'Key: {data.get(\"key\")}')
     print(f'Summary: {fields.get(\"summary\")}')
     print(f'Type: {fields.get(\"issuetype\", {}).get(\"name\")}')
     print(f'Status: {fields.get(\"status\", {}).get(\"name\")}')
     print(f'Fix Versions: {[v.get(\"name\") for v in fields.get(\"fixVersions\", [])]}')
     print(f'Labels: {fields.get(\"labels\", [])}')
     links = fields.get('issuelinks', [])
     for l in links:
         lt = l.get('type', {}).get('name', '')
         inward = l.get('inwardIssue', {}).get('key', '')
         outward = l.get('outwardIssue', {}).get('key', '')
         print(f'Link: {lt} → {inward or outward}')
     "
     ```

2. **Extract fix versions** — identify primary (latest) and backport (older) versions

3. **Fetch linked PRs**:
   ```bash
   curl -s -L "https://issues.redhat.com/rest/api/2/issue/{TICKET_KEY}/remotelink" | python3 -c "
   import sys, json
   links = json.load(sys.stdin)
   for link in links:
       obj = link.get('object', {})
       url = obj.get('url', '')
       title = obj.get('title', '')
       if 'github.com' in url and 'pull' in url:
           print(f'PR: {title} — {url}')
   "
   ```

---

### Phase 1: Clone & Build Verification

1. **Search for existing backport clones** via Jira issue links (`is cloned by` / `clones` relationships)

2. **Query the CNV Version Explorer** for each linked PR:
   ```
   https://cnv-version-explorer.apps.cnv2.engineering.redhat.com/?cPRs={PR_NUMBER}&cName=kubevirt-console-plugin
   ```
   Use `WebFetch` to check which CNV build versions include the PR.

3. **Build the version × clone × build matrix**

---

### Phase 2: Coverage Check (only with `--coverage`)

1. Call `find_tests_by_jira` with the ticket key
2. Call `get_coverage_for_feature` with keywords from the ticket summary
3. Call `search_tests` with relevant terms
4. Summarize: what specs exist, what tier, what's covered vs not

---

### Phase 3: Report Generation

Write the checklist to `playwright/product-analysis/ticket-lifecycle-<TICKET>.md`.

---

## Report Format

```markdown
# Ticket Lifecycle Checklist: <TICKET_KEY>

**Generated:** YYYY-MM-DD
**Ticket:** <summary>
**Type:** Bug / Story / Task
**Status:** <current-status>

---

## Version Matrix

| Fix Version | Role | Clone Ticket | Clone Status | Build Available | Build Tag |
|-------------|------|--------------|--------------|-----------------|-----------|
| CNV-4.19.0 | Primary | <TICKET> | <status> | ✅ / ❌ / ⏳ | v4.19.0-XX |
| CNV-4.18.3 | Backport | CNV-YYYYY | <status> | ✅ / ❌ / ⏳ | v4.18.3-YY |
| CNV-4.17.5 | Backport | ⚠ Missing | — | — | — |

**PRs:** #NNNN (kubevirt-console-plugin)
**Version Explorer:** [link](<explorer-url>)

---

## Action Items

### Backport Clones
- [ ] Verify clone exists for CNV-4.18.3 → CNV-YYYYY ✅
- [ ] Create clone for CNV-4.17.5 (missing)
  - Go to: https://redhat.atlassian.net/browse/<TICKET>
  - Clone → set Fix Version to CNV-4.17.5

### Build Verification
- [ ] Confirm PR #NNNN is merged to release-4.19 branch
- [ ] Confirm PR backport is merged to release-4.18 branch
- [ ] Confirm PR backport exists for release-4.17 branch (⚠ not found)
- [ ] Verify build via: [CNV Version Explorer](<url>)

### Validation (per version)
For each version where build is available:

#### CNV-4.19.0
- [ ] Deploy/access a cluster running CNV 4.19.x
- [ ] Verify plugin image: `oc -n openshift-cnv get deployment kubevirt-console-plugin -o jsonpath='{.spec.template.spec.containers[0].image}'`
- [ ] Reproduce the original issue (for bugs) / navigate to the feature (for stories)
- [ ] Verify the fix/feature works as described in the ticket
- [ ] Check console for JS errors
- [ ] Capture screenshot evidence
- [ ] Post Jira comment on <TICKET> with:
  - Cluster name + OCP version + CNV version + plugin image tag
  - Steps performed
  - Evidence (screenshots/screen recording)
- [ ] Transition <TICKET> to MODIFIED

#### CNV-4.18.3
- [ ] Deploy/access a cluster running CNV 4.18.x
- [ ] OR override plugin image: `oc -n openshift-cnv set image deployment/kubevirt-console-plugin console-plugin=<image:tag>`
- [ ] Verify the fix/feature works as in primary version
- [ ] Post Jira comment on CNV-YYYYY with proof
- [ ] Transition CNV-YYYYY to MODIFIED

#### CNV-4.17.5
- [ ] ⏳ Blocked — no build available yet / no clone exists

---

## Existing Test Coverage (if --coverage)

| Area | Spec File | Tier | Tests | Relevant |
|------|-----------|------|-------|----------|
| <feature> | tests/tier1/... | tier1 | 5 | Partial — covers X but not Y |

**Coverage verdict:** [Full / Partial / None]
- Covered: <what existing tests validate>
- Gap: <what the ticket changes that no test covers>

---

## Jira Comment Template

Use this when posting validation proof:

```
h3. QE Validation — <VERSION>

*Cluster:* <cluster-name>
*OCP:* <ocp-version>
*CNV:* <cnv-version>
*Plugin image:* {{<image:tag>}}
*Date:* <date>

# <step-1> — ✓
# <step-2> — ✓

*Verdict:* PASS

Tested with build from PR [#NNNN|<pr-url>].
```
```

## Rules

- **Read-only** — this command only produces a checklist markdown file. It does not:
  - Create or modify Jira tickets
  - Deploy clusters or update images
  - Run browser validation
  - Write test code
- **Output location** — `playwright/product-analysis/ticket-lifecycle-<TICKET>.md` (gitignored)
- **Evidence-based** — only mark items as ✅ if verifiable from Jira/Explorer data
- **Incomplete is OK** — if builds aren't ready or clones are missing, flag them as blocked items
- Use `kubevirt-ui-mcp` tools first, fallback to curl only on error
- URL-encode JQL via `python3 -c "import urllib.parse; ..."`
