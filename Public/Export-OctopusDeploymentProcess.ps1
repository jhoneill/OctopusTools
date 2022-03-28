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

    .PARAMETER StepFilter
        If specfied, filters steps of the deployment process by name, by zero based index or by a Where-object Style filter-Script.
        The filter may be an object with a name property, but may not be a multi-member array.

    .PARAMETER ActionsFilter
        If specified, filters actions within selected steps by name, by zero based index or by a Where-object Style filter-Script.
        The filter may be an object with a name property, but may not be a multi-member array.

    .PARAMETER Force
        By default the file will not be overwritten if it exists, specifying -Force ensures it will be.

    .EXAMPLE
        ps> Export-OctopusDeploymentProcess banana* -pt
        Exports the process from each project with a name starting "banana" to its own file in the current folder.
        The files will be named  deploymentprocess-Projects-XYZ.json  where XYX is the project ID number.

     .EXAMPLE
         ps> Export-OctopusDeploymentProcess -Project 'Pineapple' -step  {$_.name -match "^Deploy|https"}  -Action  "*https*" -Destination .\HttpsActions.json  -Force
         Exports the process from the Project names "Pineapple" filtering to only steps with names which contain "https" or start "Deploy..."
         And filtering the actions within the steps to only those like *https* (note the step filter is a where-stype scriptblock with a match operator
         and the action filter is a string with wild cards which is used for a Like operation ). The result is sent to a file which will be overwritten if it exists.
    #>
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(Position=1)]
        $Destination = $pwd,

        [Parameter(Position=2)]
        [Alias('Filter')]
        $StepFilter = "*",

        $ActionFilter = "*",

        [Alias('PT')]
        [switch]$PassThru,

        [switch]$Force
    )
    begin {
        function resolveFilter {
            param($f)
            if      ($f -is [scriptblock]) {return $f    }
            elseif  ($f -is [ValueType])   {return [scriptblock]::Create(  '$true')}   # back stop filter script returns true so everything is return
            elseif  ($f -is [string])      {return [scriptblock]::Create(('$_.name -like "{0}"' -f $f       )) }
            elseif  ($f.Name)              {return [scriptblock]::Create(('$_.name -like "{0}"' -f $f.Name )) }
            else    { throw  [System.Management.Automation.ValidationMetadataException]::new("The filter must be a string, a script block or an object with a name property.")}
        }
        $sf = resolveFilter $StepFilter
        $af = resolveFilter $ActionFilter
    }

    process {
        if ($Project.Name -and $Project.DeploymentProcess ) {
            $name       = $Project.Name
            $process    = $Project.DeploymentProcess()
        }
        else {
            $process    = Get-OctopusProject -Name $Project -DeploymentProcess
            if ($process.count -gt 1)  {
                $null = $PSBoundParameters.Remove('Project')
                $process.ProjectId | Export-OctopusDeploymentProcess @PSBoundParameters
                return
            }
            elseif ($process.ProjectName) {$name = $process.ProjectName}
            else                          {$name = $process.Id}
        }

        $Steps   = @()
        if      ($StepFilter -is [System.ValueType])     {
                $SourceSteps = $process.Steps[$StepFilter]
        }
        else    {$sourceSteps = $process.Steps.Where($sf) }
        foreach ($s in $SourceSteps   ) {
            $newstep         = $s.psobject.copy()
            $newstep.Id      = $null
            if ($ActionFilter -is [System.ValueType]) {
                    $newstep.Actions = @($s.Actions[$ActionFilter].psobject.Copy() )
            }
            else {  $newstep.Actions = @($s.Actions.where($af).ForEach({$_.psobject.copy()})) }
            foreach ($a in $newstep.Actions) {
                        $a.id       = $null
                        $a.packages = @($_.packages.foreach({$_.psobject.copy()}))
                        $a.packages.foreach({$_.id = $null  })
            }
            if (-not $newstep.Actions) {Write-Warning "All actions were removed from step $($newstep.Name)"}
            else                       {$steps += $newstep}
        }

        if     (-not $steps) {Write-Warning "All steps were excluded by the filter"; return}
        elseif (Test-Path $Destination -PathType Container )    {$DestPath = (Join-Path $Destination $name) + '.json' }
        elseif (Test-Path $Destination -IsValid -PathType Leaf) {$DestPath = $Destination}
        else   {Write-Warning "'$Destination' is not a valid destination" ;return}

        ConvertTo-Json $Steps -Depth 10 | Out-File $DestPath -NoClobber:(-not $Force)
        if     ($PassThru) {Get-Item $DestPath}
    }
}
