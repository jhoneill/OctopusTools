
function Get-OctopusWorkerPool              {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Members',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $WorkerPool,
        [Parameter(ParameterSetName='Members', Mandatory=$true)]
        [switch]$Workers
    )
    process {
        $item = Get-Octopus -Kind WorkerPool -Key $WorkerPool
        if      ($Workers) {$item.workers()}
        else               {$item}
    }
}

function Get-OctopusWorker                  {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',    Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Connection', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Worker,
        [Parameter(ParameterSetName='Connection', Mandatory=$true)]
        [switch]$Connection
    )
    process {
        $item = Get-Octopus -Kind Worker -key $Worker
         if     ($Connection) {$item.Connection()}
         else                 {$item}
    }
}

