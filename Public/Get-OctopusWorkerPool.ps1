function Get-OctopusWorkerPool              {
    <#
      .SYNOPSIS
        Gets information about Worker-pools or the members of a pool

      .PARAMETER WorkerPool
        The name or ID of a pool or the an object representing a pool

     .PARAMETER Workers
        If specified returs the workers in the specified pool

    .EXAMPLE
        $ps > Get-OctopusWorkerPool -WorkerPool 'Default Worker Pool'

        Returns the WorkerPool object representing the named pool.

        $ps > Get-OctopusWorkerPool -WorkerPool 'Default Worker Pool', 'Testing Worker Pool' -Workers

        Returns the Worker nodes in each of the named pools.
    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Members',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $WorkerPool,
        [Parameter(ParameterSetName='Members', Mandatory=$true, ValueFromPipelineByPropertyName=$true)]
        [switch]$Workers
    )
    process {
        $item = Get-Octopus -Kind WorkerPool -Key $WorkerPool
        if     (-not $item) {return}
        elseif ($Workers)   {$item.workers()}
        else                {$item}
    }
}
