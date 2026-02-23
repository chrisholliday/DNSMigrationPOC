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

**Architecture Principle:** Infrastructure → Connectivity → Configuration

All VNets are deployed with Azure DNS initially to avoid cross-VNet dependencies. Custom DNS is configured and activated after network connectivity is established.

### Phase 1: Foundation Infrastructure

**Goal:** Deploy all base networking with working defaults (Azure DNS)

- Deploy On-Prem VNet (10.0.0.0/16)
  - 2 VMs: onprem-vm-dns, onprem-vm-client
  - Azure Bastion, NAT Gateway
- Deploy Hub VNet (10.1.0.0/16)
  - 2 VMs: hub-vm-dns, hub-vm-app
  - Azure Bastion, NAT Gateway
- **DNS:** All VNets use Azure DNS (168.63.129.16)
- **Testing:** VM provisioning, internet connectivity, package updates

### Phase 2: Network Connectivity

**Goal:** Establish VNet peering and validate cross-VNet communication

- Create bidirectional peering: On-Prem ↔ Hub
- Validate network connectivity between VNets
- **Testing:** Cross-VNet ping, routing validation

### Phase 3: On-Prem DNS Configuration

**Goal:** Configure DNS server while VNet still uses Azure DNS

- Install BIND9 on onprem-vm-dns
- Configure onprem.pvt DNS zone
- Add host records (DNS VM, client VM)
- Configure forwarding to Azure DNS for internet names
- **VNet DNS:** Still uses Azure DNS (servers ready but not active)
- **Testing:** Query DNS server directly, but VNet still uses Azure DNS

### Phase 4: On-Prem DNS Cutover

**Goal:** Switch On-Prem VNet to use custom DNS

- Update On-Prem VNet DNS setting to point to onprem-vm-dns (10.0.10.4)
- Validate DHCP renewal propagates to VMs
- **Testing:** VMs resolve via custom DNS, onprem.pvt zone working

### Phase 5: Hub DNS Configuration

**Goal:** Configure hub DNS server and establish DNS forwarding

- Install BIND9 on hub-vm-dns
- Configure azure.pvt DNS zone
- Configure privatelink.blob.core.windows.net zone (legacy)
- Configure forwarding to onprem-vm-dns for onprem.pvt
- Update onprem-vm-dns to forward azure.pvt to hub-vm-dns
- **VNet DNS:** Hub still uses Azure DNS (server ready but not active)
- **Testing:** Query hub DNS server directly, bidirectional forwarding works

### Phase 6: Hub DNS Cutover

**Goal:** Switch Hub VNet to use custom DNS, complete DNS architecture

- Update Hub VNet DNS setting to point to hub-vm-dns (10.1.10.4)
- Validate DHCP renewal propagates to VMs
- **Testing:** Full DNS resolution chain working (onprem.pvt, azure.pvt, internet)

### Phase 7: Spoke Networks & Storage

**Goal:** Deploy spoke networks with storage accounts and configure legacy DNS

- Deploy Spoke1 and Spoke2 VNets (10.2.0.0/16, 10.3.0.0/16)
- Configure VNet peering: Hub ↔ Spoke1, Hub ↔ Spoke2
- Point spoke VNets to hub DNS server (10.1.10.4)
- Deploy storage accounts with private endpoints on each spoke
- **Auto-generate** privatelink.blob.core.windows.net DNS records from private endpoint IPs
- Update hub-vm-dns BIND9 configuration with privatelink zone
- **Testing:** All environments resolve storage account names via hub DNS server

### Phase 8: Azure Private DNS + Resolver + Forwarding

**Goal:** Deploy Azure Private DNS infrastructure and configure DNS forwarding

- Create Azure Private DNS zone (privatelink.blob.core.windows.net)
- Deploy Private DNS Resolver (inbound + outbound endpoints)
- Link private endpoints to DNS zone (auto-registration enabled)
- Configure hub-vm-dns to forward privatelink queries → resolver inbound endpoint
- Configure onprem-vm-dns to forward privatelink queries → resolver inbound endpoint
- **Testing:** Resolution works via both paths (BIND9 legacy + Azure Private DNS)

### Phase 9: Spoke1 Migration

**Goal:** Migrate Spoke1 to Azure Private DNS

- Switch Spoke1 VNet DNS to Azure-provided DNS (168.63.129.16)
- Link Spoke1 VNet to Private DNS zone
- Remove Spoke1 storage records from hub-vm-dns BIND9 (legacy cleanup)
- **Testing:** Spoke1 resolves via Azure Private DNS, Spoke2 still via BIND9

### Phase 10: Spoke2 Migration

**Goal:** Complete migration by moving Spoke2 to Azure Private DNS

- Switch Spoke2 VNet DNS to Azure-provided DNS (168.63.129.16)
- Link Spoke2 VNet to Private DNS zone
- Remove privatelink zone from hub-vm-dns BIND9 (legacy cleanup complete)
- **Testing:** Both spokes resolve via Azure Private DNS, migration complete

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
