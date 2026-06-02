param location string

// Reference to the existing Arc-enabled server
resource arcServer 'Microsoft.HybridCompute/machines@2025-06-01' existing = {
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

// Azure Monitor Agent extension on the Arc server
resource ama 'Microsoft.HybridCompute/machines/extensions@2025-06-01' = {
  parent: arcServer
  name: 'AzureMonitorAgent'
  location: location
  properties: {
    publisher: 'Microsoft.Azure.Monitor'
    type: 'AzureMonitorLinuxAgent'
    typeHandlerVersion: '1.32'
  }
}

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
