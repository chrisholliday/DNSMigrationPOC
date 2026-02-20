// Phase 1 - Infrastructure Deployment (Subscription-Level Orchestrator)
// Deploys: On-Prem and Hub resource groups and infrastructure
// Architecture: Uses modules for multi-resource-group deployment
// This phase establishes the foundation infrastructure for both environments

targetScope = 'subscription'

metadata description = 'Phase 1: Deploy both On-Prem and Hub VNets with Azure DNS (multi-RG)'

@description('Azure region for all resources')
param location string = 'centralus'

@description('SSH public key for VM authentication')
param sshPublicKey string

@description('VM admin username')
param vmAdminUsername string = 'azureuser'

@description('On-prem resource group name')
param onpremResourceGroupName string = 'rg-onprem-dnsmig'

@description('Hub resource group name')
param hubResourceGroupName string = 'rg-hub-dnsmig'

// ===============================
// RESOURCE GROUPS
// ===============================
resource onpremResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: onpremResourceGroupName
  location: location
}

resource hubResourceGroup 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: hubResourceGroupName
  location: location
}

// ===============================
// MODULE DEPLOYMENTS
// ===============================

// Deploy on-prem infrastructure to on-prem resource group
module onpremInfrastructure 'modules/onprem-infrastructure.bicep' = {
  scope: onpremResourceGroup
  name: 'onpremInfrastructureDeploy'
  params: {
    location: location
    sshPublicKey: sshPublicKey
    vmAdminUsername: vmAdminUsername
  }
}

// Deploy hub infrastructure to hub resource group
module hubInfrastructure 'modules/hub-infrastructure.bicep' = {
  scope: hubResourceGroup
  name: 'hubInfrastructureDeploy'
  params: {
    location: location
    sshPublicKey: sshPublicKey
    vmAdminUsername: vmAdminUsername
  }
}

// ===============================
// OUTPUTS
// ===============================

// On-Prem Outputs
output onpremResourceGroupName string = onpremResourceGroup.name
output onpremVnetId string = onpremInfrastructure.outputs.vnetId
output onpremVnetName string = onpremInfrastructure.outputs.vnetName
output onpremDnsVmPrivateIp string = onpremInfrastructure.outputs.dnsVmPrivateIp
output onpremClientVmPrivateIp string = onpremInfrastructure.outputs.clientVmPrivateIp
output onpremDnsVmId string = onpremInfrastructure.outputs.dnsVmId
output onpremClientVmId string = onpremInfrastructure.outputs.clientVmId
output onpremBastionName string = onpremInfrastructure.outputs.bastionName
output onpremNatGatewayPublicIp string = onpremInfrastructure.outputs.natGatewayPublicIp

// Hub Outputs
output hubResourceGroupName string = hubResourceGroup.name
output hubVnetId string = hubInfrastructure.outputs.vnetId
output hubVnetName string = hubInfrastructure.outputs.vnetName
output hubDnsVmPrivateIp string = hubInfrastructure.outputs.dnsVmPrivateIp
output hubAppVmPrivateIp string = hubInfrastructure.outputs.appVmPrivateIp
output hubDnsVmId string = hubInfrastructure.outputs.dnsVmId
output hubAppVmId string = hubInfrastructure.outputs.appVmId
output hubBastionName string = hubInfrastructure.outputs.bastionName
output hubNatGatewayPublicIp string = hubInfrastructure.outputs.natGatewayPublicIp
