Import-Module -Name (Join-Path -Path $PSScriptRoot -ChildPath '\..\..\Unit\Modules\TestHelpers\CommonTestHelper.psm1')

if (-not (Test-BuildCategory -Type 'Integration'))
{
    return
}

$script:dscModuleName = 'AzureDevOpsDsc'

$script:sqlServerDscModuleName = 'SqlServerDsc'
$script:sqlServerDscResourceFriendlyName = 'SqlSetup'
$script:sqlServerDscResourceName = 'DSC_' + $script:sqlServerDscResourceFriendlyName
$script:sqlMemoryDscResourceFriendlyName = 'SqlMemory'
$script:sqlMemoryDscResourceName = 'DSC_' + $script:sqlMemoryDscResourceFriendlyName

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

$script:testEnvironment = Initialize-TestEnvironment `
    -DSCModuleName $script:sqlServerDscModuleName `
    -DSCResourceName $script:sqlServerDscResourceName `
    -ResourceType 'Mof' `
    -TestType 'Integration'


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

try
{
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

    Describe "$($script:sqlServerDscResourceName)_Integration" {
        BeforeAll {
            $sqlSetupResourceId = "[$($script:sqlServerDscResourceFriendlyName)]SqlSetup_AzureDevOps"
            $sqlMemoryResourceId = "[$($script:sqlMemoryDscResourceFriendlyName)]SqlMemory_To2GB"
        }

        $configurationName = "$($script:sqlServerDscResourceName)_CreateDependencies_Config"

        Context ('When using configuration {0}' -f $configurationName) {
            It 'Should compile and apply the MOF without throwing' {
                {
                    $configurationParameters = @{
                        OutputPath                         = $TestDrive
                        # The variable $ConfigurationData was dot-sourced above.
                        ConfigurationData                  = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $true
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }
        }

        $configurationName = "$($script:sqlServerDscResourceName)_InstallDatabaseEngineNamedInstanceAsSystem_Config"

        Context ('When using configuration {0}' -f $configurationName) {
            It 'Should compile and apply the MOF without throwing' {
                {
                    $configurationParameters = @{
                        OutputPath                       = $TestDrive
                        # The variable $ConfigurationData was dot-sourced above.
                        ConfigurationData                = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $true
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            } -ErrorVariable itBlockError

            # Check if previous It-block failed. If so output the SQL Server setup log file.
            if ( $itBlockError.Count -ne 0 )
            {
                Show-SqlBootstrapLog
            }

            It 'Should be able to call Get-DscConfiguration without throwing' {
                {
                    $script:currentConfiguration = Get-DscConfiguration -Verbose -ErrorAction Stop
                } | Should -Not -Throw
            }

            It ('Should have set the "{0}" resource and all the parameters should match' -f $sqlSetupResourceId) {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                    -and $_.ResourceId -eq $sqlSetupResourceId
                }

                $resourceCurrentState.Action                     | Should -Be 'Install'
                $resourceCurrentState.AgtSvcAccount              | Should -BeNullOrEmpty
                $resourceCurrentState.AgtSvcAccountUsername      | Should -Be ('.\{0}' -f (Split-Path -Path $ConfigurationData.AllNodes.SqlAgentServicePrimaryAccountUserName -Leaf))
                $resourceCurrentState.AgtSvcStartupType          | Should -Be 'Manual'
                $resourceCurrentState.BrowserSvcStartupType      | Should -BeNullOrEmpty
                $resourceCurrentState.ErrorReporting             | Should -BeNullOrEmpty
                $resourceCurrentState.Features                   | Should -Be $ConfigurationData.AllNodes.DatabaseEngineNamedInstanceFeatures
                $resourceCurrentState.ForceReboot                | Should -BeNullOrEmpty
                $resourceCurrentState.FTSvcAccount               | Should -BeNullOrEmpty
                $resourceCurrentState.FTSvcAccountUsername       | Should -Be ('NT Service\MSSQLFDLauncher${0}' -f (Split-Path -Path $ConfigurationData.AllNodes.DatabaseEngineNamedInstanceName -Leaf))
                $resourceCurrentState.InstanceDir                | Should -Be $ConfigurationData.AllNodes.InstanceDir
                $resourceCurrentState.InstanceID                 | Should -Be $ConfigurationData.AllNodes.DatabaseEngineNamedInstanceName
                $resourceCurrentState.InstanceName               | Should -Be $ConfigurationData.AllNodes.DatabaseEngineNamedInstanceName
                $resourceCurrentState.SAPwd                      | Should -BeNullOrEmpty
                $resourceCurrentState.SecurityMode               | Should -Be 'SQL'
                $resourceCurrentState.SourcePath                 | Should -Be "$($ConfigurationData.AllNodes.DriveLetter):\"
                $resourceCurrentState.SQLCollation               | Should -Be $ConfigurationData.AllNodes.Collation
                $resourceCurrentState.SQLSvcAccount              | Should -BeNullOrEmpty
                $resourceCurrentState.SQLSvcAccountUsername      | Should -Be ('.\{0}' -f (Split-Path -Path $ConfigurationData.AllNodes.SqlServicePrimaryAccountUserName -Leaf))
                $resourceCurrentState.SqlSvcStartupType          | Should -Be 'Automatic'


                # Verify all the accounts are returned in the property SQLSysAdminAccounts.
                $ConfigurationData.AllNodes.SqlAdministratorAccountUserName | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                $ConfigurationData.AllNodes.SqlInstallAccountUserName | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                $ConfigurationData.AllNodes.AzureDevOpsServiceAccountUserName | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                'NT AUTHORITY\LOCAL SERVICE' | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                "NT SERVICE\MSSQL`$$($ConfigurationData.AllNodes.DatabaseEngineNamedInstanceName)" | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                "NT SERVICE\SQLAgent`$$($ConfigurationData.AllNodes.DatabaseEngineNamedInstanceName)" | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                'NT SERVICE\SQLWriter' | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                'NT SERVICE\Winmgmt' | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
                'sa' | Should -BeIn $resourceCurrentState.SQLSysAdminAccounts
            }

            It ('Should have set the "{0}" resource and all the parameters should match' -f $sqlMemoryResourceId) {
                $resourceCurrentState = $script:currentConfiguration | Where-Object -FilterScript {
                    $_.ConfigurationName -eq $configurationName `
                    -and $_.ResourceId -eq $sqlMemoryResourceId
                }

                $resourceCurrentState.MinMemory                  | Should -Be 1024
                $resourceCurrentState.MaxMemory                  | Should -Be 2048
            }

            It 'Should return $true when Test-DscConfiguration is run' {
                Test-DscConfiguration -Verbose | Should -Be 'True'
            }
        }

        $configurationName = "$($script:sqlServerDscResourceName)_StopServicesInstance_Config"

        Context ('When using configuration {0}' -f $configurationName) {
            It 'Should compile and apply the MOF without throwing' {
                {
                    $configurationParameters = @{
                        OutputPath        = $TestDrive
                        # The variable $ConfigurationData was dot-sourced above.
                        ConfigurationData = $ConfigurationData
                    }

                    & $configurationName @configurationParameters

                    $startDscConfigurationParameters = @{
                        Path         = $TestDrive
                        ComputerName = 'localhost'
                        Wait         = $true
                        Verbose      = $true
                        Force        = $true
                        ErrorAction  = 'Stop'
                    }

                    Start-DscConfiguration @startDscConfigurationParameters
                } | Should -Not -Throw
            }
        }
    }

}
finally
{
    Restore-TestEnvironment -TestEnvironment $script:testEnvironment
}
