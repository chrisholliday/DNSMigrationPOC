// On-Prem Infrastructure Module
// Deployed to: rg-onprem-dnsmig
// Contains: VNet, VMs, Bastion, NAT Gateway using Azure DNS

metadata description = 'On-Prem infrastructure module (resource group scope)'

@description('Azure region for resources')
param location string

@description('SSH public key for VM authentication')
param sshPublicKey string

@description('VM admin username')
param vmAdminUsername string = 'azureuser'

// Naming convention
var vnetName = 'onprem-vnet'
var bastionSubnetName = 'AzureBastionSubnet'
var workloadSubnetName = 'onprem-subnet-workload'
var natGatewayName = 'onprem-natgw'
var nsgName = 'onprem-nsg'
var bastionName = 'onprem-bastion'
var dnsVmName = 'onprem-vm-dns'
var clientVmName = 'onprem-vm-client'

var vnetAddressPrefix = '10.0.0.0/16'
var bastionSubnetPrefix = '10.0.1.0/24'
var workloadSubnetPrefix = '10.0.10.0/24'
var dnsVmIp = '10.0.10.4'
var clientVmIp = '10.0.10.5'

// ===============================
// NETWORK SECURITY GROUP
// ===============================
resource nsg 'Microsoft.Network/networkSecurityGroups@2021-08-01' = {
  name: nsgName
  location: location
  properties: {
    securityRules: [
      {
        name: 'AllowSSHFromOnprem'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.0.0.0/16'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowSSHFromHub'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '10.1.0.0/16'
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
          sourceAddressPrefix: '10.0.1.0/24'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 102
          direction: 'Inbound'
        }
      }
      {
        name: 'AllowDNSFromHub'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: '10.1.0.0/16'
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
      {
        name: 'AllowHTTP'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '80'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 103
          direction: 'Outbound'
        }
      }
      {
        name: 'AllowDNSToHub'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '10.1.0.0/16'
          access: 'Allow'
          priority: 104
          direction: 'Outbound'
        }
      }
    ]
  }
}

// ===============================
// VIRTUAL NETWORK (Azure DNS)
// ===============================
resource vnet 'Microsoft.Network/virtualNetworks@2021-08-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressPrefix
      ]
    }
    // Note: No dhcpOptions.dnsServers - using Azure DNS (168.63.129.16)
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

// ===============================
// NAT GATEWAY
// ===============================
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

// ===============================
// AZURE BASTION
// ===============================
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

// ===============================
// NETWORK INTERFACES
// ===============================
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
          privateIPAddress: dnsVmIp
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

resource clientNic 'Microsoft.Network/networkInterfaces@2021-08-01' = {
  name: '${clientVmName}-nic'
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
          privateIPAddress: clientVmIp
        }
      }
    ]
    networkSecurityGroup: {
      id: nsg.id
    }
  }
}

// ===============================
// VIRTUAL MACHINES
// ===============================
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

resource clientVm 'Microsoft.Compute/virtualMachines@2021-07-01' = {
  name: clientVmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: clientVmName
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
          id: clientNic.id
        }
      ]
    }
  }
}

// ===============================
// VM EXTENSIONS
// ===============================
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

resource clientVmExtension 'Microsoft.Compute/virtualMachines/extensions@2021-07-01' = {
  parent: clientVm
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

// ===============================
// OUTPUTS
// ===============================
output vnetId string = vnet.id
output vnetName string = vnet.name
output dnsVmPrivateIp string = dnsNic.properties.ipConfigurations[0].properties.privateIPAddress
output clientVmPrivateIp string = clientNic.properties.ipConfigurations[0].properties.privateIPAddress
output dnsVmId string = dnsVm.id
output clientVmId string = clientVm.id
output bastionName string = bastion.name
output natGatewayPublicIp string = natGatewayPip.properties.ipAddress
