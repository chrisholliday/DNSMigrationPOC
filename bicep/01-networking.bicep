targetScope = 'resourceGroup'

param location string = 'centralus'

// All names and IPs hardcoded - this is a POC, never changes
var onpremVnetName = 'dnsmig-onprem-vnet'
var hubVnetName = 'dnsmig-hub-vnet'
var spoke1VnetName = 'dnsmig-spoke1-vnet'
var spoke2VnetName = 'dnsmig-spoke2-vnet'

var onpremAddressSpace = '10.10.0.0/16'
var hubAddressSpace = '10.20.0.0/16'
var spoke1AddressSpace = '10.30.0.0/16'
var spoke2AddressSpace = '10.40.0.0/16'

var onpremSubnetPrefix = '10.10.1.0/24'
var hubSubnetVmPrefix = '10.20.1.0/24'
var hubSubnetInboundPrefix = '10.20.2.0/24'
var hubSubnetOutboundPrefix = '10.20.3.0/24'
var spoke1SubnetVmPrefix = '10.30.1.0/24'
var spoke1SubnetPePrefix = '10.30.2.0/24'
var spoke2SubnetVmPrefix = '10.40.1.0/24'
var spoke2SubnetPePrefix = '10.40.2.0/24'

// NSGs
resource onpremNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'dnsmig-onprem-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-DNS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource hubNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'dnsmig-hub-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-DNS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

resource spokeNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'dnsmig-spoke-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH-VNet'
        properties: {
          priority: 100
          direction: 'Inbound'
          access: 'Allow'
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
      {
        name: 'Allow-DNS'
        properties: {
          priority: 110
          direction: 'Inbound'
          access: 'Allow'
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
        }
      }
    ]
  }
}

// VNets
resource onpremVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: onpremVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        onpremAddressSpace
      ]
    }
    subnets: [
      {
        name: 'dnsmig-onprem-subnet'
        properties: {
          addressPrefix: onpremSubnetPrefix
          networkSecurityGroup: {
            id: onpremNsg.id
          }
        }
      }
    ]
  }
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: hubVnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        hubAddressSpace
      ]
    }
    subnets: [
      {
        name: 'dnsmig-hub-vm-subnet'
        properties: {
          addressPrefix: hubSubnetVmPrefix
          networkSecurityGroup: {
            id: hubNsg.id
          }
        }
      }
      {
        name: 'dnsmig-hub-inbound-subnet'
        properties: {
          addressPrefix: hubSubnetInboundPrefix
          networkSecurityGroup: {
            id: hubNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
      {
        name: 'dnsmig-hub-outbound-subnet'
        properties: {
          addressPrefix: hubSubnetOutboundPrefix
          networkSecurityGroup: {
            id: hubNsg.id
          }
          delegations: [
            {
              name: 'Microsoft.Network.dnsResolvers'
              properties: {
                serviceName: 'Microsoft.Network/dnsResolvers'
              }
            }
          ]
        }
      }
    ]
  }
}

resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: spoke1VnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke1AddressSpace
      ]
    }
    subnets: [
      {
        name: 'dnsmig-spoke1-vm-subnet'
        properties: {
          addressPrefix: spoke1SubnetVmPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
        }
      }
      {
        name: 'dnsmig-spoke1-pe-subnet'
        properties: {
          addressPrefix: spoke1SubnetPePrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
        }
      }
    ]
  }
}

resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: spoke2VnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        spoke2AddressSpace
      ]
    }
    subnets: [
      {
        name: 'dnsmig-spoke2-vm-subnet'
        properties: {
          addressPrefix: spoke2SubnetVmPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
        }
      }
      {
        name: 'dnsmig-spoke2-pe-subnet'
        properties: {
          addressPrefix: spoke2SubnetPePrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
        }
      }
    ]
  }
}

// Outputs for next phases
output onpremVnetId string = onpremVnet.id
output hubVnetId string = hubVnet.id
output spoke1VnetId string = spoke1Vnet.id
output spoke2VnetId string = spoke2Vnet.id

output onpremVnetName string = onpremVnetName
output hubVnetName string = hubVnetName
output spoke1VnetName string = spoke1VnetName
output spoke2VnetName string = spoke2VnetName

output hubVmSubnetId string = '${hubVnet.id}/subnets/dnsmig-hub-vm-subnet'
output hubInboundSubnetId string = '${hubVnet.id}/subnets/dnsmig-hub-inbound-subnet'
output hubOutboundSubnetId string = '${hubVnet.id}/subnets/dnsmig-hub-outbound-subnet'
output onpremSubnetId string = '${onpremVnet.id}/subnets/dnsmig-onprem-subnet'
output spoke1VmSubnetId string = '${spoke1Vnet.id}/subnets/dnsmig-spoke1-vm-subnet'
output spoke2VmSubnetId string = '${spoke2Vnet.id}/subnets/dnsmig-spoke2-vm-subnet'
