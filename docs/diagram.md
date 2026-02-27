# Topology Diagram

A simple Mermaid diagram showing the hub-and-spoke layout and DNS flows.

```mermaid
graph LR
  OnPrem["On-Prem VNet\n(vm-onprem-dns)"]
  Hub["Hub VNet\n(vm-hub-dns, Resolver)"]
  Spoke1["Spoke1 VNet\n(vm-spoke1, private endpoint)"]
  Spoke2["Spoke2 VNet\n(vm-spoke2, private endpoint)"]

  OnPrem --- Hub
  Hub --- Spoke1
  Hub --- Spoke2

  OnPrem -->|forwards privatelink queries| Hub
  Hub -->|legacy BIND9 authoritative for azure.pvt| Hub
  Spoke1 -->|resolves via hub DNS (phase 1)| Hub
  Spoke2 -->|resolves via hub DNS (phase 1)| Hub
  Spoke1 -->|auto-register private endpoint| Hub
  Spoke2 -->|auto-register private endpoint| Hub

  Hub -->|resolver inbound (phase 5)| Resolver["Azure Private Resolver"]
  Resolver -->|private DNS zone| PrivateZone["privatelink.blob.core.windows.net (Private DNS)"]

```
