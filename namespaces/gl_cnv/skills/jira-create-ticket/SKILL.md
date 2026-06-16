---
name: jira-create-ticket
description: Search and create JIRA tickets for CNV project. Use when the user asks to create a bug, search JIRA, or when jenkins-investigate-job finds an environment failure.
---

# jira-create-ticket

Credentials: `~/.config/jira/token` (format: `email=...` and `jira_token=...`).
All calls use Basic auth (`-u "email:token"`) against `https://redhat.atlassian.net/rest/api/3/`.

## Steps

1. **Search first** — always check before creating:
   `GET /search/jql?jql=project=CNV AND summary ~ "keyword" AND status not in (Closed)&maxResults=5&fields=summary,status,assignee`
   If match exists, report it and stop.

2. **Look up accountIds** for reporter/assignee (username does not work in api/3):
   `GET /user/search?query=<name_or_email>` → extract `accountId`

3. **Create ticket:**
   `POST /issue` with fields: `project.key=CNV`, `summary`, `issuetype.name=Bug`, `description` (ADF format), optionally `reporter.accountId`, `assignee.accountId`, `components`, `labels`.

## ADF description format

api/3 uses Atlassian Document Format, not wiki markup:

```json
{"type": "doc", "version": 1, "content": [
  {"type": "heading", "attrs": {"level": 2}, "content": [{"type": "text", "text": "Summary"}]},
  {"type": "paragraph", "content": [{"type": "text", "text": "..."}]},
  {"type": "codeBlock", "content": [{"type": "text", "text": "log lines"}]},
  {"type": "bulletList", "content": [
    {"type": "listItem", "content": [{"type": "paragraph", "content": [
      {"type": "text", "text": "link text", "marks": [{"type": "link", "attrs": {"href": "url"}}]}
    ]}]}
  ]}
]}
```

## Ticket templates

Pick the template based on failure type from `jenkins-investigate-job`.
Component names in templates follow `team` values from `cnv-tasks-*.yaml` schema (`x-team-attributes`).
Before creating a ticket, verify the component exists: `GET /project/CNV/components` and pick the closest match.

- **Environment failure** → [templates/infra-failure.md](templates/infra-failure.md)
  Deploy, cluster, DNS, registry, quota, Jenkins OOM, missing tools.
- **Test failure** → [templates/test-failure.md](templates/test-failure.md)
  Test ran and failed on assert, timeout, or unexpected behavior.
- **Other / unclear** → Use the infra-failure template as a base, adjust the Summary and Component to match the actual failure.

## Pitfalls

- Old `issues.redhat.com` redirects — always use `redhat.atlassian.net` directly.
- Old api/2 `"reporter": {"name": "..."}` does not work — api/3 requires `accountId`.
- Token: generate at [id.atlassian.com/manage-profile/security/api-tokens](https://id.atlassian.com/manage-profile/security/api-tokens).
