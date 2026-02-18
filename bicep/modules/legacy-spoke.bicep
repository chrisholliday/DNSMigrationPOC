targetScope = 'resourceGroup'

param location string
param prefix string
param adminUsername string
@secure()
param sshPublicKey string
param vmSize string
param addressSpace string
param subnetVmPrefix string
param subnetPePrefix string
param dnsServerIp string
param vmIp string
param vnetName string
param vmNameSuffix string

var nsgName = '${prefix}-${vmNameSuffix}-nsg'
var vmName = '${prefix}-${vmNameSuffix}'

// NAT Gateway resources
resource spokeNatGatewayPublicIp 'Microsoft.Network/publicIPAddresses@2023-09-01' = {
  name: '${prefix}-${vmNameSuffix}-nat-pip'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIPAllocationMethod: 'Static'
  }
}

resource spokeNatGateway 'Microsoft.Network/natGateways@2023-09-01' = {
  name: '${prefix}-${vmNameSuffix}-nat'
  location: location
  sku: {
    name: 'Standard'
  }
  properties: {
    publicIpAddresses: [
      {
        id: spokeNatGatewayPublicIp.id
      }
    ]
  }
}

resource spokeNsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: nsgName
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
    ]
  }
}

resource spokeVnet 'Microsoft.Network/virtualNetworks@2023-09-01' = {
  name: vnetName
  location: location
  properties: {
    addressSpace: {
      addressPrefixes: [
        addressSpace
      ]
    }
    dhcpOptions: {
      dnsServers: [
        dnsServerIp
      ]
    }
    subnets: [
      {
        name: 'snet-vm'
        properties: {
          addressPrefix: subnetVmPrefix
          networkSecurityGroup: {
            id: spokeNsg.id
          }
          natGateway: {
            id: spokeNatGateway.id
          }
        }
      }
      {
        name: 'snet-pe'
        properties: {
          addressPrefix: subnetPePrefix
          privateEndpointNetworkPolicies: 'Disabled'
        }
      }
    ]
  }
}

resource vmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: '${prefix}-${vmNameSuffix}-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: vmIp
          subnet: {
            id: '${spokeVnet.id}/subnets/snet-vm'
          }
        }
      }
    ]
  }
}

resource spokeVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: vmName
  location: location
  properties: {
    hardwareProfile: {
      vmSize: vmSize
    }
    osProfile: {
      computerName: vmName
      adminUsername: adminUsername
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
        sku: '22_04-lts'
        version: 'latest'
      }
      osDisk: {
        createOption: 'FromImage'
        managedDisk: {
          storageAccountType: 'Standard_LRS'
        }
      }
    }
    networkProfile: {
      networkInterfaces: [
        {
          id: vmNic.id
        }
      ]
    }
  }
}

output spokeVnetId string = spokeVnet.id
output spokeVmIp string = vmIp
