param (
    [string]$SPName,
    [string]$RGName,
    [string]$TFCProjectName,
    [string]$TFCWorkspaceName
)

if ($args.Length -ne 4) {
    Clear-Host
    Write-Host "Usage : $PSCommandPath SP_name RG_name tfc_prj_name tfc_workspace_name"
    Write-Host
    Write-Host "Assumption: environment variable TF_CLOUD_ORGANIZATION is available"
    Write-Host "This script requires 4 arguments"
    # ... rest of the usage message ...
    exit 0
}

if (Test-AzResourceGroup -ResourceGroupName $RGName) {
    Write-Host "Resource Group $RGName already exists"
    $subsId = (az account show | ConvertFrom-Json).id
}
else {
    $location = Read-Host "Enter the Azure region (AustraliaEast|AustraliaSouthEast) to create resource group"
    Write-Host "Creating Resource Group $RGName in region $location"
    $rgOutput = (az group create --name $RGName --location $location | ConvertFrom-Json)
    $subsId = $rgOutput.id -split "/")[2]
}

if ((az ad sp list --display-name $SPName | ConvertFrom-Json).Count -gt 0) {
    Write-Host "Service Principal $SPName already exists, checking if role assignment exists"
    $appId = (az ad sp list --display-name $SPName | ConvertFrom-Json)[0].appId
    $RGAppID = (az role assignment list --resource-group $RGName | ConvertFrom-Json | Where-Object { $_.principalName -eq $appId }).principalName
    if ($RGAppID -eq $appId) {
        Write-Host "Role assignment already exists"
    }
    else {
        Write-Host "Role assignment does not exist, creating role assignment"
        az role assignment create --assignee $appId --role Contributor --scope "/subscriptions/$subsId/resourceGroups/$RGName"
    }
}
else {
    Write-Host "Service Principal $SPName does not exist"
    Write-Host "Creating service principal $SPName and assigning permission"
    $spOutput = (az ad sp create-for-rbac -n $SPName --role Contributor --scopes "/subscriptions/$subsId/resourceGroups/$RGName" | ConvertFrom-Json)
}

$fcNamePlan = "fc-$RGName-plan"
$fcNameApply = "fc-$RGName-apply"
$fcDesc = "Terraform Federated credential for SP $SPName"
$issuer = "https://app.terraform.io"
$subjectPlan = "organization:$env:TF_CLOUD_ORGANIZATION:project:$TFCProjectName:workspace:$TFCWorkspaceName:run_phase:plan"
$subjectApply = "organization:$env:TF_CLOUD_ORGANIZATION:project:$TFCProjectName:workspace:$TFCWorkspaceName:run_phase:apply"
$audiences = '["api://AzureADTokenExchange"]'

$plan = @{
    name = $fcNamePlan
    issuer = $issuer
    subject = $subjectPlan
    description = "$fcDesc plan"
    audiences = $audiences | ConvertFrom-Json
}

$apply = @{
    name = $fcNameApply
    issuer = $issuer
    subject = $subjectApply
    description = "$fcDesc apply"
    audiences = $audiences | ConvertFrom-Json
}

$objId = (az ad sp list --display-name $SPName | ConvertFrom-Json)[0].appId
$jsonArray = az ad app federated-credential list --id $objId | ConvertFrom-Json

$fcIdPlan = $jsonArray | Where-Object { $_.name -eq $fcNamePlan } | Select-Object -ExpandProperty name

if ($fcIdPlan -ne $fcNamePlan) {
    Write-Host "Creating federated credential $fcNamePlan"
    az ad app federated-credential create --id $objId --parameters ($plan | ConvertTo-Json)
}
else {
    Write-Host "Federated Credential $fcNamePlan exists, skipping step..."
}

$fcIdApply = $jsonArray | Where-Object { $_.name -eq $fcNameApply } | Select-Object -ExpandProperty name

if ($fcIdApply -ne $fcNameApply) {
    Write-Host "Creating federated credential $fcNameApply"
    az ad app federated-credential create --id $objId --parameters ($apply | ConvertTo-Json)
}
else {
    Write-Host "Federated Credential $fcNameApply exists, skipping step..."
}