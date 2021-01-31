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


<#
    .SYNOPSIS
        This function will output the Azure DevOps log files.
    .DESCRIPTION
        This function will output the Azure DevOps log files, this is to be
        able to debug any problems that potentially occurred during setup.
#>
function Show-AzureDevOpsLog
{
    [CmdletBinding()]
    param
    (
        [Parameter(Mandatory=$true)]
        [System.String]
        $Path
    )

    $summaryLogPath = Get-ChildItem -Path $Path |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    $summaryLog = Get-Content $summaryLogPath

    Write-Verbose -Message $('-' * 80) -Verbose
    Write-Verbose -Message $(Split-Path -Path $summaryLogPath -Leaf) -Verbose
    Write-Verbose -Message $('-' * 80) -Verbose

    $summaryLog | ForEach-Object -Process {
        Write-Verbose $_ -Verbose
    }

    Write-Verbose -Message $('-' * 80) -Verbose
}


# Dot-source configuration to be used in subsquent tests/executions
$configFile = Join-Path -Path $PSScriptRoot -ChildPath "AzureDevOpsDsc.AzureDevOps.config.ps1"
. $configFile


# By switching to 'SilentlyContinue' should theoretically increase the download speed.
$previousProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'


# Download Azure DevOps Server media (ISO)
if (-not (Test-Path -Path $ConfigurationData.AllNodes.ImagePath))
{
    # Download the ISO
    Write-Verbose -Message "Start downloading the Azure DevOps Server media (ISO) at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')..." -Verbose
    Invoke-WebRequest -Uri $azureDevOpsServerVersionData.SourceIsoDownloadUri -OutFile $ConfigurationData.AllNodes.DownloadIsoPath | Out-Null
    Write-Verbose -Message ('Azure DevOps Server media (ISO) file has SHA1 hash ''{0}''.' -f (Get-FileHash -Path $ConfigurationData.AllNodes.ImagePath -Algorithm 'SHA1').Hash) -Verbose

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
        Write-Verbose -Message "Finished downloading the Azure DevOps Server media (ISO) at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')." -Verbose
    }
}
else
{
    Write-Verbose -Message 'Azure DevOps Server media (ISO) is already present/downloaded.' -Verbose
}


# Download Azure DevOps Server media (EXE)
if (-not (Test-Path -Path $ConfigurationData.AllNodes.DownloadExePath))
{
    # Download the EXE
    Write-Verbose -Message "Start downloading the Azure DevOps Server media (EXE) at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')..." -Verbose
    Invoke-WebRequest -Uri $azureDevOpsServerVersionData.SourceExeDownloadUri -OutFile $ConfigurationData.AllNodes.DownloadExePath | Out-Null
    Write-Verbose -Message ('Azure DevOps Server media (EXE) file has SHA1 hash ''{0}''.' -f (Get-FileHash -Path $ConfigurationData.AllNodes.DownloadExePath -Algorithm 'SHA1').Hash) -Verbose

    # Return to previous 'ProgressPreference' value
    $ProgressPreference = $previousProgressPreference

    # Double check that the Azure DevOps Server media was downloaded.
    if (-not (Test-Path -Path $ConfigurationData.AllNodes.DownloadExePath))
    {
        Write-Warning -Message ('Azure DevOps Server media (EXE) could not be downloaded, can not run the integration test.')
        return
    }
    else
    {
        Write-Verbose -Message "Finished downloading the Azure DevOps Server media (EXE) at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')." -Verbose
    }
}
else
{
    Write-Verbose -Message 'Azure DevOps Server media (EXE) is already present/downloaded.' -Verbose
}


# Install Azure DevOps Server using the EXE
Write-Verbose -Message 'Installing Azure DevOps Server...' -Verbose
$downloadExeArgumentList = '/CustomInstallPath {0} /Full /NoRefresh /NoRestart /Passive /ProductKey TRIAL /Silent /Log {1}' -f $ConfigurationData.AllNodes.InstallPath, $ConfigurationData.AllNodes.LogFilePath
Start-Process -FilePath $ConfigurationData.AllNodes.DownloadExePath `
              -ArgumentList $downloadExeArgumentList `
              -Wait -Verbose
Write-Verbose -Message 'Successfully installed Azure DevOps Server.' -Verbose

Write-Verbose -Message 'Outputting Azure DevOps Server, installation logs...' -Verbose
Show-AzureDevOpsLog -Path $($azureDevOpsServerVersionData.LogsDirectoryPath + '\*.txt')


# Configure Azure DevOps Server using TFSCONFIG
$tfsConfigExePath = Join-Path -Path $(Join-Path -Path $ConfigurationData.AllNodes.InstallPath -ChildPath 'Tools') -ChildPath 'tfsconfig.exe'
$tfsConfigFilePath = Join-Path -Path $PSScriptRoot -ChildPath 'AzureDevOpsDsc.AzureDevOps.config.ini'

Write-Verbose -Message 'Verifying Azure DevOps Server configuration...' -Verbose

$tfsConfigExeArgumentList = 'unattend /configure /unattendfile:{0} /verify' -f $tfsConfigFilePath
Start-Process -FilePath $tfsConfigExePath `
              -ArgumentList $tfsConfigExeArgumentList `
              -Wait -Verbose
Write-Verbose -Message 'Successfully verified Azure DevOps Server configuration.' -Verbose

Write-Verbose -Message 'Configuring Azure DevOps Server...' -Verbose
$tfsConfigExeArgumentList = 'unattend /configure /unattendfile:{0}' -f $tfsConfigFilePath
Start-Process -FilePath $tfsConfigExePath `
              -ArgumentList $tfsConfigExeArgumentList `
              -Wait -Verbose
Write-Verbose -Message 'Successfully configured Azure DevOps Server.' -Verbose

Write-Verbose -Message 'Outputting Azure DevOps Server, configuration logs...' -Verbose
Show-AzureDevOpsLog -Path 'C:\ProgramData\Microsoft\Azure DevOps\Server Configuration\Logs\*.log'
