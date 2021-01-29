Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '\..\..\Unit\Modules\TestHelpers\CommonTestHelper.psm1')

if (-not (Test-BuildCategory -Type 'Integration'))
{
    return
}

$script:dscModuleName = 'AzureDevOpsDsc'

$script:azureDevOpsDscCommonModulePath = Join-Path -Path $PSScriptRoot -ChildPath '..\..\..\Source\Modules\AzureDevOpsDsc.Common'
Import-Module -Name $script:azureDevOpsDscCommonModulePath

try
{
    Import-Module -Name DscResource.Test -Force -ErrorAction 'Stop'
}
catch [System.IO.FileNotFoundException]
{
    throw 'DscResource.Test module dependency not found. Please run ".\build.ps1 -Tasks build" first.'
}


# Dot-source configuration to be used in subsquent tests/executions
$configFile = Join-Path -Path $PSScriptRoot -ChildPath "AzureDevOpsDsc.AzureDevOps.config.ps1"
. $configFile


# By switching to 'SilentlyContinue' should theoretically increase the download speed.
$previousProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'


# Download Azure DevOps Server media
if (-not (Test-Path -Path $ConfigurationData.AllNodes.ImagePath))
{
    # Download the EXE used to download the ISO
    Write-Verbose -Message "Start downloading the Azure DevOps Server media at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')..." -Verbose
    Invoke-WebRequest -Uri $azureDevOpsServerVersionData.SourceDownloadUri -OutFile $ConfigurationData.AllNodes.DownloadIsoPath | Out-Null
    Write-Verbose -Message ('Azure DevOps Server media file has SHA1 hash ''{0}''.' -f (Get-FileHash -Path $ConfigurationData.AllNodes.ImagePath -Algorithm 'SHA1').Hash) -Verbose

    # Return to previous 'ProgressPreference' value
    $ProgressPreference = $previousProgressPreference

    # Double check that the Azure DevOps Server media was downloaded.
    if (-not (Test-Path -Path $ConfigurationData.AllNodes.ImagePath))
    {
        Write-Warning -Message ('Azure DevOps Server media could not be downloaded, can not run the integration test.')
        return
    }
    else
    {
        Write-Verbose -Message "Finished downloading the Azure DevOps Server media iso at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')." -Verbose
    }
}
else
{
    Write-Verbose -Message 'Azure DevOps Server media is already present/downloaded.' -Verbose
}
