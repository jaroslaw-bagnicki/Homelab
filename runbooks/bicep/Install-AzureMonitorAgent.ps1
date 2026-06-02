# Installs the Azure Monitor Agent on the Arc-enabled homelab server
# Not available via Bicep in polandcentral — see comment in main.bicep
# Docs: https://learn.microsoft.com/en-us/azure/azure-arc/servers/manage-vm-extensions#enable-extensions-from-the-portal
# Uses Az.ConnectedMachine module — Set-AzVMExtension doesn't support Arc servers
New-AzConnectedMachineExtension `
  -ResourceGroupName "homelab-rg" `
  -Location "polandcentral" `
  -MachineName "homelab" `
  -Name "AzureMonitorAgent" `
  -ExtensionType "AzureMonitorLinuxAgent" `
  -Publisher "Microsoft.Azure.Monitor" `
  -TypeHandlerVersion "1.40"
