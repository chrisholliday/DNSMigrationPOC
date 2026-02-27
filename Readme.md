# README - Azure DNS Migration Sandbox

## Overview

This repo provides a simple, staged DNS migration sandbox that moves **only** the `privatelink.blob.core.windows.net` zone from **Linux-hosted DNS** to **Azure Private DNS**, while keeping `onprem.pvt` and `azure.pvt` hosted on Linux throughout the POC.

The design intentionally mirrors a production-like hub-and-spoke topology but with minimal resources, simple naming, and a clear migration path.

## Goals

1. Prove **private endpoint records are created automatically** in the Azure Private DNS zone via DNS Zone Groups.
2. Demonstrate **incremental migration**: one spoke switches to Azure Private DNS first, then the second later, with **no downtime**.
3. Validate resolution **before**, **during**, and **after** the cutover.

## Zones in Scope

- `onprem.pvt` - hosted on the on-prem Linux DNS server (no migration).
- `azure.pvt` — hosted on the hub Linux DNS server (no migration).
- `privatelink.blob.core.windows.net` — hosted on the hub Linux DNS server **initially**, then migrated to **Azure Private DNS**.

## Technology Stack

- All VMs use Ubuntu (Linux) for cost and deployment speed considerations.
- Deployment code uses PowerShell (cross-platform) and Bicep for Azure deployments.

## Architecture (Minimal Networks)

- **On-Prem VNet**
  - Linux DNS VM (authoritative for `onprem.pvt`)
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

Peering is configured between On-Prem ↔ Hub, and Hub ↔ each Spoke.

## Deployment Phases

**Architecture Principle:** Infrastructure → Connectivity → Configuration

All VNets are deployed with Azure DNS initially to avoid cross-VNet dependencies. Custom DNS is configured and activated after network connectivity is established.

## Documentation

- Architecture overview: [docs/Architecture.md](docs/Architecture.md)
- Deployment guide: [ProjectDeploymentGuide.md](ProjectDeploymentGuide.md)
- Migration runbook: (not included in this repo yet)
- Security considerations beyond the POC: (not included in this repo yet)

## Audience

This proof-of-concept is intended for the Azure platform engineering team and reviewers evaluating the migration approach and trade-offs.

## Default Region

`centralus` is the default, but every script includes a `-Location` parameter.

## Naming Convention

Examples follow Microsoft guidance: lower-case, hyphen-separated, and role-qualified where helpful.

- `rg-dnsmig-onprem`
- `rg-dnsmig-hub`
- `rg-dnsmig-spoke1`
- `rg-dnsmig-spoke2`

Example resource names: `hub-vm-dns`, `spoke1-vm-app`, `spoke2-sa-{unique}`.
