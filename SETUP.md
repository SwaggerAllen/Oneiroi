# Setup

The attended runbook for standing an instance up, filled in through P0.5
(design/p0-plan.md). The block below is read by `mix oneiroi.audit`: every
variable this codebase requires with no default and no external name is
listed here, one per line, or the audit says so, and a line no
declaration explains is reported too.

```oneiroi:required-env
PLATFORM_SECRET_KEY_BASE   # the endpoint's cookie-signing secret, 64 bytes or more
```
