function New-OctopusProjectGroup            {
<#
.SYNOPSIS
    Creates a project group

.PARAMETER Name
    Name for the group

.PARAMETER Description
    Description of the group

.PARAMETER Force
    Supresses any confirmation prompts. These will only appear if the confirmPreference variable has been changed
#>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        [alias('ProjectGroupName')]
        $Name,
        [alias('ProjectGroupDescription')]
        $Description,

        [switch]$Force
    )
    process {
        if ($Name.count -gt 1) {
            $Name | New-OctopusProjectGroup -Description $d -Force:$Force
            return
        }

        $projectGroupdef = @{
            Id                = $null
            Name              = $Name
            EnvironmentIds    = @()
            Links             = $null
            RetentionPolicyId = $null
            Description       = $Description
        }
        if ($Force -or $pscmdlet.ShouldProcess($Name,"Add Project group")) {
            Invoke-OctopusMethod -Method Post -EndPoint projectgroups -Item $projectGroupdef -PSType OctopusProjectGroup
        }
    }
}
