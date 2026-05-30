# Add the service principal application ID and certificate path
ServicePrincipalId="525b1595-071d-469f-a2c6-0680cda35b4b";
ServicePrincipalCert="~/homelab-arc-agent.crt";


export subscriptionId="a8a36bc1-79a7-49fe-9faa-92220103c66f";
export resourceGroup="homelab-rg";
export tenantId="b48c71d0-46cf-4171-ad02-1ed785ba425d";
export location="polandcentral";
export authType="principal";
export correlationId="961e18eb-03aa-4934-bf65-26961f8f18fc";
export cloud="AzureCloud";


# Download the installation package
LINUX_INSTALL_SCRIPT="/tmp/install_linux_azcmagent.sh"
if [ -f "$LINUX_INSTALL_SCRIPT" ]; then rm -f "$LINUX_INSTALL_SCRIPT"; fi;
output=$(wget https://gbl.his.arc.azure.com/azcmagent-linux -O "$LINUX_INSTALL_SCRIPT" 2>&1);
if [ $? != 0 ]; then wget -qO- --method=PUT --body-data="{\"subscriptionId\":\"$subscriptionId\",\"resourceGroup\":\"$resourceGroup\",\"tenantId\":\"$tenantId\",\"location\":\"$location\",\"correlationId\":\"$correlationId\",\"authType\":\"$authType\",\"operation\":\"onboarding\",\"messageType\":\"DownloadScriptFailed\",\"message\":\"$output\"}" "https://gbl.his.arc.azure.com/log" &> /dev/null || true; fi;
echo "$output";

# Install the hybrid agent
bash "$LINUX_INSTALL_SCRIPT";
sleep 5;

# Run connect command
sudo azcmagent connect --service-principal-id "$ServicePrincipalId" --service-principal-cert "$ServicePrincipalCert" --resource-group "$resourceGroup" --tenant-id "$tenantId" --location "$location" --subscription-id "$subscriptionId" --cloud "$cloud" --tags 'ArcSQLServerExtensionDeployment=Disabled' --correlation-id "$correlationId";
