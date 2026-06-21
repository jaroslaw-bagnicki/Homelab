param location string

var suffix = take(uniqueString(tenant().tenantId), 6)

// Reference to existing Arc-enabled servers
resource arcServerHomelab 'Microsoft.HybridCompute/machines@2025-06-01' existing = {
  name: 'homelab'
}

resource arcServerCloudlab 'Microsoft.HybridCompute/machines@2025-06-01' existing = {
  name: 'cloudlab'
}

// Azure Monitor Agent extension — installed on each Arc-enabled server.
// The AMA collects the performance counters defined in the DCR below.
resource amaHomelab 'Microsoft.HybridCompute/machines/extensions@2025-06-01' = {
  parent: arcServerHomelab
  name: 'AzureMonitorAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    enableAutomaticUpgrade: true
  }
}

resource amaCloudlab 'Microsoft.HybridCompute/machines/extensions@2025-06-01' = {
  parent: arcServerCloudlab
  name: 'AzureMonitorAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    enableAutomaticUpgrade: true
  }
}

// Link the DCR to each Arc-enabled server
resource dcrAssociationHomelab 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'homelab-vm-dcr-association'
  scope: arcServerHomelab
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

resource dcrAssociationCloudlab 'Microsoft.Insights/dataCollectionRuleAssociations@2024-03-11' = {
  name: 'cloudlab-vm-dcr-association'
  scope: arcServerCloudlab
  properties: {
    dataCollectionRuleId: dcr.id
  }
}

// Data Collection Rule — uses the VM Insights meta-counter that expands to the full
// standard counter set. Matches the DCR shape from:
// https://learn.microsoft.com/en-us/azure/azure-monitor/vm/vm-enable-monitoring
resource dcr 'Microsoft.Insights/dataCollectionRules@2024-03-11' = {
  name: 'homelab-vm-dcr'
  location: location
  kind: 'Linux'
  properties: {
    dataSources: {
      performanceCounters: [
        {
          name: 'VMInsightsPerfCounters'
          streams: [
            'Microsoft-InsightsMetrics'
          ]
          samplingFrequencyInSeconds: 60
          counterSpecifiers: [
            '\\VmInsights\\DetailedMetrics'
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
