# VPSmanage Project Notes

VPSmanage is a script-first VPS operations toolbox.

## Initial Direction

- Project name: VPSmanage
- Repository type: independent GitHub project
- Runtime: Bash on Linux VPS hosts
- Scope: interactive VPS setup, diagnostics, and security actions

## Functional Scope

- SSH port configuration
- Speedtest installation and execution
- Docker installation with environment detection
- SSL certificate issuing through acme.sh
- Optional security hardening
- IP quality and public network checks

## Design Rules

- Every system-changing feature must be optional.
- Destructive or lockout-prone actions need confirmation.
- Config files should be backed up before modification.
- The script should prefer native package managers when practical.
- Third-party remote scripts should require explicit confirmation before execution.
