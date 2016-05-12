$scriptPath = $MyInvocation.MyCommand.Path
$scriptDir = Split-Path $scriptPath

if(-not (Get-Command Write-ErrorLog -errorAction SilentlyContinue))
{
    Import-Module "$scriptDir\logging\Logging-DocumentDBScaleDemo.psm1" -Force
}