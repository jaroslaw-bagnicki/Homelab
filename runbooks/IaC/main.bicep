param location string

var suffix = take(uniqueString(tenant().tenantId), 6)

// Reference to the existing Arc-enabled server
resource arcServer 'Microsoft.HybridCompute/machines@2024-07-10' existing = {
  name: 'homelab'
}


// Log Analytics workspace — stores metrics and logs
resource law 'Microsoft.OperationalInsights/workspaces@2025-07-01' = {
  name: 'homelab-law'
  location: location
  properties: {
    sku: {
      name: 'PerGB2018'
    }
  }
}

// Azure Monitor Agent extension — commented out because the publisher/type
// combination (Microsoft.Azure.Monitor / AzureMonitorLinuxAgent) is not
// available in polandcentral via the HybridCompute RP. Install via PowerShell
// with New-AzConnectedMachineExtension instead.
// See Install-AzureMonitorAgent.ps1 and
// https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions
// resource ama 'Microsoft.HybridCompute/machines/extensions@2024-07-10' = {
//   parent: arcServer
//   name: 'AzureMonitorAgent'
//   location: location
//   properties: {
//     publisher: 'Microsoft.Azure.Monitor'
//     type: 'AzureMonitorLinuxAgent'
//     autoUpgradeMinorVersion: true
//   }
// }

// Data Collection Rule — defines what telemetry to collect and where to send it
resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: 'homelab-vm-dcr'
  location: location
  kind: 'Linux'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'linuxPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\Processor\\% Processor Time'
            '\\Memory\\% Used Memory'
            '\\Disk\\% Used Space'
          ]
        }
      ]
    }
    destinations: {
      logAnalytics: [
        {
          workspaceResourceId: law.id
          name: 'homelab-law-destination'
        }
      ]
    }
    dataFlows: [
      {
        streams: [
          'Microsoft-InsightsMetrics'
        ]
        destinations: [
          'homelab-law-destination'
        ]
      }
    ]
  }
}

// Link the DCR to the Arc server
resource dcrAssociation 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'homelab-vm-dcr-association'
  scope: arcServer
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

// Key Vault — stores secrets (SSH keys, etc.), RBAC-only (no access policies)
resource kv 'Microsoft.KeyVault/vaults@2026-02-01' = {
  name: 'homelab-${suffix}-kv'
  location: location
  properties: {
    sku: {
      name: 'standard'
      family: 'A'
    }
    tenantId: subscription().tenantId
    enableRbacAuthorization: true
    softDeleteRetentionInDays: 7
  }
}
