# Installs the Azure Monitor Agent on the Arc-enabled homelab server
# Not available via Bicep in polandcentral — see comment in main.bicep
Set-AzVMExtension `
  -ResourceGroupName "homelab-rg" `
  -Location "polandcentral" `
  -VMName "homelab" `
  -Name "AzureMonitorAgent" `
  -ExtensionType "AzureMonitorLinuxAgent" `
  -Publisher "Microsoft.Azure.Monitor" `
  -TypeHandlerVersion "1.40" `
  -MachineType "HybridMachine"
