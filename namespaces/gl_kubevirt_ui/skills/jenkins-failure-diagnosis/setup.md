# Jenkins Failure Diagnosis MCP — Setup

## 1. Install Dependencies

From the repository root (or using the path to this skill inside your clone):

```bash
cd .cursor/skills/jenkins-failure-diagnosis/mcp-server
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## 2. Get Your Jenkins API Token

1. Log in to your Jenkins instance
2. Click your username (top right) → Configure
3. Under **API Token**, click "Add new Token"
4. Name it (e.g. `cursor-mcp`), click Generate, and copy the value

## 3. Configure in Cursor

Add the following to your Cursor MCP settings. For a **project-local** server, use `.cursor/mcp.json` in this repository (merge with existing `mcpServers` entries).

Use an absolute path, or `${workspaceFolder}` if your Cursor build expands it in MCP config:

```json
{
  "mcpServers": {
    "jenkins-failure-diagnosis": {
      "command": "${workspaceFolder}/.cursor/skills/jenkins-failure-diagnosis/mcp-server/.venv/bin/python",
      "args": [
        "${workspaceFolder}/.cursor/skills/jenkins-failure-diagnosis/mcp-server/server.py"
      ],
      "env": {
        "JENKINS_URL": "https://jenkins.your-company.com",
        "JENKINS_USER": "your-username",
        "JENKINS_TOKEN": "your-api-token",
        "JENKINS_VERIFY_SSL": "true"
      }
    }
  }
}
```

If `${workspaceFolder}` is not expanded, replace it with the full path to this repository (e.g. `/Users/you/dev/kubevirt-ui-pw`).

Set `JENKINS_VERIFY_SSL` to `false` if your corporate Jenkins uses a self-signed certificate.

## 4. Verify

Restart Cursor (or reload the window). The MCP tools should appear when you ask the agent to diagnose a Jenkins build. You can verify by asking:

> "Use the get_build_info tool to check https://jenkins.example.com/job/my-job/123"

## Troubleshooting

- **"Missing Jenkins credentials"** — Ensure all three env vars are set in `mcp.json`
- **401 Unauthorized** — Token may be expired; regenerate in Jenkins
- **Connection refused** — Check `JENKINS_URL` is reachable from your machine; check VPN
- **SSL errors** — Set `JENKINS_VERIFY_SSL=false` or add your corporate CA to the system trust store
