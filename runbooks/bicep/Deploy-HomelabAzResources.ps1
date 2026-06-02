New-AzResourceGroupDeployment `
  -ResourceGroupName 'homelab-rg' `
  -TemplateFile "$PSScriptRoot/main.bicep" `
  -Location 'polandcentral'
