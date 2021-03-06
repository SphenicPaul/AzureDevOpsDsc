<#
    .SYNOPSIS
        Creates a new Azure DevOps 'Project' with the specified properties set by the parameters.

    .PARAMETER ApiUri
        The URI of the Azure DevOps API to be connected to. For example:

          https://dev.azure.com/someOrganizationName/_apis/

    .PARAMETER Pat
        The 'Personal Access Token' (PAT) to be used by any subsequent requests/operations
        against the Azure DevOps API. This PAT must have the relevant permissions assigned
        for the subsequent operations being performed.

    .PARAMETER ProjectName
        The 'name' of the 'Project' being created.

    .PARAMETER ProjectDescription
        The 'description' of the 'Project' being created.

    .PARAMETER SourceControlType
        The 'sourceControlType' of the 'Project' being created.

        Options are 'Tfvc' or 'Git'. Defaults to 'Git' if no value provided.

    .PARAMETER Force
        When this switch is used, any confirmation will be overidden/ignored.

    .EXAMPLE
        New-AzDevOpsProject -ApiUri 'YourApiUriHere' -Pat 'YourPatHere' `
                            -ProjectName 'YourProjectNameHere' `
                            -ProjectDescription 'YourProjectDescriptionHere' -SourceControlType 'Git'

        Creates a 'Project' (assocated with the Organization/ApiUrl) in Azure DevOps using project-related, parameter values provided.
#>
function New-AzDevOpsProject
{
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    [OutputType([System.Object])]
    param
    (
        [Parameter(Mandatory = $true)]
        [ValidateScript( { Test-AzDevOpsApiUri -ApiUri $_ -IsValid })]
        [Alias('Uri')]
        [System.String]
        $ApiUri,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-AzDevOpsPat -Pat $_ -IsValid })]
        [Alias('PersonalAccessToken')]
        [System.String]
        $Pat,

        [Parameter(Mandatory = $true)]
        [ValidateScript({ Test-AzDevOpsProjectName -ProjectName $_ -IsValid })]
        [Alias('Name')]
        [System.String]
        $ProjectName,

        [Parameter()]
        [ValidateScript({ Test-AzDevOpsProjectDescription -ProjectDescription $_ -IsValid })]
        [AllowEmptyString()]
        [Alias('Description')]
        [System.String]
        $ProjectDescription = '',

        [Parameter()]
        [ValidateSet('Git','Tfvc')]
        [System.String]
        $SourceControlType = 'Git',

        [Parameter()]
        [System.Management.Automation.SwitchParameter]
        $Force
    )

    [string]$resourceJson = '
    {
      "id": "00000000-0000-0000-0000-000000000000",
      "name": "' + $ProjectName + '",
      "description": "' + $ProjectDescription + '",
      "capabilities": {
        "versioncontrol": {
          "sourceControlType": "' + $SourceControlType + '"
        },
        "processTemplate": {
          "templateTypeId": "6b724908-ef14-45cf-84f8-768b5384da45"
        }
      }
    }
'

    [System.Object]$newResource = $null
    $ResourceName = 'Project'

    if ($Force -or $PSCmdlet.ShouldProcess($ApiUri, $ResourceName))
    {
        New-AzDevOpsApiResource -ApiUri $ApiUri -Pat $Pat `
                                -ResourceName $ResourceName `
                                -Resource $($resourceJson | ConvertFrom-Json) `
                                -Force:$Force -Wait | Out-Null

        [System.Object]$newResource = Get-AzDevOpsProject -ApiUri $ApiUri -Pat $Pat `
                                                          -ProjectName $ProjectName
    }

    return $newResource
}
