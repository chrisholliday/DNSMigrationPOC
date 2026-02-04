targetScope = 'resourceGroup'

param location string = 'centralus'
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string

var privatelinkZone = 'privatelink.blob.${environment().suffixes.storage}'

// Hardcoded values for simplicity
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

var onpremDnsIp = '10.10.1.4'
var onpremClientIp = '10.10.1.5'
var hubDnsIp = '10.20.1.4'
var spoke1VmIp = '10.30.1.4'
var spoke2VmIp = '10.40.1.4'

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
    ]
  }
}

resource spoke1Nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'dnsmig-spoke1-nsg'
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

resource spoke2Nsg 'Microsoft.Network/networkSecurityGroups@2023-09-01' = {
  name: 'dnsmig-spoke2-nsg'
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
    dhcpOptions: {
      dnsServers: [
        onpremDnsIp
      ]
    }
  }
}

resource onpremSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: onpremVnet
  name: 'snet-vm'
  properties: {
    addressPrefix: onpremSubnetPrefix
    networkSecurityGroup: {
      id: onpremNsg.id
    }
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
    dhcpOptions: {
      dnsServers: [
        hubDnsIp
      ]
    }
  }
}

resource hubSubnetVm 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-vm'
  properties: {
    addressPrefix: hubSubnetVmPrefix
    networkSecurityGroup: {
      id: hubNsg.id
    }
  }
}

resource hubSubnetInbound 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-dns-inbound'
  properties: {
    addressPrefix: hubSubnetInboundPrefix
    delegations: [
      {
        name: 'dnsResolverDelegation'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
        }
      }
    ]
  }
}

resource hubSubnetOutbound 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: hubVnet
  name: 'snet-dns-outbound'
  properties: {
    addressPrefix: hubSubnetOutboundPrefix
    delegations: [
      {
        name: 'dnsResolverDelegation'
        properties: {
          serviceName: 'Microsoft.Network/dnsResolvers'
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
    dhcpOptions: {
      dnsServers: [
        hubDnsIp
      ]
    }
  }
}

resource spoke1SubnetVm 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: spoke1Vnet
  name: 'snet-vm'
  properties: {
    addressPrefix: spoke1SubnetVmPrefix
    networkSecurityGroup: {
      id: spoke1Nsg.id
    }
  }
}

resource spoke1SubnetPe 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: spoke1Vnet
  name: 'snet-pe'
  properties: {
    addressPrefix: spoke1SubnetPePrefix
    privateEndpointNetworkPolicies: 'Disabled'
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
    dhcpOptions: {
      dnsServers: [
        hubDnsIp
      ]
    }
  }
}

resource spoke2SubnetVm 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: spoke2Vnet
  name: 'snet-vm'
  properties: {
    addressPrefix: spoke2SubnetVmPrefix
    networkSecurityGroup: {
      id: spoke2Nsg.id
    }
  }
}

resource spoke2SubnetPe 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' = {
  parent: spoke2Vnet
  name: 'snet-pe'
  properties: {
    addressPrefix: spoke2SubnetPePrefix
    privateEndpointNetworkPolicies: 'Disabled'
  }
}

// Peerings
resource onpremToHubPeer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: onpremVnet
  name: 'peer-onprem-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource hubToOnpremPeer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'peer-hub-to-onprem'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: onpremVnet.id
    }
  }
}

resource hubToSpoke1Peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke1'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spoke1Vnet.id
    }
  }
}

resource spoke1ToHubPeer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spoke1Vnet
  name: 'peer-spoke1-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
}

resource hubToSpoke2Peer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: hubVnet
  name: 'peer-hub-to-spoke2'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: spoke2Vnet.id
    }
  }
}

resource spoke2ToHubPeer 'Microsoft.Network/virtualNetworks/virtualNetworkPeerings@2023-09-01' = {
  parent: spoke2Vnet
  name: 'peer-spoke2-to-hub'
  properties: {
    allowVirtualNetworkAccess: true
    allowForwardedTraffic: true
    allowGatewayTransit: false
    useRemoteGateways: false
    remoteVirtualNetwork: {
      id: hubVnet.id
    }
  }
}

// NICs
resource onpremDnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-onprem-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: onpremDnsIp
          subnet: {
            id: onpremSubnet.id
          }
        }
      }
    ]
  }
}

resource onpremClientNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-onprem-nic-client'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: onpremClientIp
          subnet: {
            id: onpremSubnet.id
          }
        }
      }
    ]
  }
}

resource hubDnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-hub-nic-dns'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: hubDnsIp
          subnet: {
            id: hubSubnetVm.id
          }
        }
      }
    ]
  }
}

resource spoke1Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-spoke1-nic-app'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: spoke1VmIp
          subnet: {
            id: spoke1SubnetVm.id
          }
        }
      }
    ]
  }
}

resource spoke2Nic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-spoke2-nic-app'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          privateIPAllocationMethod: 'Static'
          privateIPAddress: spoke2VmIp
          subnet: {
            id: spoke2SubnetVm.id
          }
        }
      }
    ]
  }
}

// Cloud-init for DNS servers
var onpremDnsCloudInit = format(
  '''#cloud-config
package_update: true
packages:
  - dnsmasq
write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      domain=onprem.pvt
      local=/onprem.pvt/
      addn-hosts=/etc/dnsmasq.d/onprem.hosts
      server=/azure.pvt/{0}
      server=/{1}/{0}
      server=168.63.129.16
  - path: /etc/dnsmasq.d/onprem.hosts
    content: |
      {2} onprem-vm-dns.onprem.pvt
      {3} onprem-vm-client.onprem.pvt
runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
''',
  hubDnsIp,
  privatelinkZone,
  onpremDnsIp,
  onpremClientIp
)

var hubDnsCloudInit = format(
  '''#cloud-config
package_update: true
packages:
  - dnsmasq
write_files:
  - path: /etc/dnsmasq.d/custom.conf
    content: |
      domain=azure.pvt
      local=/azure.pvt/
      addn-hosts=/etc/dnsmasq.d/azure.hosts
      local=/{0}/
      addn-hosts=/etc/dnsmasq.d/privatelink.hosts
      server=/onprem.pvt/{1}
      server=168.63.129.16
  - path: /etc/dnsmasq.d/azure.hosts
    content: |
      {2} hub-vm-dns.azure.pvt
      {3} spoke1-vm-app.azure.pvt
      {4} spoke2-vm-app.azure.pvt
  - path: /etc/dnsmasq.d/privatelink.hosts
    content: |
      10.30.2.4 legacyblob.{0}
runcmd:
  - systemctl enable dnsmasq
  - systemctl restart dnsmasq
''',
  privatelinkZone,
  onpremDnsIp,
  hubDnsIp,
  spoke1VmIp,
  spoke2VmIp
)

// VMs
resource onpremDnsVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'dnsmig-onprem-vm-dns'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'dnsmig-onprem-vm-dns'
      adminUsername: adminUsername
      customData: base64(onpremDnsCloudInit)
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
          id: onpremDnsNic.id
        }
      ]
    }
  }
}

resource onpremClientVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'dnsmig-onprem-vm-client'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'dnsmig-onprem-vm-client'
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
          id: onpremClientNic.id
        }
      ]
    }
  }
}

resource hubDnsVm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'dnsmig-hub-vm-dns'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'dnsmig-hub-vm-dns'
      adminUsername: adminUsername
      customData: base64(hubDnsCloudInit)
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
          id: hubDnsNic.id
        }
      ]
    }
  }
}

resource spoke1Vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'dnsmig-spoke1-vm-app'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'dnsmig-spoke1-vm-app'
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
          id: spoke1Nic.id
        }
      ]
    }
  }
}

resource spoke2Vm 'Microsoft.Compute/virtualMachines@2023-03-01' = {
  name: 'dnsmig-spoke2-vm-app'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B1s'
    }
    osProfile: {
      computerName: 'dnsmig-spoke2-vm-app'
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
          id: spoke2Nic.id
        }
      ]
    }
  }
}

output hubDnsIp string = hubDnsIp
output onpremDnsIp string = onpremDnsIp
output spoke1VmIp string = spoke1VmIp
output spoke2VmIp string = spoke2VmIp
output onpremVnetId string = onpremVnet.id
output hubVnetId string = hubVnet.id
output spoke1VnetId string = spoke1Vnet.id
output spoke2VnetId string = spoke2Vnet.id
