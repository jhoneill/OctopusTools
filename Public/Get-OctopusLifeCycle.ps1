function Get-OctopusLifeCycle               {
<#
    .SYNOPSIS
        Gets Lifecycles, and optionally the projects which use them

    .PARAMETER Lifecycle
        The lifecycle to fetch, by ID or Name. If none is specified all Lifecyles will be returned.

    .PARAMETER Projects
        If specified with the lifecycle returns the associated projects.
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Projects',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Lifecycle,

        [Parameter(ParameterSetName='Projects',          Mandatory=$true)]
        [switch]$Projects
    )
    process {
        $item = Get-Octopus -Kind lifecycle -key $Lifecycle
        if     (-not $item) {return}
        elseif ($Projects)  {$item.Projects() }
        else    {
            foreach ($p in $item.phases ) {
                $p.pstypenames.Add('OctopusLifecyclePhase')
            }
            $item
        }
    }
}