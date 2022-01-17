function Export-OctopusDeploymentProcess    {
    <#
    .SYNOPSIS
        Exports one or more custom action-templates

    .PARAMETER Project
        One or project either passed as an object or a name or project ID. Accepts input from the pipeline

    .PARAMETER Destination
        The file name or directory to use to create the JSON file. If a directory is given the file name will be "tempaltename.Json". If nothing is specified the files will be output to the current directory.

    .PARAMETER PassThru
        If specified the newly created files will be returned.

    .PARAMETER Force
        By default the file will not be overwritten if it exists, specifying -Force ensures it will be.

    .EXAMPLE
        C:> Export-OctopusDeploymentProcess banana* -pt
        Exports the process from each project with a name starting "banana" to its own file in the current folder.
        The files will be named  deploymentprocess-Projects-XYZ.json  where XYX is the project ID number.
    #>
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $Project,

        [Parameter(Position=1)]
        $Destination = $pwd,

        [Parameter(Position=2)]
        [ValidateCount(0,1)]
        [Alias('Name','Index')]
        [object[]]$Filter,

        [Alias('PT')]
        [switch]$PassThru,

        [switch]$Force
    )

    process {
        if ($Project.Name -and $Project.DeploymentProcess ) {
            $name       = $Project.Name
            $process    = $Project.DeploymentProcess()
        }
        else {
            $process    = Get-OctopusProject -Name $Project -DeploymentProcess
            if ($process.count -gt 1)  {
                $process.ProjectId | Export-OctopusDeploymentProcess -Destination $Destination -PassThru:$PassThru -Force:$Force
                return
            }
            elseif ($process.ProjectName) {$name = $process.ProjectName}
            else {$name = $process.Id}
        }
        $Steps   = @()
        foreach ($SourceStep in $process.Steps) {
            $newstep        = $SourceStep.psobject.copy()
            $newstep.Id     = $null
            $newstep.Actions = @($SourceStep.Actions.ForEach({$_.psobject.copy()}))
            foreach ($a in $newstep.Actions) {
                        $a.id       = $null
                        $a.packages = @($_.packages.foreach({$_.psobject.copy()}))
                        $a.packages.foreach({$_.id = $null  })
            }
            $steps += $newstep
        }
        foreach ($f in $Filter) {
            if      ($f.Name)         {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f.Name )) }
            elseif  ($f -is [string]) {$f = [scriptblock]::Create(('$_.name -like "{0}"' -f $f      )) }

            if      ($f -is [System.ValueType])     {$Steps = $Steps[$f]}
            else    {$steps = $steps | Where-Object $f}
            if     (-not $steps) {Write-Warning "All steps were excluded by the filter";return}
        }
        if     (Test-Path $Destination -PathType Container )    {$DestPath = (Join-Path $Destination $name) + '.json' }
        elseif (Test-Path $Destination -IsValid -PathType Leaf) {$DestPath = $Destination}
        else   {Write-Warning "Invalid destination" ;return}
        ConvertTo-Json $Steps -Depth 10 | Out-File $DestPath -NoClobber:(-not $Force)
        if     ($PassThru) {Get-Item $DestPath}
    }
}
# to do . Import ! You don't know if the export is good or bad until you import. morning Mr Schrodinger