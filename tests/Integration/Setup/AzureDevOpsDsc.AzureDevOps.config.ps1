

# Get a spare drive letter
$mockLastDrive = ((Get-Volume).DriveLetter | Sort-Object | Select-Object -Last 1)
$mockIsoMediaDriveLetter = [char](([int][char]$mockLastDrive) + 1)


# Information relating to the SQL Server instance to be installed
$azureDevOpsServerVersionData = @{

    Version = '2020'
    IsoImageName = 'azuredevopsserver2020.iso'
    ExeName = 'azuredevopsserver2020.exe'

    # Additional variables required for ISO/EXE download
    SourceIsoDownloadUri = 'https://download.visualstudio.microsoft.com/download/pr/633b160b-5f28-43e3-a186-7651ccb43eb6/e755e76738b237090f94c07b390b40de/azuredevopsserver2020.iso'
    SourceExeDownloadUri = 'https://download.visualstudio.microsoft.com/download/pr/633b160b-5f28-43e3-a186-7651ccb43eb6/9d592d8a0932abffe608759738f805be/azuredevopsserver2020.exe'

    # Install
    InstallDirectoryPath = 'C:\AzureDevOpsServer'
    LogsDirectoryPath = 'C:\AzureDevOpsServer\Logs'

    # SQL Server information
    SqlInstance                             = '.\AZDEVOPS'
}


# Configuration information/data used within the SQL Server installation
$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName                                = 'localhost'

            # Properties for downloading media
            DownloadIsoPath                         = Join-Path -Path $env:TEMP -ChildPath $azureDevOpsServerVersionData.IsoImageName
            DownloadExePath                         = Join-Path -Path $env:TEMP -ChildPath $azureDevOpsServerVersionData.ExeName

            # Properties for mounting media
            ImagePath                               = Join-Path -Path $env:TEMP -ChildPath $azureDevOpsServerVersionData.IsoImageName
            DriveLetter                             = $mockIsoMediaDriveLetter

            # Properties
            InstallPath                             = $azureDevOpsServerVersionData.InstallDirectoryPath
            LogFilePath                             = Join-Path -Path $azureDevOpsServerVersionData.LogsDirectoryPath -ChildPath 'AzureDevOpsServer.Log.txt'

            # SQL Server information
            SqlInstance                             = $azureDevOpsServerVersionData.SqlInstance
        }
    )
}

<#
    .SYNOPSIS
        Setting up the dependencies to test installing SQL Server instances.
#>
Configuration DSC_SqlSetup_CreateDependencies_Config
{
    Import-DscResource -ModuleName 'PSDscResources' -ModuleVersion '2.12.0.0'
    Import-DscResource -ModuleName 'StorageDsc' -ModuleVersion '4.9.0.0'

    node $AllNodes.NodeName
    {
        MountImage 'MountIsoMedia'
        {
            ImagePath   = $Node.ImagePath
            DriveLetter = $Node.DriveLetter
            Ensure      = 'Present'
        }

        WaitForVolume WaitForMountOfIsoMedia
        {
            DriveLetter      = $Node.DriveLetter
            RetryIntervalSec = 5
            RetryCount       = 10
        }

    }
}
