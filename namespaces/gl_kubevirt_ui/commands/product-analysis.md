# Product Analysis: Documentation vs Active Development

Cross-reference OpenShift Virtualization product documentation with active Jira tickets to surface risks, limitations, coverage gaps, and concerns for the CNV User Interface.

## Input

The user invokes `/product-analysis` with optional focus areas:

- **No arguments**: Full analysis across all doc sections and active tickets
- **With focus**: `/product-analysis networking` or `/product-analysis storage migration`

### Options

| Option | Effect |
|--------|--------|
| *(none)* | Full analysis — top 10 findings across all domains |
| `--focus <area>` | Limit analysis to specific documentation domains |
| `--tickets-only` | Skip doc fetch, analyze only active tickets against cached docs |
| `--refresh` | Force `refresh_store` before analysis |

Examples:
```
/product-analysis
/product-analysis --focus networking storage
/product-analysis --refresh
/product-analysis --focus migration --tickets-only
```

## Workflow

Follow the `product-analyst.mdc` rule for full instructions. Summary:

---

### Phase 0: Data Gathering

1. **Fetch active CNV UI tickets** via Jira REST API:
   ```
   project = "CNV"
   AND component = "CNV User Interface"
   AND status IN (New, ON_QA, "Dev Complete", POST, Planning, "In Progress", MODIFIED)
   ```
   - Paginate with `startAt` if > 50 results
   - Extract: key, summary, status, type, labels, fixVersions, description (first 500 chars)

2. **Fetch product documentation** via `kubevirt-ui-mcp`:
   - Call `list_product_doc_sections` for the full index
   - Fetch priority sections: `supported-limits`, `networking-overview`, `storage-overview`, `migration-about`, `migration-configuring`, `release-notes-4-22`, `requirements`, `troubleshooting`
   - If `--focus` is provided, fetch only sections matching the focus area tags

3. **Check test coverage** via `get_tier_distribution` for baseline context

---

### Phase 1: Documentation Analysis

Extract from each fetched section:
- Hard limitations and maximums
- Required prerequisites (feature gates, operators, storage, network)
- Known issues and workarounds
- Behavioral constraints and unsupported combinations

---

### Phase 2: Cross-Reference

For each active ticket, map to documentation:
- Which doc sections are relevant?
- Does the feature have documented limitations?
- Are those limitations covered by existing tests?
- Is the ticket's setup complexity reflected in CI capabilities?

Use `find_tests_by_jira`, `get_coverage_for_feature`, and `search_tests` to assess coverage.

---

### Phase 3: Score and Rank

Apply risk scoring (Impact 40%, Likelihood 30%, Coverage Gap 30%) to produce the top 10.

---

### Phase 4: Report

Generate the report following the format in `product-analyst.mdc` and write to:
```
playwright/product-analysis/report-YYYY-MM-DD.md
```

---

## Output

The report is written to `playwright/product-analysis/` (gitignored — not committed to source control).

Each run produces a timestamped file: `report-YYYY-MM-DD.md`

The report contains:
- Executive summary
- Top 10 prioritized findings with risk scores
- For each finding: doc reference, affected tickets, current coverage, concerns, questions, recommended actions
- Appendix of all analyzed tickets and documentation sections

## Rules

- **Read-only analysis** — do not modify code, tests, or configuration
- **Evidence-based** — every finding must cite both a doc section and a ticket
- **Actionable** — every finding ends with a concrete next step
- Use `kubevirt-ui-mcp` tools first, fallback to curl/grep only on error
- URL-encode JQL queries via `python3 -c "import urllib.parse; ..."`
- If the Jira REST API requires auth, inform the user and use cached data from `search_tickets`
