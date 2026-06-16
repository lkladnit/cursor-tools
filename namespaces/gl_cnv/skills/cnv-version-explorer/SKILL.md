---
name: cnv-version-explorer
description: Query CNV Version Explorer for bundle and IIB build info using its Swagger/OpenAPI endpoints. Use when the user mentions cnv-version-explorer, version explorer, or asks for IIB build details.
---

# cnv-version-explorer

Public API, no auth required. Base URL: `https://cnv-version-explorer.apps.cnv2.engineering.redhat.com`

## Instructions

When the user asks for CNV Version Explorer data:

1. Pick the appropriate endpoint from the OpenAPI definition (Swagger at `/swagger/`):
   - `GET /GetBuildByIIB?iib_number=<number>`
   - `GET /GetBuildInfo?version=<vX.Y.Z.rhel9-###>`
   - `GET /GetSuccessfulBuildsByVersion?version=<X.Y.Z>&max_entries=<N>&errata_status=<true|false>`
   - `GET /GetBuildsWithErrata?minor_version=<vX.Y>`
   - `GET /GetTestRuns?bundle=<bundle>&test_result=<Completed|Failed>`
   - `GET /CompareBundles?bundle1=<bundle>&bundle2=<bundle>`
   - `GET /GetFirstBuildByPullRequest?pull_request=<url>`
   - `GET /GetUpgradePath?targetVersion=<vX.Y>&channel=<stable|candidate|nightly>`
2. If the response is empty or `null`, report it and suggest verifying the input format (e.g. `v4.16` vs `4.16`, `vX.Y.Z.rhel9-###` for GetBuildInfo).
3. If no listed endpoint matches the user's question, check the Swagger UI at `/swagger/` for additional endpoints not listed here.

## Examples

```bash
curl -s "https://cnv-version-explorer.apps.cnv2.engineering.redhat.com/GetBuildByIIB?iib_number=1097518"
curl -s "https://cnv-version-explorer.apps.cnv2.engineering.redhat.com/GetBuildInfo?version=v4.21.0.rhel9-161"
curl -s "https://cnv-version-explorer.apps.cnv2.engineering.redhat.com/GetSuccessfulBuildsByVersion?version=4.21.0&max_entries=5&errata_status=false"
curl -s "https://cnv-version-explorer.apps.cnv2.engineering.redhat.com/GetUpgradePath?targetVersion=v4.16&channel=stable"
```
