// VNet Peering Module
// Creates one-way peering from local VNet to remote VNet

metadata description = 'VNet peering module (resource group scope)'

@description('Name of the local VNet (in this resource group)')
param localVnetName string

@description('Name of the remote VNet (for display purposes)')
param remoteVnetName string

@description('Resource ID of the remote VNet')
param remoteVnetId string

@description('Name of the peering')
param peeringName string

@description('Allow virtual network access')
param allowVirtualNetworkAccess bool = true

@description('Allow forwarded traffic')
param allowForwardedTraffic bool = true

@description('Allow gateway transit')
param allowGatewayTransit bool = false

@description('Use remote gateways')
param useRemoteGateways bool = false

// Reference to local VNet
resource localVnet 'Microsoft.Network/virtualNetworks@2021-08-01' existing = {
  name: localVnetName
}

// Create peering
resource peering 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-08-01' = {
  parent: localVnet
  name: peeringName
  properties: {
    allowVirtualNetworkAccess: allowVirtualNetworkAccess
    allowForwardedTraffic: allowForwardedTraffic
    allowGatewayTransit: allowGatewayTransit
    useRemoteGateways: useRemoteGateways
    remoteVirtualNetwork: {
      id: remoteVnetId
    }
  }
}

output peeringName string = peering.name
output peeringState string = peering.properties.peeringState
