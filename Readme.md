# README — Azure DNS Migration Sandbox

## Overview

This repo provides a simple, staged DNS migration sandbox that moves **only** the `privatelink.blob.core.windows.net` zone from **Linux‑hosted DNS** to **Azure Private DNS**, while keeping `onprem.pvt` and `azure.pvt` hosted on Linux throughout the POC.

The design intentionally mirrors a production‑like hub‑and‑spoke topology but with minimal resources, simple naming, and a clear migration path.

## Goals

1. Prove **private endpoint records are created automatically** in the Azure Private DNS zone via DNS Zone Groups.
2. Demonstrate **incremental migration**: one spoke switches to Azure Private DNS first, then the second later, with **no downtime**.
3. Validate resolution **before**, **during**, and **after** the cutover.

## Zones in Scope

- `onprem.pvt` — hosted on the on‑prem Linux DNS server (no migration).
- `azure.pvt` — hosted on the hub Linux DNS server (no migration).
- `privatelink.blob.core.windows.net` — hosted on the hub Linux DNS server **initially**, then migrated to **Azure Private DNS**.

## Architecture (Minimal Networks)

- **On‑Prem VNet**
  - Linux DNS VM (authoritative for `onprem.pvt`)
  - Linux client VM
  - Forwards `azure.pvt` and `privatelink.blob.core.windows.net` to the hub DNS server

- **Hub VNet**
  - Linux DNS VM (authoritative for `azure.pvt` and legacy `privatelink.blob.core.windows.net`)
  - Azure Private DNS Resolver (inbound + outbound)
  - Azure Private DNS zone for `privatelink.blob.core.windows.net`

- **Spoke1 VNet**
  - VM for testing resolution
  - Storage account + private endpoint

- **Spoke2 VNet**
  - VM for testing resolution
  - Storage account + private endpoint

Peering is configured between On‑Prem ↔ Hub, and Hub ↔ each Spoke.

## Deployment Phases

### Phase 1 — Legacy‑Only Build

Deploy the full topology with **Linux DNS only**.

- All VNets use the **hub DNS VM** as their DNS server (except on‑prem, which uses its own DNS VM).
- `privatelink.blob.core.windows.net` is still hosted on the hub DNS VM.

Script: [scripts/01-deploy-legacy.ps1](scripts/01-deploy-legacy.ps1)

### Phase 1b — Configure DNS Servers

Install and configure dnsmasq on the DNS VMs to serve the zones.

Script: [scripts/02-configure-dns-servers.ps1](scripts/02-configure-dns-servers.ps1)

### Phase 2 — Azure Private DNS + Resolver

- Create the Azure Private DNS zone for `privatelink.blob.core.windows.net`.
- Create DNS Resolver inbound/outbound endpoints and a forwarding ruleset.
- Deploy storage accounts + private endpoints with DNS Zone Groups (auto‑creates records).

Script: [scripts/03-deploy-private-dns.ps1](scripts/03-deploy-private-dns.ps1)

### Phase 3 — Update Legacy Forwarders

Switch legacy DNS servers to forward `privatelink.blob.core.windows.net` to the Private Resolver inbound endpoint.

Script: [scripts/04-configure-legacy-forwarders.ps1](scripts/04-configure-legacy-forwarders.ps1)

### Phase 4 — Migrate Spoke1

Switch Spoke1 VNet to Azure‑provided DNS (keeps Spoke2 on the hub DNS VM).

Script: [scripts/05-migrate-spoke1.ps1](scripts/05-migrate-spoke1.ps1)

### Phase 5 — Migrate Spoke2

Link Spoke2 to the private DNS zone (if not already) and switch it to Azure‑provided DNS.

Script: [scripts/06-migrate-spoke2.ps1](scripts/06-migrate-spoke2.ps1)

## Validation

- Run the validation helper at each phase to confirm DNS behavior.

Guide: [docs/Validation-Guide.md](docs/Validation-Guide.md)
Script: [scripts/validate.ps1](scripts/validate.ps1)

## Documentation

- Architecture overview: [docs/Architecture.md](docs/Architecture.md)
- Deployment guide: [docs/Deployment-Guide.md](docs/Deployment-Guide.md)
- Migration runbook: [docs/Migration-Runbook.md](docs/Migration-Runbook.md)
- Security considerations beyond the POC: [docs/Security-Considerations.md](docs/Security-Considerations.md)

## Default Region

`centralus` is the default, but every script includes a `-Location` parameter.

## Naming Convention

Simple, readable naming is used throughout:

- `onprem-*`
- `hub-*`
- `spoke1-*`
- `spoke2-*`

Each name includes **location** and **role** where helpful (for example: `hub-vm-dns`, `spoke1-vm-app`).

## Next Steps

Start with the legacy build script and follow the runbook end‑to‑end:

- [docs/Migration-Runbook.md](docs/Migration-Runbook.md)
