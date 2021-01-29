

# Get a spare drive letter
$mockLastDrive = ((Get-Volume).DriveLetter | Sort-Object | Select-Object -Last 1)
$mockIsoMediaDriveLetter = [char](([int][char]$mockLastDrive) + 1)


# Information relating to the SQL Server instance to be installed
$sqlServerVersionData = @{

    Version = '150'
    IsoImageName = 'SQL2019.iso'

    # Additional variables required as ISO is downloaded via additional EXE
    SourceDownloadExeUri = 'https://download.microsoft.com/download/d/a/2/da259851-b941-459d-989c-54a18a5d44dd/SQL2019-SSEI-Dev.exe'

    DownloadExeName = 'SQL2019-SSEI-Dev.exe'
    DownloadIsoName = 'SQLServer2019-x64-ENU-Dev.iso'
}


# Configuration information/data used within the SQL Server installation
$ConfigurationData = @{
    AllNodes = @(
        @{
            NodeName                                = 'localhost'

            SqlServerInstanceIdPrefix               = 'MSSQL'
            #AnalysisServiceInstanceIdPrefix         = 'MSAS'

            # Database Engine properties.
            DatabaseEngineNamedInstanceName         = 'AZDEVOPS'
            DatabaseEngineNamedInstanceFeatures     = 'SQLENGINE,FULLTEXT'           # ',REPLICATION,AS,CONN,BC,SDK'
            #AnalysisServicesMultiServerMode         = 'MULTIDIMENSIONAL'
            DatabaseEngineDefaultInstanceName       = 'MSSQLSERVER'
            DatabaseEngineDefaultInstanceFeatures   = 'SQLENGINE,FULLTEXT'           # ',REPLICATION,CONN,BC,SDK'

            # General SqlSetup properties
            Collation                               = 'Latin1_General_CI_AS'
            InstanceDir                             = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedDir                        = 'C:\Program Files\Microsoft SQL Server'
            InstallSharedWOWDir                     = 'C:\Program Files (x86)\Microsoft SQL Server'
            InstallSQLDataDir                       = "C:\Db\$($sqlServerVersionData.Version)\System"
            SQLUserDBDir                            = "C:\Db\$($sqlServerVersionData.Version)\Data\"
            SQLUserDBLogDir                         = "C:\Db\$($sqlServerVersionData.Version)\Log\"
            SQLBackupDir                            = "C:\Db\$($sqlServerVersionData.Version)\Backup"
            UpdateEnabled                           = 'False'
            SuppressReboot                          = $true # Make sure we don't reboot during testing.
            ForceReboot                             = $false

            # Properties for downloading media
            DownloadExePath                         = Join-Path -Path $env:TEMP -ChildPath $sqlServerVersionData.DownloadExeName
            DownloadIsoPath                         = Join-Path -Path $env:TEMP -ChildPath $sqlServerVersionData.DownloadIsoName

            # Properties for mounting media
            ImagePath                               = Join-Path -Path $env:TEMP -ChildPath $sqlServerVersionData.IsoImageName
            DriveLetter                             = $mockIsoMediaDriveLetter

            # Parameters to configure TempDb
            SqlTempDbFileCount                      = '2'
            SqlTempDbFileSize                       = '128'
            SqlTempDbFileGrowth                     = '128'
            SqlTempDbLogFileSize                    = '128'
            SqlTempDbLogFileGrowth                  = '128'

            SqlInstallAccountUserName               = "$env:COMPUTERNAME\SqlInstall"
            SqlInstallAccountPassword               = 'P@ssw0rd1'
            SqlAdministratorAccountUserName         = "$env:COMPUTERNAME\SqlAdmin"
            SqlAdministratorAccountPassword         = 'P@ssw0rd1'
            SqlServicePrimaryAccountUserName        = "$env:COMPUTERNAME\svc-SqlPrimary"
            SqlServicePrimaryAccountPassword        = 'yig-C^Equ3'
            SqlAgentServicePrimaryAccountUserName   = "$env:COMPUTERNAME\svc-SqlAgentPri"
            SqlAgentServicePrimaryAccountPassword   = 'yig-C^Equ3'
            #SqlServiceSecondaryAccountUserName      = "$env:COMPUTERNAME\svc-SqlSecondary"
            #SqlServiceSecondaryAccountPassword      = 'yig-C^Equ3'
            #SqlAgentServiceSecondaryAccountUserName = "$env:COMPUTERNAME\svc-SqlAgentSec"
            #SqlAgentServiceSecondaryAccountPassword = 'yig-C^Equ3'

            #CertificateFile                         = $env:DscPublicCertificatePath
        }
    )
}


<#
    Creating all the credential objects to save some repeating code.
#>

$SqlInstallCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList @($ConfigurationData.AllNodes.SqlInstallAccountUserName,
        (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlInstallAccountPassword -AsPlainText -Force))

$SqlAdministratorCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList @($ConfigurationData.AllNodes.SqlAdministratorAccountUserName,
        (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlAdministratorAccountPassword -AsPlainText -Force))

$SqlServicePrimaryCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList @($ConfigurationData.AllNodes.SqlServicePrimaryAccountUserName,
        (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlServicePrimaryAccountPassword -AsPlainText -Force))

$SqlAgentServicePrimaryCredential = New-Object `
    -TypeName System.Management.Automation.PSCredential `
    -ArgumentList @($ConfigurationData.AllNodes.SqlAgentServicePrimaryAccountUserName,
        (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlAgentServicePrimaryAccountPassword -AsPlainText -Force))

# $SqlServiceSecondaryCredential = New-Object `
#     -TypeName System.Management.Automation.PSCredential `
#     -ArgumentList @(
#         $ConfigurationData.AllNodes.SqlServiceSecondaryAccountUserName,
#                 (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlServiceSecondaryAccountPassword -AsPlainText -Force))

# $SqlAgentServiceSecondaryCredential = New-Object `
#     -TypeName System.Management.Automation.PSCredential `
#     -ArgumentList @($ConfigurationData.AllNodes.SqlAgentServiceSecondaryAccountUserName,
#         (ConvertTo-SecureString -String $ConfigurationData.AllNodes.SqlAgentServiceSecondaryAccountPassword -AsPlainText -Force))


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

        User 'CreateSqlServicePrimaryAccount'
        {
            Ensure   = 'Present'
            UserName = Split-Path -Path $SqlServicePrimaryCredential.UserName -Leaf
            Password = $SqlServicePrimaryCredential
        }

        User 'CreateSqlAgentServicePrimaryAccount'
        {
            Ensure   = 'Present'
            UserName = Split-Path -Path $SqlAgentServicePrimaryCredential.UserName -Leaf
            Password = $SqlAgentServicePrimaryCredential
        }

        # User 'CreateSqlServiceSecondaryAccount'
        # {
        #     Ensure   = 'Present'
        #     UserName = Split-Path -Path $SqlServiceSecondaryCredential.UserName -Leaf
        #     Password = $SqlServicePrimaryCredential
        # }

        # User 'CreateSqlAgentServiceSecondaryAccount'
        # {
        #     Ensure   = 'Present'
        #     UserName = Split-Path -Path $SqlAgentServiceSecondaryCredential.UserName -Leaf
        #     Password = $SqlAgentServicePrimaryCredential
        # }

        User 'CreateSqlInstallAccount'
        {
            Ensure   = 'Present'
            UserName = Split-Path -Path $SqlInstallCredential.UserName -Leaf
            Password = $SqlInstallCredential
        }

        Group 'AddSqlInstallAsAdministrator'
        {
            Ensure           = 'Present'
            GroupName        = 'Administrators'
            MembersToInclude = Split-Path -Path $SqlInstallCredential.UserName -Leaf
        }

        User 'CreateSqlAdminAccount'
        {
            Ensure   = 'Present'
            UserName = Split-Path -Path $SqlAdministratorCredential.UserName -Leaf
            Password = $SqlAdministratorCredential
        }

        WindowsFeature 'NetFramework45'
        {
            Name   = 'NET-Framework-45-Core'
            Ensure = 'Present'
        }
    }
}
