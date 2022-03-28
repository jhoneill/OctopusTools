function Get-OctopusLifeCycle               {
<#
    .SYNOPSIS
        Gets Lifecycles, and optionally the projects which use them

    .PARAMETER Lifecycle
        The lifecycle to fetch, by ID or Name. If none is specified all Lifecyles will be returned.

    .PARAMETER Projects
        If specified with the lifecycle, returns the projects associated with it.

    .PARAMETER Environments
        If specified with the lifecycle, returns the environments it refers to.

    .EXAMPLE
        ps > Get-OctopusLifeCycle 'Default Lifecycle' -Projects

        Gets a list of projects which use the default LifeCycle

    .EXAMPLE
        ps > Get-OctopusProject Banana | Get-OctopusLifeCycle -Environments | Get-OctopusEnvironment

        Gets the default lifecycle associated with a project  and returns the IDs of its environments.
        These are then piped into Get-OctopusEnvironment to return the environment details.

#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Projects',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Environments',      Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Lifecycle,

        [Parameter(ParameterSetName='Projects',          Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [switch]$Projects ,

        [Parameter(ParameterSetName='Environments',      Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [switch]$Environments

    )
    process {
        if     ($Lifecycle.LifecycleId) {$Lifecycle = $Lifecycle.LifecycleId}
        elseif ($Lifecycle.id) {$Lifecycle = $Lifecycle.Id}
        $item = Get-Octopus -Kind lifecycle -key $Lifecycle
        if     (-not $item)    {return}
        elseif ($Projects)     {$item.Projects() }
        elseif ($Environments) {$item.Environments()}
        else    {
            foreach ($p in $item.phases ) {
                $p.pstypenames.Add('OctopusLifecyclePhase')
            }
            $item
        }
    }
}
