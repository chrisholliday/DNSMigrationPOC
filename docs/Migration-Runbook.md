# Migration Runbook

This runbook follows the staged approach defined in the repo.

## Prerequisites

- Azure subscription
- PowerShell with Az module
- SSH public key

## Phase 1 — Legacy‑Only Build

1. Deploy the legacy environment:
   - [scripts/01-deploy-legacy.ps1](../scripts/01-deploy-legacy.ps1)
2. Configure the legacy DNS servers:
   - [scripts/02-configure-dns-servers.ps1](../scripts/02-configure-dns-servers.ps1)
3. Validate legacy DNS resolution:
   - [scripts/validate.ps1](../scripts/validate.ps1) with `-Phase Legacy`

## Phase 2 — Private DNS + Resolver

1. Deploy Private DNS + Resolver + private endpoints:
   - [scripts/03-deploy-private-dns.ps1](../scripts/03-deploy-private-dns.ps1)
2. Confirm records exist in the private DNS zone:
   - [scripts/validate.ps1](../scripts/validate.ps1) with `-Phase AfterPrivateDns`

## Phase 3 — Update Legacy Forwarders

1. Update Linux DNS forwarders to use the Resolver inbound endpoint:
   - [scripts/04-configure-legacy-forwarders.ps1](../scripts/04-configure-legacy-forwarders.ps1)
2. Validate end‑to‑end resolution from on‑prem and spokes:
   - [scripts/validate.ps1](../scripts/validate.ps1) with `-Phase AfterForwarders`

## Phase 4 — Migrate Spoke1

1. Switch Spoke1 VNet to Azure‑provided DNS:
   - [scripts/05-migrate-spoke1.ps1](../scripts/05-migrate-spoke1.ps1)
2. Validate:
   - [scripts/validate.ps1](../scripts/validate.ps1) with `-Phase AfterSpoke1`

## Phase 5 — Migrate Spoke2

1. Link Spoke2 to Private DNS and switch it to Azure‑provided DNS:
   - [scripts/06-migrate-spoke2.ps1](../scripts/06-migrate-spoke2.ps1)
2. Validate:
   - [scripts/validate.ps1](../scripts/validate.ps1) with `-Phase AfterSpoke2`

## Cleanup

- [scripts/teardown.ps1](../scripts/teardown.ps1)
