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

###########################################################
# Get Run Configuration
###########################################################
$configFile = Join-Path $ExampleDir "run\configurations.properties"
# Make sure you run this in Microsoft Azure Powershell prompt
if(-not (Test-Path $configFile))
{
    Write-ErrorLog "No run configuration file found at '$configFile'" (Get-ScriptName) (Get-ScriptLineNumber)
    throw "No run configuration file found at '$configFile'"
}
$config = & "$scriptDir\..\config\ReadConfig.ps1" $configFile

###########################################################
# Add Azure Account
###########################################################

try
{
    $account = Get-AzureRmContext
}
catch {}

if($account -eq $null)
{
    $account = Add-AzureRmAccount
    if($account -eq $null)
    {
        Write-ErrorLog "Failed to add Azure RM Account." (Get-ScriptName) (Get-ScriptLineNumber)
        throw "Failed to add Azure RM Account."
    }
}
Write-SpecialLog ("Using Azure RM Account: " + $account.Name) (Get-ScriptName) (Get-ScriptLineNumber)

$subscriptions = Get-AzureRmSubscription
$subId = ($subscriptions | ? { $_.SubscriptionId -eq $config["AZURE_SUBSCRIPTION_ID"] } | Select-Object -First 1 ).SubscriptionId
if($subId -eq $null)
{
    Write-InfoLog ("Available Subscription Names:" + ($subscriptions | Out-String)) (Get-ScriptName) (Get-ScriptLineNumber)

    $subId = Read-Host "Enter Azure Subscription Name or Id)"

    $subscription = $subscriptions | ? { ($_.SubscriptionName -eq $subId) -or ($_.SubscriptionId -eq $subId) } | Select-Object -First 1
    #Update the Azure Subscription Id in config
    & "$scriptDir\..\config\ReplaceStringInFile.ps1" $configFile $configFile `
    @{
        AZURE_SUBSCRIPTION_NAME=$subscription.SubscriptionName
        AZURE_SUBSCRIPTION_ID=$subscription.SubscriptionId
        AZURE_TENANT_ID=$subscription.TenantId
    }

    $location = Read-Host "Enter Azure Location, hit enter for default (West Europe)"
    if([String]::IsNullOrWhiteSpace($location))
    {
        $location = "West Europe"
    }
    
    #Update the Azure Location in config
    & "$scriptDir\..\config\ReplaceStringInFile.ps1" $configFile $configFile @{AZURE_LOCATION=$location}
        
    ###########################################################
    # Refresh Run Configuration
    ###########################################################
    $config = & "$scriptDir\..\config\ReadConfig.ps1" $configFile
}

Write-SpecialLog "Current run configuration:" (Get-ScriptName) (Get-ScriptLineNumber)
$config.Keys | sort | % { if(-not ($_.Contains("PASSWORD") -or $_.Contains("KEY"))) { Write-SpecialLog ("Key = " + $_ + ", Value = " + $config[$_]) (Get-ScriptName) (Get-ScriptLineNumber) } }

Write-SpecialLog ("Using subscription: {0} - {1}" -f $config["AZURE_SUBSCRIPTION_NAME"], $config["AZURE_SUBSCRIPTION_ID"]) (Get-ScriptName) (Get-ScriptLineNumber)
Set-AzureRmContext -TenantId $config["AZURE_TENANT_ID"] -SubscriptionId $config["AZURE_SUBSCRIPTION_ID"]

###########################################################
# Check Azure Resource Creation List
###########################################################


$startTime = Get-Date

$docdb = $false
if($config["DOCUMENTDB"].Equals("true", [System.StringComparison]::OrdinalIgnoreCase))
{
    $docdb = $true
}

###########################################################
# Create Azure Resources
###########################################################

Write-SpecialLog "Step 0: Creating Azure Resource Group" (Get-ScriptName) (Get-ScriptLineNumber)
& "$scriptDir\CreateAzureResourceGroup.ps1" $config["AZURE_RESOURCE_GROUP"] $config["AZURE_LOCATION"]


if($docdb)
{
    Write-SpecialLog "Step 2.3: Creating DocumentDB and update account key in configurations.properties" (Get-ScriptName) (Get-ScriptLineNumber)
    $docdbKey = & "$scriptDir\DocumentDB\CreateDocumentDBARM.ps1" $config["AZURE_RESOURCE_GROUP"] $config["AZURE_LOCATION"] $config["DOCUMENTDB_ACCOUNT"]
    if(-not [String]::IsNullOrWhiteSpace($docdbKey))
    {
        & "$scriptDir\..\config\ReplaceStringInFile.ps1" $configFile $configFile @{DOCDB_KEY=$docdbKey}
    }
}


$finishTime = Get-Date
$totalSeconds = ($finishTime - $startTime).TotalSeconds
Write-InfoLog "Azure resources created, completed in $totalSeconds seconds." (Get-ScriptName) (Get-ScriptLineNumber)
