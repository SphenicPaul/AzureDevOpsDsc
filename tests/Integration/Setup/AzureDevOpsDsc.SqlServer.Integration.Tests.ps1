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
        This function will output the Setup Bootstrap Summary.txt log file.
    .DESCRIPTION
        This function will output the Summary.txt log file, this is to be
        able to debug any problems that potentially occurred during setup.
        This will pick up the newest Summary.txt log file, so any
        other log files will be ignored (AppVeyor build worker has
        SQL Server instances installed by default).
        This code is meant to work regardless what SQL Server
        major version is used for the integration test.
#>
function Show-SqlBootstrapLog
{
    [CmdletBinding()]
    param
    (
    )

    $summaryLogPath = Get-ChildItem -Path 'C:\Program Files\Microsoft SQL Server\**\Setup Bootstrap\Log\Summary.txt' |
        Sort-Object -Property LastWriteTime -Descending |
        Select-Object -First 1

    $summaryLog = Get-Content $summaryLogPath

    Write-Verbose -Message $('-' * 80) -Verbose
    Write-Verbose -Message 'Summary.txt' -Verbose
    Write-Verbose -Message $('-' * 80) -Verbose

    $summaryLog | ForEach-Object -Process {
        Write-Verbose $_ -Verbose
    }

    Write-Verbose -Message $('-' * 80) -Verbose
}


# Dot-source configuration to be used in subsquent tests/executions
$configFile = Join-Path -Path $PSScriptRoot -ChildPath "AzureDevOpsDsc.SqlServer.config.ps1"
. $configFile


# By switching to 'SilentlyContinue' should theoretically increase the download speed.
$previousProgressPreference = $ProgressPreference
$ProgressPreference = 'SilentlyContinue'


# Download SQL Server media
if (-not (Test-Path -Path $ConfigurationData.AllNodes.ImagePath))
{
    # Download the EXE used to download the ISO
    Write-Verbose -Message "Start downloading the SQL Server media at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')..." -Verbose
    Invoke-WebRequest -Uri $sqlServerVersionData.SourceDownloadExeUri -OutFile $ConfigurationData.AllNodes.DownloadExePath | Out-Null

    # Download ISO using the EXE
    $imageDirectoryPath = Split-Path -Path $ConfigurationData.AllNodes.ImagePath -Parent
    $downloadExeArgumentList = '/ENU /Quiet /HideProgressBar /Action=Download /Language=en-US /MediaType=ISO /MediaPath={0}' -f $imageDirectoryPath
    Start-Process -FilePath $ConfigurationData.AllNodes.DownloadExePath `
                -ArgumentList $downloadExeArgumentList `
                -Wait

    # Rename the ISO and generate SHA1 hash
    Rename-Item -Path $ConfigurationData.AllNodes.DownloadIsoPath `
                -NewName $(Split-Path -Path $ConfigurationData.AllNodes.ImagePath -Leaf) | Out-Null
    Write-Verbose -Message ('SQL Server media file has SHA1 hash ''{0}''.' -f (Get-FileHash -Path $ConfigurationData.AllNodes.ImagePath -Algorithm 'SHA1').Hash) -Verbose

    # Return to previous 'ProgressPreference' value
    $ProgressPreference = $previousProgressPreference

    # Double check that the SQL media was downloaded.
    if (-not (Test-Path -Path $ConfigurationData.AllNodes.ImagePath))
    {
        Write-Warning -Message ('SQL media could not be downloaded, can not run the integration test.')
        return
    }
    else
    {
        Write-Verbose -Message "Finished downloading the SQL Server media iso at $(Get-Date -Format 'yyyy-MM-dd hh:mm:ss')." -Verbose
    }
}
else
{
    Write-Verbose -Message 'SQL Server media is already present/downloaded.' -Verbose
}
