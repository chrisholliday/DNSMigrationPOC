# Project Deployment Guide

## Goals

The goal of this project is to reproduce a very simplified enviorment using cloud hosted dns servers for dns resolution, and to demonstrate the required actions to migrate the dns resolution to Azure private DNS while still allowing on prem devices to resolve cloud dns zones, and to ensure that on prem namespaces are still resolved from the cloud.

This is not intended to server as a foundtion for working or production code, and the key objective of the deployment is to get a working enviornment stood up as quickly and easily as possible so that the actual migration efforts can be demonstrated.

To that end the deployment of resources should follow a set of phased approches.

### Phase 1: Foundation Infrastructure

**Goal:** Deploy all base networking with working defaults (Azure DNS)

- Deploy On-Prem VNet (10.0.0.0/16)
  - Resource Group: rg-dnsmig-onprem
  - VMs: vm-onprem-dns
  - Azure Bastion, NAT Gateway
- Deploy Hub VNet (10.1.0.0/16)
  - Resource Group: rg-dnsmig-hub
  - VM: vm-hub-dns
  - Azure Bastion, NAT Gateway
- Deploy spoke1 VNet (10.2.0.0/16)
  - Resource Group: rg-dnsmig-spoke1
  - VMs: vm-spoke1
  - Storage Account: globally unique generated name
  - Azure Bastion, NAT Gateway
- Deploy Hub VNet (10.3.0.0/16)
  - Resource Group: rg-dnsmig-spoke2
  - VM: vm-spoke1
  - Azure Bastion, NAT Gateway
  - Storage Account: globally unique generated name

- **DNS:** All VNets use Azure DNS (168.63.129.16)
- **Testing:** VM provisioning, internet connectivity, package updates

### Phase 2: Network Connectivity

**Goal:** Establish VNet peering and validate cross-VNet communication

- Create bidirectional peering: On-Prem ↔ Hub, Hub ↔ Spoke1, Hub ↔ Spoke2
- Validate network connectivity between VNets
- **Testing:** Cross-VNet ping, routing validation

### Phase 3: DNS Configuration

**Goal:** Configure DNS servers while VNets still uses Azure DNS

- Install BIND9 (or equivilant) on DNS servers
- Configure onprem.pvt DNS zone (create record for onprem vm)
- Configure azure.pvt DNS Zone (create record for hub vm)
- Configure privatelink.blob.core.windows.net zone (legacy) (create records for storage accounts)
- Configure forwarding to Azure DNS for internet names
- **VNet DNS:** Still uses Azure DNS (servers ready but not active)
- **Testing:** Query DNS servers directly, but VNets still uses Azure DNS

### Phase 4: Hosted DNS Cutover

**Goal:** Switch to use custom DNS servers

- Update On-Prem VNet DNS setting to point dns to onprem-vm-dns
- Update all other vnets to point dns to vm-hub-dns
- Validate DHCP renewal propagates to VMs
- Configure forwarding to vm-hub-dns for azure.pvt from vm-onprem-dns
- Configure forwarding to vm-hub-dns for privatelink.blob.core.windows.net from vm-onprem-dns
- Configure forwarding to vm-onprem-dns for all other zone from vm-hub-dns
- Configure forwarding to azure dns for all other zone from vm-hub-dns

- **Testing:** All VMs resolve records in hosted zones, and common internet dns names

### Phase 5: Azure Private DNS + Resolver + Forwarding

**Goal:** Deploy Azure Private DNS infrastructure and configure DNS forwarding

- Create Azure Private DNS zone (privatelink.blob.core.windows.net)
- Deploy Private DNS Resolver (inbound + outbound endpoints)
- Link private endpoints to DNS zone (auto-registration enabled)
- Configure hub-vm-dns to forward privatelink queries → resolver inbound endpoint
- Configure onprem-vm-dns to forward privatelink queries → resolver inbound endpoint
- **Testing:** Resolution works via both paths (BIND9 legacy + Azure Private DNS)

### Phase 6: Spoke1 Migration

**Goal:** Migrate Spoke1 to Azure Private DNS

- Switch Spoke1 VNet DNS to Azure-provided DNS (168.63.129.16)
- Link Spoke1 VNet to Private DNS zone
- Remove Spoke1 storage records from hub-vm-dns BIND9 (legacy cleanup)
- **Testing:** Spoke1 resolves via Azure Private DNS, Spoke2 still via BIND9

### Phase 7: Spoke2 Migration

**Goal:** Complete migration by moving Spoke2 to Azure Private DNS

- Switch Spoke2 VNet DNS to Azure-provided DNS (168.63.129.16)
- Link Spoke2 VNet to Private DNS zone
- Remove privatelink zone from hub-vm-dns BIND9 (legacy cleanup complete)
- **Testing:** Both spokes resolve via Azure Private DNS, migration complete

## Validation

- A validation script should be available at each phase to confirm proper configuration.
