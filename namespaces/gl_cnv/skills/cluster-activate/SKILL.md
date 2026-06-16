---
name: cluster-activate
description: Spawn an interactive shell on the IPI executor with KUBECONFIG set for a cluster. Use when the user asks for kubeconfig access, cluster access, or to run oc commands on a CNV QE cluster.
---

# cluster-activate

Run `scripts/cluster-activate.sh` from the repo to SSH into the IPI executor with `KUBECONFIG` set for the given cluster.

## Instructions

When the user needs kubeconfig or cluster access by cluster name:

1. Run `scripts/cluster-activate.sh CLUSTER_NAME` from the contra/cnv repo root.
2. The script checks SSH access to the IPI executor. If SSH fails:
   - It prints the `~/.ssh/config` snippet if missing.
   - It suggests `ssh-copy-id -i ~/.ssh/cnv-qe-jenkins.key cloud-user@ocp-ipi-executor.rhos-psi.cnv-qe.rhood.us`.
   - Ask the user to run that and retry.
3. On success, the user gets an interactive shell on the executor with `KUBECONFIG` set. They run `oc` commands there.
4. Validate access with `oc whoami` in that shell.
5. Common diagnostic commands:
   - `oc get co` — cluster operators (look for Degraded/Progressing)
   - `oc get nodes` — node Ready/NotReady status
   - `oc get pods -A --field-selector=status.phase!=Running,status.phase!=Succeeded` — problematic pods
   - `oc get events -A --sort-by=.lastTimestamp | tail -50` — recent cluster events
   - `oc get mcp` — MachineConfigPool status (often stuck during upgrades)
   - OCP 4.x OLM commands (not applicable to OCP 5+ with OLM v1):
     - `oc get csv -A` — operator CSV phase (Succeeded/Failed/Pending)
     - `oc get sub -A` — subscriptions and install plan refs
     - `oc get installplan -A` — pending/failed install plans
6. To extract cluster name from a Jenkins build log, look for `CLUSTER_NAME=` or `CLUSTER_DIR=` lines.

## Prerequisites

- SSH key `~/.ssh/cnv-qe-jenkins.key` (obtain from CNV QE team; see [cluster-connection-guide](https://gitlab.cee.redhat.com/cnv-qe-devops/devops-knowledge-base/-/blob/main/docs/infrastructure/cluster-connection-guide.md))
- `~/.ssh/config` with `Host ipi-exec` (script prints the snippet if missing)

## SSH troubleshooting

| Error | Fix |
|-------|-----|
| `Permission denied (publickey)` | Run `ssh-copy-id -i ~/.ssh/cnv-qe-jenkins.key cloud-user@ocp-ipi-executor.rhos-psi.cnv-qe.rhood.us` |
| `Connection timed out` | Check VPN connection; if VPN is up, the cluster may have been deprovisioned |
| `Host key verification failed` | Remove stale entry from `~/.ssh/known_hosts` for the executor host |

For other SSH errors, run `ssh -vvv ipi-exec` to get debug output and report it to the user.

## Reference

[docs/CLUSTER-DEPLOYMENT.md](https://gitlab.cee.redhat.com/contra/cnv-qe-automation/-/blob/main/docs/CLUSTER-DEPLOYMENT.md) in contra/cnv-qe-automation.
