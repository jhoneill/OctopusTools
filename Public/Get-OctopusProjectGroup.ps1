function Get-OctopusProjectGroup            {
<#
    .SYNOPSIS
        Gets project groups, and optionally their member projects

    .PARAMETER ProjectGroup
        One or more ProjectGroups to get by name or ID. Accepts input from the pipeline' if the object has an ID or Project group ID the associated project group will be returned

    .PARAMETER Projects
        Expands the projects in the group

    .EXAMPLE
        C:> Get-OctopusProjectGroup
        Returns a list of all the project groups

    .EXAMPLE
        C:> $myProj  | Get-OctopusProjectGroup
        Pipes an object into Get-OctopusProjectGroup; because this is a project object with a ProjectGroupID property the command is able to find the project group

    .EXAMPLE
        C> gpg Obsolete -x
        Uses the short alias GPG for *G*et-Octopus*P*roject*G*roup and x * for E*x*pandProjects to return a list of projects in the "obsolete" group

.NOTES
General notes
#>
    [alias('gpg')]
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Projects', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $ProjectGroup,

        [Parameter(ParameterSetName='Projects', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [Alias('x','ExpandProjects')]
        [switch]$Projects
    )
    process {
        $item = Get-Octopus -Kind ProjectGroup -key $ProjectGroup -ExtraId ProjectGroupId
        if     ($Projects)  {$item.Projects()}
        else   {$item}
    }
}

