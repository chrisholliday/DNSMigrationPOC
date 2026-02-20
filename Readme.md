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

Peering is configured between On-Prem <-> Hub, and Hub <-> each Spoke.

## Deployment Phases

### Phase 1.1 - On-Prem initial build (onprem)

Deploy only the on-prem resource group.

- VNet is configured to use Azure DNS.
- Azure Bastion is available for access to VMs for manual testing.
- NAT Gateway provides internet access for OS and package updates.
- VMs are built but not configured for any role or capability.
- *Testing* at the completion of the build, a test script should verify the ability of the two VMs to:
  - Resolve common internet names.
  - Check for updates without errors.
- Manual testing with Azure Bastion will confirm the test script.

### Phase 1.2 - Deploy DNS services (onprem)

- Deploy Phase 1 and add the following:
  - DNS VM is configured to host the onprem DNS zone.
  - DNS VM is configured to forward all other requests to Azure DNS.
  - DNS VM and client VM have records in the onprem DNS zone.
  - VNet is configured to point DNS services to the DNS VM.
- *Testing* at the completion of the build, a test script should verify the ability of the two VMs to:
  - Resolve common internet names.
  - Verify that resolution is provided by the DNS VM.
  - Check for updates without errors.
- Manual testing with Azure Bastion will confirm the test script.

### Phase 1.3 - Hub configuration build (hub)

Deploy Phases 1-2 and add the following:

- Hub VNet is configured to use the onprem DNS server.
- Azure Bastion is available for access to VMs for manual testing.
- NAT Gateway provides internet access for OS and package updates.
- Hub VMs are built but not configured for any role or capability.
- *Testing* at the completion of the build, a test script should verify the ability of the two VMs to:
  - Resolve common internet names.
  - Check for updates without errors.
- Manual testing with Azure Bastion will confirm the test script.

### Phase 1.4 - Hub deploy DNS services

Deploy Phases 1-3 and add the following:

- Hub DNS VM is configured to host the azure.pvt DNS zone.
- Hub DNS VM is configured to host the privatelink.blob.core.windows.net zone.
- Hub DNS VM is configured to forward all other requests to onprem DNS.
- Onprem DNS VM is configured to forward azure.pvt requests to the hub DNS VM.
- VNet is configured to point DNS services to the hub DNS VM.
- *Testing* at the completion of the build, a test script should verify the ability of all VMs to:
  - Resolve common internet names.
  - Verify that resolution is provided by the correct DNS VM.
  - Check for updates without errors.
- Manual testing with Azure Bastion will confirm the test script.

### Phase 1.5 - Add other networks

- Deploy all remaining virtual networks.
- All VNets use the **hub DNS VM** as their DNS server (except on-prem, which uses its own DNS VM).

### Phase 1.6 - Add Storage Accounts

- Deploy a storage account in each spoke network.

- Register the private endpoint in the hub DNS VM.
- Validate name resolution from hub and onprem client VMs.

### Phase 2.1 - Azure Private DNS + Resolver

- Create the Azure Private DNS zone for `privatelink.blob.core.windows.net` in the hub resource group.
- Create DNS Resolver inbound/outbound endpoints and a forwarding ruleset.

### Phase 2.2 - Update Legacy Forwarders

Switch legacy DNS servers to forward `privatelink.blob.core.windows.net` to the Private Resolver inbound endpoint.

### Phase 2.3 - Migrate Spoke1

Switch Spoke1 VNet to Azure-provided DNS (keeps Spoke2 on the hub DNS VM).

### Phase 2.4 - Migrate Spoke2

Link Spoke2 to the private DNS zone (if not already) and switch it to Azure-provided DNS.

## Validation

- A validation script should be available at each phase to confirm proper configuration.

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

Each name includes **location** and **role** where helpful (for example: `hub-vm-dns`, `spoke1-vm-app`). Otherwise
conforms to standard Microsoft naming guidance.
