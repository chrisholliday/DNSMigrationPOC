# Security Considerations (Beyond the POC)

This POC prioritizes simplicity. In production, consider:

## Network Security

- Restrict SSH with Just‑In‑Time access or Bastion only.
- Enforce NSGs with least‑privilege rules.
- Add Azure Firewall or NVA for egress control.
- Use separate subnets for admin and workload traffic.

## Identity and Access

- Use managed identities for automation.
- Limit who can modify Private DNS zones and Resolver rulesets.
- Enforce RBAC on resource groups and private endpoints.

## Resiliency

- Use zone‑redundant or multi‑instance DNS resolvers where appropriate.
- Deploy multiple DNS servers or managed services to avoid single points of failure.
- Add health checks and monitoring for DNS latency and failures.

## Monitoring and Logging

- Enable Azure Monitor + Log Analytics for DNS Resolver metrics.
- Capture DNS query logs from Linux DNS servers.
- Alert on NXDOMAIN spikes or unusual query patterns.

## Governance

- Enforce DNS Zone Group creation with Azure Policy.
- Standardize naming and tagging.
- Restrict manual DNS record creation in Private DNS zones.
