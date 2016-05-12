[CmdletBinding(PositionalBinding=$True)]
Param(
    [parameter(Mandatory=$true)]
    [string]$ExampleDir
    )

###########################################################
# Start - Initialization - Invocation, Logging etc
###########################################################
$VerbosePreference = "SilentlyContinue"
$ErrorActionPreference = "Stop"

$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath

& "$scriptDir\..\init.ps1"
if(-not $?)
{
    throw "Initialization failure."
    exit -9999
}
###########################################################
# End - Initialization - Invocation, Logging etc
###########################################################

###########################################################
# Main Script
###########################################################

# Make sure you run this in Microsoft Azure Powershell prompt
if(-not (& "$scriptDir\CheckAzurePowershell.ps1"))
{
    Write-ErrorLog "Check Azure Powershell Failed! You need to run this script from Azure Powershell." (Get-ScriptName) (Get-ScriptLineNumber)
    throw "Check Azure Powershell Failed! You need to run this script from Azure Powershell."
}

$startTime = Get-Date

Write-SpecialLog "Deleting Azure resources for example: $ExampleDir" (Get-ScriptName) (Get-ScriptLineNumber)

$configFile = Join-Path $ExampleDir "run\configurations.properties"
$config = & "$scriptDir\..\config\ReadConfig.ps1" $configFile

$config.Keys | sort | % { if(-not ($_.Contains("PASSWORD") -or $_.Contains("KEY"))) { Write-SpecialLog ("Key = " + $_ + ", Value = " + $config[$_]) (Get-ScriptName) (Get-ScriptLineNumber) } }

Write-SpecialLog ("Please provide Azure crendetials for your subscription: {0} - {1}" -f $config["AZURE_SUBSCRIPTION_NAME"], $config["AZURE_SUBSCRIPTION_ID"]) (Get-ScriptName) (Get-ScriptLineNumber)

Login-AzureRmAccount -Tenant $config["AZURE_TENANT_ID"] -SubscriptionId $config["AZURE_SUBSCRIPTION_ID"]

#Changing Error Action to Continue here onwards to have maximum resource deletion
$ErrorActionPreference = "Continue"

$docdb = $false
if($config["DOCUMENTDB"].Equals("true", [System.StringComparison]::OrdinalIgnoreCase))
{
    $docdb = $true
}

$success = $true

if($docdb)
{
    Write-InfoLog "Deleting DocumentDB" (Get-ScriptName) (Get-ScriptLineNumber)
    & "$scriptDir\DocumentDB\DeleteDocumentDBARM.ps1"  $config["AZURE_RESOURCE_GROUP"] $config["DOCUMENTDB_ACCOUNT"]
    $success = $success -and $?
}

Write-InfoLog "Deleting Azure Resource Group" (Get-ScriptName) (Get-ScriptLineNumber)
& "$scriptDir\DeleteAzureResourceGroup.ps1" $config["AZURE_RESOURCE_GROUP"]
$success = $success -and $?

if($success)
{
    Write-SpecialLog "Deleting configuration.properties file" (Get-ScriptName) (Get-ScriptLineNumber)
    Remove-Item $configFile
    $totalSeconds = ((Get-Date) - $startTime).TotalSeconds
    Write-SpecialLog "Deleted Azure resources, completed in $totalSeconds seconds" (Get-ScriptName) (Get-ScriptLineNumber)
}
else
{
    Write-ErrorLog "One or more errors occurred during Azure resource deletion. Please check logs for error information." (Get-ScriptName) (Get-ScriptLineNumber)
    Write-ErrorLog "Please retry and delete your configuration file manually from: $configFile" (Get-ScriptName) (Get-ScriptLineNumber)
    throw "One or more errors occurred during Azure resource deletion. Please check logs for error information."
}