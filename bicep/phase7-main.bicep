// Phase 7 Orchestrator - Spoke Networks and Storage
// Subscription-level deployment

targetScope = 'subscription'

@description('Azure region for resources')
param location string = 'centralus'

@description('SSH public key for VM authentication')
@secure()
param sshPublicKey string

@description('VM admin username')
param vmAdminUsername string = 'azureuser'

@description('Spoke1 resource group name')
param spoke1ResourceGroupName string = 'rg-spoke1-dnsmig'

@description('Spoke2 resource group name')
param spoke2ResourceGroupName string = 'rg-spoke2-dnsmig'

// ===============================
// RESOURCE GROUPS
// ===============================
resource spoke1ResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: spoke1ResourceGroupName
  location: location
}

resource spoke2ResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: spoke2ResourceGroupName
  location: location
}

// ===============================
// SPOKE1 INFRASTRUCTURE
// ===============================
module spoke1Infrastructure 'modules/spoke-infrastructure.bicep' = {
  scope: spoke1ResourceGroup
  name: 'spoke1-infrastructure-deployment'
  params: {
    location: location
    sshPublicKey: sshPublicKey
    vmAdminUsername: vmAdminUsername
    spokeName: 'spoke1'
    vnetAddressPrefix: '10.2.0.0/16'
    workloadSubnetPrefix: '10.2.10.0/24'
    vmIpAddress: '10.2.10.4'
    dnsServerIp: '10.1.10.4'
  }
}

// ===============================
// SPOKE2 INFRASTRUCTURE
// ===============================
module spoke2Infrastructure 'modules/spoke-infrastructure.bicep' = {
  scope: spoke2ResourceGroup
  name: 'spoke2-infrastructure-deployment'
  params: {
    location: location
    sshPublicKey: sshPublicKey
    vmAdminUsername: vmAdminUsername
    spokeName: 'spoke2'
    vnetAddressPrefix: '10.3.0.0/16'
    workloadSubnetPrefix: '10.3.10.0/24'
    vmIpAddress: '10.3.10.4'
    dnsServerIp: '10.1.10.4'
  }
}

// ===============================
// OUTPUTS
// ===============================
output spoke1ResourceGroupName string = spoke1ResourceGroup.name
output spoke1VnetName string = spoke1Infrastructure.outputs.vnetName
output spoke1VnetId string = spoke1Infrastructure.outputs.vnetId
output spoke1VmName string = spoke1Infrastructure.outputs.vmName
output spoke1StorageAccountName string = spoke1Infrastructure.outputs.storageAccountName
output spoke1PrivateEndpointNicId string = spoke1Infrastructure.outputs.privateEndpointNicId

output spoke2ResourceGroupName string = spoke2ResourceGroup.name
output spoke2VnetName string = spoke2Infrastructure.outputs.vnetName
output spoke2VnetId string = spoke2Infrastructure.outputs.vnetId
output spoke2VmName string = spoke2Infrastructure.outputs.vmName
output spoke2StorageAccountName string = spoke2Infrastructure.outputs.storageAccountName
output spoke2PrivateEndpointNicId string = spoke2Infrastructure.outputs.privateEndpointNicId
