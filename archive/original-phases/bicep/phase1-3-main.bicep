// Phase 1.3 - Hub Infrastructure
// Deploys: Hub VNet, Subnets, NAT Gateway, Azure Bastion, 2 VMs (dns + app), VNet Peering to On-Prem

metadata description = 'Phase 1.3: Hub VNet with basic infrastructure, VMs, and peering to On-Prem'

param location string = 'centralus'
param environmentName string = 'hub'
param sshPublicKey string
param vmAdminUsername string = 'azureuser'
param onpremVnetId string
param onpremDnsIp string

// Naming convention
var vnetName = '${environmentName}-vnet'
var bastionSubnetName = 'AzureBastionSubnet'
var workloadSubnetName = '${environmentName}-subnet-workload'
var natGatewayName = '${environmentName}-natgw'
var nsgName = '${environmentName}-nsg'
var bastionName = '${environmentName}-bastion'
var dnsVmName = '${environmentName}-vm-dns'
var appVmName = '${environmentName}-vm-app'
var peeringToOnpremName = 'hub-to-onprem'

var vnetAddressPrefix = '10.1.0.0/16'
var bastionSubnetPrefix = '10.1.1.0/24'
var workloadSubnetPrefix = '10.1.10.0/24'

// Resources

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHFromHub'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.1.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSSHFromOnprem'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 101
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSSHFromBastion'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.1.1.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowDNSFromOnprem'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 103
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowHTTPS'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '443'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Outbound'
        }
      }
    ]
  }
}

// Virtual Network with DNS servers pointing to on-prem DNS
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    dhcpOptions: {
      dnsServers: [
        onpremDnsIp
      ]
    }
    subnets: [
      {
        name: bastionSubnetName
        properties: {
          addressPrefix: bastionSubnetPrefix
        }
      }
      {
        name: workloadSubnetName
        properties: {
          addressPrefix: workloadSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
        }
      }
    ]
  }
}

// VNet Peering: Hub to On-Prem
// Note: Reverse peering (on-prem to hub) is created by the deployment script
// to avoid cross-resource-group scope issues in Bicep
resource peeringToOnprem 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2021-08-01' = {
  parent: vnet
  name: peeringToOnpremName
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: onpremVnetId
    }
  }
}

// Public IP for NAT Gateway
resource natGatewayPip 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: '${natGatewayName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
    idleTimeoutInMinutes: 4
  }
}

// NAT Gateway
resource natGateway 'Microsoft.Network/natGateways@2021-08-01' = {
  name: natGatewayName
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natGatewayPip.id
      }
    ]
    idleTimeoutInMinutes: 4
  }
}

// Associate NAT Gateway with workload subnet
resource workloadSubnetRef 'Microsoft.Network/virtualNetworks/subnets@2021-08-01' = {
  parent: vnet
  name: workloadSubnetName
  properties: {
    addressPrefix: workloadSubnetPrefix
    networkSecurityGroup: {
      id: nsg.id
    }
    natGateway: {
      id: natGateway.id
    }
  }
}

// Public IP for Bastion
resource bastionPip 'Microsoft.Network/publicIPAddresses@2021-08-01' = {
  name: '${bastionName}-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// Azure Bastion
resource bastion 'Microsoft.Network/bastionHosts@2021-08-01' = {
  name: bastionName
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'IpConf'
        properties: {
          subnet: {
            id: '${vnet.id}/subnets/${bastionSubnetName}'
          }
          publicIPAddress: {
            id: bastionPip.id
          }
        }
      }
    ]
  }
}

// Network Interface for DNS VM
resource dnsNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${dnsVmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: workloadSubnetRef.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.1.10.4'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// Network Interface for App VM
resource appNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${appVmName}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: workloadSubnetRef.id
          }
          privateIPAllocationMethod: 'Static'
          privateIPAddress: '10.1.10.5'
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// DNS VM
resource dnsVm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: dnsVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: dnsVmName
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: dnsNic.id
        }
      ]
    }
  }
}

// App VM
resource appVm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: appVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: appVmName
      adminUsername: vmAdminUsername
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${vmAdminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-focal'
        sku: '20_04-lts-gen2'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Premium_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: appNic.id
        }
      ]
    }
  }
}

// Virtual Machine Extension to update packages on DNS VM
resource dnsVmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: dnsVm
  name: 'ConfigureVM'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get upgrade -y\napt-get install -y curl dnsutils\n')
    }
  }
}

// Virtual Machine Extension for app VM
resource appVmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: appVm
  name: 'ConfigureVM'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get upgrade -y\napt-get install -y curl dnsutils net-tools\n')
    }
  }
}

output vnetId string = vnet.id
output vnetName string = vnet.name
output dnsVmPrivateIp string = dnsNic.properties.ipConfigurations[0].properties.privateIPAddress
output appVmPrivateIp string = appNic.properties.ipConfigurations[0].properties.privateIPAddress
output dnsVmId string = dnsVm.id
output appVmId string = appVm.id
output bastionName string = bastion.name
output natGatewayPublicIp string = natGatewayPip.properties.ipAddress
output peeringToOnpremId string = peeringToOnprem.id
