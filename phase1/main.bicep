// phase1/main.bicep
// Phase 1 — Foundation Infrastructure
//
// Deploys four resource groups and their core resources:
//   • rg-dnsmig-onprem  — on-prem VNet + DNS VM + Bastion + NAT GW
//   • rg-dnsmig-hub     — hub VNet + DNS VM + Bastion + NAT GW
//   • rg-dnsmig-spoke1  — spoke1 VNet + workload VM + Storage + Private Endpoint
//   • rg-dnsmig-spoke2  — spoke2 VNet + workload VM + Storage + Private Endpoint
//
// All VNets use Azure DNS (168.63.129.16) at this stage.
// Custom DNS servers are switched in Phase 4.

targetScope = 'subscription'

@description('Azure region for all resources')
param location string = 'centralus'

@description('Admin username for all VMs')
param adminUsername string = 'azureuser'

@description('SSH public key data (the full key string, e.g. "ssh-rsa AAAA...")')
param sshPublicKey string

@description('VM size for all virtual machines')
param vmSize string = 'Standard_B2s'

// ── Unique suffix for globally-unique storage account names ──────────────────
// uniqueString is deterministic per subscription, keeping names stable across re-deployments.
var uniqueSuffix = uniqueString(subscription().subscriptionId)
var spoke1StorageName = take('saspoke1${uniqueSuffix}', 24)
var spoke2StorageName = take('saspoke2${uniqueSuffix}', 24)

// ── Resource Groups ───────────────────────────────────────────────────────────

resource rgOnprem 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-dnsmig-onprem'
  location: location
}

resource rgHub 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-dnsmig-hub'
  location: location
}

resource rgSpoke1 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-dnsmig-spoke1'
  location: location
}

resource rgSpoke2 'Microsoft.Resources/resourceGroups@2023-07-01' = {
  name: 'rg-dnsmig-spoke2'
  location: location
}

// ── On-Prem VNet ──────────────────────────────────────────────────────────────

module onprem 'modules/dns-vnet.bicep' = {
  scope: rgOnprem
  name: 'deploy-onprem'
  params: {
    vnetName: 'vnet-onprem'
    vnetAddressPrefix: '10.0.0.0/16'
    vmSubnetPrefix: '10.0.1.0/24'
    bastionSubnetPrefix: '10.0.255.0/27'
    vmName: 'vm-onprem-dns'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    location: location
  }
}

// ── Hub VNet ──────────────────────────────────────────────────────────────────

module hub 'modules/dns-vnet.bicep' = {
  scope: rgHub
  name: 'deploy-hub'
  params: {
    vnetName: 'vnet-hub'
    vnetAddressPrefix: '10.1.0.0/16'
    vmSubnetPrefix: '10.1.1.0/24'
    bastionSubnetPrefix: '10.1.255.0/27'
    vmName: 'vm-hub-dns'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    location: location
  }
}

// ── Spoke1 VNet ───────────────────────────────────────────────────────────────

module spoke1 'modules/spoke.bicep' = {
  scope: rgSpoke1
  name: 'deploy-spoke1'
  params: {
    vnetName: 'vnet-spoke1'
    vnetAddressPrefix: '10.2.0.0/16'
    appSubnetPrefix: '10.2.1.0/24'
    bastionSubnetPrefix: '10.2.255.0/27'
    vmName: 'vm-spoke1'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    storageAccountName: spoke1StorageName
    location: location
  }
}

// ── Spoke2 VNet ───────────────────────────────────────────────────────────────

module spoke2 'modules/spoke.bicep' = {
  scope: rgSpoke2
  name: 'deploy-spoke2'
  params: {
    vnetName: 'vnet-spoke2'
    vnetAddressPrefix: '10.3.0.0/16'
    appSubnetPrefix: '10.3.1.0/24'
    bastionSubnetPrefix: '10.3.255.0/27'
    vmName: 'vm-spoke2'
    vmSize: vmSize
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    storageAccountName: spoke2StorageName
    location: location
  }
}

// ── Outputs ───────────────────────────────────────────────────────────────────
// These outputs are consumed by Phase 3 (DNS configuration) and Phase 4 (DNS cutover).

output onpremVmName string = onprem.outputs.vmName
output onpremVmPrivateIp string = onprem.outputs.vmPrivateIp

output hubVmName string = hub.outputs.vmName
output hubVmPrivateIp string = hub.outputs.vmPrivateIp

output spoke1VmName string = spoke1.outputs.vmName
output spoke1VmPrivateIp string = spoke1.outputs.vmPrivateIp
output spoke1StorageAccountName string = spoke1.outputs.storageAccountName
output spoke1PrivateEndpointName string = spoke1.outputs.privateEndpointName

output spoke2VmName string = spoke2.outputs.vmName
output spoke2VmPrivateIp string = spoke2.outputs.vmPrivateIp
output spoke2StorageAccountName string = spoke2.outputs.storageAccountName
output spoke2PrivateEndpointName string = spoke2.outputs.privateEndpointName
