# Installs the Azure Monitor Agent on the Arc-enabled homelab server
# Not available via Bicep in polandcentral — see comment in main.bicep
# Docs: https://learn.microsoft.com/en-us/azure/azure-monitor/agents/azure-monitor-agent-manage?tabs=azure-powershell#install-azure-monitor-agent-on-azure-arc-enabled-servers
# Uses Az.ConnectedMachine module — Set-AzVMExtension doesn't support Arc servers
New-AzConnectedMachineExtension `
  -ResourceGroupName "homelab-rg" `
  -Location "polandcentral" `
  -MachineName "homelab" `
  -Name "AzureMonitorAgent" `
  -ExtensionType "AzureMonitorLinuxAgent" `
  -Publisher "Microsoft.Azure.Monitor" `
  -TypeHandlerVersion "1.41"
