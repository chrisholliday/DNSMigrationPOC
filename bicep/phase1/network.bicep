targetScope = 'resourceGroup'

param location string = 'centralus'
param prefix string = 'dnsmig'
param adminUsername string = 'azureuser'

@secure()
param sshPublicKey string

param vmSize string = 'Standard_B2s'
param vnetAddressSpace string = '10.10.0.0/16'
param vmSubnetPrefix string = '10.10.1.0/24'

// Static IPs
param dnsServerIp string = '10.10.1.10'
param clientVmIp string = '10.10.1.20'

/////////////////////
// NETWORKING
/////////////////////

// Public IP for NAT Gateway (outbound internet connectivity)
resource natPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-onprem-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

// NAT Gateway for reliable outbound internet access
resource natGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${prefix}-onprem-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: natPublicIp.id
      }
    ]
  }
}

// Network Security Group
resource nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: '${prefix}-onprem-nsg'
  location: location
  properties: {
    securityRules: [
      {
        name: 'Allow-SSH'
        properties: {
          protocol: 'Tcp'
          sourcePortRange: '*'
          destinationPortRange: '22'
          sourceAddressPrefix: '*'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 100
          direction: 'Inbound'
        }
      }
      {
        name: 'Allow-DNS'
        properties: {
          protocol: '*'
          sourcePortRange: '*'
          destinationPortRange: '53'
          sourceAddressPrefix: 'VirtualNetwork'
          destinationAddressPrefix: '*'
          access: 'Allow'
          priority: 110
          direction: 'Inbound'
        }
      }
    ]
  }
}

// Virtual Network
resource vnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: '${prefix}-onprem-vnet'
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        vnetAddressSpace
      ]
    }
    subnets: [
      {
        name: 'snet-vms'
        properties: {
          addressPrefix: vmSubnetPrefix
          networkSecurityGroup: {
            id: nsg.id
          }
          natGateway: {
            id: natGateway.id
          }
        }
      }
    ]
  }
}

/////////////////////
// DNS SERVER VM
/////////////////////

// Network Interface for DNS Server
resource dnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: dnsServerIp
          subnet: {
            id: '${vnet.id}/subnets/snet-vms'
          }
        }
      }
    ]
  }
}

// Minimal cloud-init: just basic setup, no DNS config in this phase
var dnsServerCloudInit = base64('''#cloud-config
package_update: true
packages:
  - curl
  - net-tools
  - wget

runcmd:
  - echo "DNS Server (10.10.1.10) base setup complete" > /tmp/phase1-ready.log
  - echo "Waiting for Phase 2 DNS configuration..." >> /tmp/phase1-ready.log
''')

// DNS Server VM
resource dnsVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-onprem-vm-dns'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${prefix}-onprem-vm-dns'
      adminUsername: adminUsername
      customData: dnsServerCloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
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

/////////////////////
// CLIENT VM
/////////////////////

// Network Interface for Client VM
resource clientNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-onprem-nic-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: clientVmIp
          subnet: {
            id: '${vnet.id}/subnets/snet-vms'
          }
        }
      }
    ]
  }
}

// Minimal cloud-init for client VM
var clientCloudInit = base64('''#cloud-config
package_update: true
packages:
  - curl
  - net-tools
  - wget

runcmd:
  - echo "Client VM (10.10.1.20) base setup complete" > /tmp/phase1-ready.log
  - echo "Waiting for Phase 3 client configuration..." >> /tmp/phase1-ready.log
''')

// Client VM
resource clientVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: '${prefix}-onprem-vm-client'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: '${prefix}-onprem-vm-client'
      adminUsername: adminUsername
      customData: clientCloudInit
      linuxConfiguration: {
        disablePasswordAuthentication: true
        ssh: {
          publicKeys: [
            {
              path: '/home/${adminUsername}/.ssh/authorized_keys'
              keyData: sshPublicKey
            }
          ]
        }
      }
    }
    storageProfile: {
      imageReference: {
        publisher: 'Canonical'
        offer: '0001-com-ubuntu-server-jammy'
        sku: '22_04-lts-gen2'
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

//////////////////////
// OUTPUTS
/////////////////////

output vnetId string = vnet.id
output vnetName string = vnet.name
output dnsServerPrivateIp string = dnsServerIp
output clientVmPrivateIp string = clientVmIp
output dnsServerVmId string = dnsVm.id
output dnsServerVmName string = dnsVm.name
output clientVmId string = clientVm.id
output clientVmName string = clientVm.name
output natGatewayPublicIp string = natPublicIp.properties.ipAddress
