targetScope = 'subscription'

type RgNames = {
  onprem: string
  hub: string
  spoke1: string
  spoke2: string
}

type AddressSpaces = {
  onprem: string
  hub: string
  spoke1: string
  spoke2: string
}

type SubnetPrefixes = {
  onpremVm: string
  hubVm: string
  hubInbound: string
  hubOutbound: string
  spoke1Vm: string
  spoke1Pe: string
  spoke2Vm: string
  spoke2Pe: string
}

type DnsIps = {
  onpremDns: string
  onpremClient: string
  hubDns: string
  spoke1Vm: string
  spoke2Vm: string
}

param location string = 'centralus'
param prefix string = 'dnsmig'
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string
param vmSize string = 'Standard_B1s'

param rgNames RgNames = {
  onprem: '${prefix}-rg-onprem'
  hub: '${prefix}-rg-hub'
  spoke1: '${prefix}-rg-spoke1'
  spoke2: '${prefix}-rg-spoke2'
}

param addressSpaces AddressSpaces = {
  onprem: '10.10.0.0/16'
  hub: '10.20.0.0/16'
  spoke1: '10.30.0.0/16'
  spoke2: '10.40.0.0/16'
}

param subnetPrefixes SubnetPrefixes = {
  onpremVm: '10.10.1.0/24'
  hubVm: '10.20.1.0/24'
  hubInbound: '10.20.2.0/24'
  hubOutbound: '10.20.3.0/24'
  spoke1Vm: '10.30.1.0/24'
  spoke1Pe: '10.30.2.0/24'
  spoke2Vm: '10.40.1.0/24'
  spoke2Pe: '10.40.2.0/24'
}

param dnsIps DnsIps = {
  onpremDns: '10.10.1.4'
  onpremClient: '10.10.1.5'
  hubDns: '10.20.1.4'
  spoke1Vm: '10.30.1.4'
  spoke2Vm: '10.40.1.4'
}

var names = {
  onpremVnet: '${prefix}-onprem-vnet'
  hubVnet: '${prefix}-hub-vnet'
  spoke1Vnet: '${prefix}-spoke1-vnet'
  spoke2Vnet: '${prefix}-spoke2-vnet'
}

resource rgOnprem 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgNames.onprem
  location: location
}

resource rgHub 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgNames.hub
  location: location
}

resource rgSpoke1 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgNames.spoke1
  location: location
}

resource rgSpoke2 'Microsoft.Resources/resourceGroups@2021-04-01' = {
  name: rgNames.spoke2
  location: location
}

module onprem './modules/legacy-onprem.bicep' = {
  scope: rgOnprem
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    addressSpace: addressSpaces.onprem
    subnetPrefix: subnetPrefixes.onpremVm
    dnsIps: {
      dns: dnsIps.onpremDns
      client: dnsIps.onpremClient
      hubDns: dnsIps.hubDns
    }
    vnetName: names.onpremVnet
  }
}

module hub './modules/legacy-hub.bicep' = {
  scope: rgHub
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    addressSpace: addressSpaces.hub
    subnetVmPrefix: subnetPrefixes.hubVm
    subnetInboundPrefix: subnetPrefixes.hubInbound
    subnetOutboundPrefix: subnetPrefixes.hubOutbound
    dnsIps: {
      dns: dnsIps.hubDns
      onpremDns: dnsIps.onpremDns
      spoke1Vm: dnsIps.spoke1Vm
      spoke2Vm: dnsIps.spoke2Vm
    }
    vnetName: names.hubVnet
  }
}

module spoke1 './modules/legacy-spoke.bicep' = {
  scope: rgSpoke1
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    addressSpace: addressSpaces.spoke1
    subnetVmPrefix: subnetPrefixes.spoke1Vm
    subnetPePrefix: subnetPrefixes.spoke1Pe
    dnsServerIp: dnsIps.hubDns
    vmIp: dnsIps.spoke1Vm
    vnetName: names.spoke1Vnet
    vmNameSuffix: 'spoke1-vm-app'
  }
}

module spoke2 './modules/legacy-spoke.bicep' = {
  scope: rgSpoke2
  params: {
    location: location
    prefix: prefix
    adminUsername: adminUsername
    sshPublicKey: sshPublicKey
    vmSize: vmSize
    addressSpace: addressSpaces.spoke2
    subnetVmPrefix: subnetPrefixes.spoke2Vm
    subnetPePrefix: subnetPrefixes.spoke2Pe
    dnsServerIp: dnsIps.hubDns
    vmIp: dnsIps.spoke2Vm
    vnetName: names.spoke2Vnet
    vmNameSuffix: 'spoke2-vm-app'
  }
}

module peerOnpremToHub './modules/legacy-peering.bicep' = {
  scope: rgOnprem
  params: {
    localVnetName: names.onpremVnet
    peeringName: 'peer-onprem-to-hub'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.hub,
      'Microsoft.Network/virtualNetworks',
      names.hubVnet
    )
  }
}

module peerHubToOnprem './modules/legacy-peering.bicep' = {
  scope: rgHub
  params: {
    localVnetName: names.hubVnet
    peeringName: 'peer-hub-to-onprem'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.onprem,
      'Microsoft.Network/virtualNetworks',
      names.onpremVnet
    )
  }
}

module peerHubToSpoke1 './modules/legacy-peering.bicep' = {
  scope: rgHub
  params: {
    localVnetName: names.hubVnet
    peeringName: 'peer-hub-to-spoke1'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.spoke1,
      'Microsoft.Network/virtualNetworks',
      names.spoke1Vnet
    )
  }
}

module peerSpoke1ToHub './modules/legacy-peering.bicep' = {
  scope: rgSpoke1
  params: {
    localVnetName: names.spoke1Vnet
    peeringName: 'peer-spoke1-to-hub'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.hub,
      'Microsoft.Network/virtualNetworks',
      names.hubVnet
    )
  }
}

module peerHubToSpoke2 './modules/legacy-peering.bicep' = {
  scope: rgHub
  params: {
    localVnetName: names.hubVnet
    peeringName: 'peer-hub-to-spoke2'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.spoke2,
      'Microsoft.Network/virtualNetworks',
      names.spoke2Vnet
    )
  }
}

module peerSpoke2ToHub './modules/legacy-peering.bicep' = {
  scope: rgSpoke2
  params: {
    localVnetName: names.spoke2Vnet
    peeringName: 'peer-spoke2-to-hub'
    remoteVnetId: resourceId(
      subscription().subscriptionId,
      rgNames.hub,
      'Microsoft.Network/virtualNetworks',
      names.hubVnet
    )
  }
}

output hubDnsIp string = dnsIps.hubDns
output onpremDnsIp string = dnsIps.onpremDns
output spoke1VmIp string = dnsIps.spoke1Vm
output spoke2VmIp string = dnsIps.spoke2Vm
