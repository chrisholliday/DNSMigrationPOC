targetScope = 'resourceGroup'

param location string = 'centralus'
param adminUsername string = 'azureuser'
@secure()
param sshPublicKey string

// Hardcoded values
var onpremDnsIp = '10.10.1.4'
var onpremClientIp = '10.10.1.5'
var hubDnsIp = '10.20.1.4'
var spoke1VmIp = '10.30.1.4'
var spoke2VmIp = '10.40.1.4'

// Reference VNets and subnets created by phase 1
resource onpremVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-onprem-vnet'
}

resource hubVnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-hub-vnet'
}

resource spoke1Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-spoke1-vnet'
}

resource spoke2Vnet 'Microsoft.Network/virtualNetworks@2023-09-01' existing = {
  name: 'dnsmig-spoke2-vnet'
}

resource onpremSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: onpremVnet
  name: 'dnsmig-onprem-subnet'
}

resource hubVmSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: hubVnet
  name: 'dnsmig-hub-vm-subnet'
}

resource spoke1VmSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: spoke1Vnet
  name: 'dnsmig-spoke1-vm-subnet'
}

resource spoke2VmSubnet 'Microsoft.Network/virtualNetworks/subnets@2023-09-01' existing = {
  parent: spoke2Vnet
  name: 'dnsmig-spoke2-vm-subnet'
}

// On-Prem DNS Server NIC
resource onpremDnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-onprem-dns-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: onpremSubnet.id
          }
          privateIPAddress: onpremDnsIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

// On-Prem Client NIC
resource onpremClientNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-onprem-client-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: onpremSubnet.id
          }
          privateIPAddress: onpremClientIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

// Hub DNS Server NIC
resource hubDnsNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-hub-dns-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: hubVmSubnet.id
          }
          privateIPAddress: hubDnsIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

// Spoke1 App VM NIC
resource spoke1VmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-spoke1-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: spoke1VmSubnet.id
          }
          privateIPAddress: spoke1VmIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

// Spoke2 App VM NIC
resource spoke2VmNic 'Microsoft.Network/networkInterfaces@2023-09-01' = {
  name: 'dnsmig-spoke2-vm-nic'
  location: location
  properties: {
    ipConfigurations: [
      {
        name: 'ipconfig1'
        properties: {
          subnet: {
            id: spoke2VmSubnet.id
          }
          privateIPAddress: spoke2VmIp
          privateIPAllocationMethod: 'Static'
        }
      }
    ]
  }
}

// On-Prem DNS Server VM
resource onpremDnsVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'dnsmig-onprem-dns'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'dns-onprem'
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
          id: onpremDnsNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource onpremDnsVmExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: onpremDnsVm
  name: 'CloudInit'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get install -y dnsutils curl\n')
    }
  }
}

// On-Prem Client VM
resource onpremClientVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'dnsmig-onprem-client'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'client-onprem'
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
          id: onpremClientNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource onpremClientVmExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: onpremClientVm
  name: 'CloudInit'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64(format(
        '#!/bin/bash\napt-get update\napt-get install -y dnsutils\necho "nameserver {0}" > /etc/resolv.conf\n',
        onpremDnsIp
      ))
    }
  }
}

// Hub DNS Server VM
resource hubDnsVm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'dnsmig-hub-dns'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'dns-hub'
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
          id: hubDnsNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource hubDnsVmExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: hubDnsVm
  name: 'CloudInit'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get install -y dnsutils curl\n')
    }
  }
}

// Spoke1 App VM
resource spoke1Vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'dnsmig-spoke1-app'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'app-spoke1'
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
          id: spoke1VmNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource spoke1VmExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: spoke1Vm
  name: 'CloudInit'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get install -y dnsutils curl\n')
    }
  }
}

// Spoke2 App VM
resource spoke2Vm 'Microsoft.Compute/virtualMachines@2023-09-01' = {
  name: 'dnsmig-spoke2-app'
  location: location
  properties: {
    hardwareProfile: {
      vmSize: 'Standard_B2s'
    }
    osProfile: {
      computerName: 'app-spoke2'
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
          id: spoke2VmNic.id
          properties: {
            primary: true
          }
        }
      ]
    }
  }
}

resource spoke2VmExt 'Microsoft.Compute/virtualMachines/extensions@2023-09-01' = {
  parent: spoke2Vm
  name: 'CloudInit'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Extensions'
    type: 'CustomScript'
    typeHandlerVersion: '2.1'
    autoUpgradeMinorVersion: true
    settings: {
      script: base64('#!/bin/bash\napt-get update\napt-get install -y dnsutils curl\n')
    }
  }
}

output vmsCreated bool = true
