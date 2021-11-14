function Get-OctopusProject                 {
    <#
    # ExampleFodder
    Get-OctopusProject 'Random Quotes' -Releases | ogv -PassThru | foreach {$_.delete()}
    Get-OctopusProject 'Random Quotes' -DeploymentProcess | % steps | % actions | % properties
    (OctopusProject here*).releases().where({$_.version -like '*20'}).Deployments()[0].task().raw()
    Invoke-OctopusMethod "projects/Projects-21/deploymentprocesses"                        | select -expand steps  |select -expand actions | select -expand properties
    #                    Invoke-OctopusMethod "projects/Projects-21/runbookProcesses/RunbookProcess-Runbooks-1" | select -expand steps  |select -expand actions | select -expand properties
    #                         "/projects/$($project.Id)/releases" -expand   ; Invoke-RestMethod -Method Delete -Uri "/releases/$($release.Id)" -Headers $header
    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    [Alias('gop')]
    param   (
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Channels',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='DeploymentSettings',Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='ReleaseVersion',    Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Runbooks',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Triggers',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Variables',         Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(ParameterSetName='Channels', Mandatory=$true)]
        [switch]$Channels,

        [Parameter(ParameterSetName='DeploymentProcess', Mandatory=$true)]
        [switch]$DeploymentProcess,

        [Parameter(ParameterSetName='DeploymentSettings',Mandatory=$true)]
        [switch]$DeploymentSettings,

        [Parameter(ParameterSetName='AllReleases',       Mandatory=$true)]
        [Alias('AllReleases')]
        [switch]$Releases,

        [Parameter(ParameterSetName='ReleaseVersion',    Mandatory=$true)]
        $ReleaseVersion,

        [Parameter(ParameterSetName='Runbooks',          Mandatory=$true)]
        [switch]$Runbooks,

        [Parameter(ParameterSetName='Triggers',          Mandatory=$true)]
        [switch]$Triggers,

        [Parameter(ParameterSetName='Variables',         Mandatory=$true)]
        [switch]$Variables
    )
    process {
        $item = Get-Octopus -Kind Project -Key $Project -ExtraId ProjectID | Sort-Object -Property ProjectGroupName,Name
        #xxxx todo Some types still to add for these methods in the types.ps1mxl file
        if      ($PSCmdlet.ParameterSetName -eq 'Default') {$item}
        elseif  ($Channels)           {$item.Channels()}
        elseif  ($DeploymentProcess)  {$item.DeploymentProcess()}
        elseif  ($DeploymentSettings) {$item.DeploymentSettings()}
        elseif  ($Runbooks)           {$item.Runbooks()}
        elseif  ($Triggers)           {$item.Triggers()}
        elseif  ($Variables)          {$item.Variables()}
        elseif  ($ReleaseVersion)     {$item.Releases()   | Where-Object {$_.version -like $ReleaseVersion} }
        else                          {$item.Releases() }
    }
}

function New-OctopusProject                 {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param (
        [parameter(Mandatory=$true, position=0,ValueFromPipeline=$true)]
        $Name,

        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [string]$Description,

        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $ProjectGroup,

        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $LifeCycle
    )
    <# xxxx todo  Look at adding these properties
        IncludedLibraryVariableSetIds
        DiscreteChannelRelease
        DefaultToSkipIfAlreadyInstalled
        TenantedDeploymentMode
        DefaultGuidedFailureMode
        VersioningStrategy
        ReleaseCreationStrategy
        Templates
        AutoDeployReleaseOverrides
        IsDisabled
        AutoCreateRelease
        ProjectConnectivityPolicy
    #>
    process {
        if     (-not $ProjectGroup)    {$ProjectGroup = Get-OctopusProjectGroup | Select-Object -First 1 -ExpandProperty Id}
        elseif      ($ProjectGroup.id) {$ProjectGroup = $ProjectGroup}
        elseif      ($ProjectGroup -notmatch '^ProjectGroups-\d+$') {
                    $ProjectGroup = (Get-OctopusProjectGroup $ProjectGroup).id
                    if (-not $ProjectGroup) {throw 'Could not resolve the project group provided'}
        }
        if     (-not $LifeCycle)       {$LifeCycle = Get-OctopusLifeCycle| Select-Object -First 1 -ExpandProperty Id}
        elseif      ($LifeCycle.id)    {$LifeCycle = $LifeCycle.id}
        elseif      ($LifeCycle -notmatch '^Lifecycles-\d+$') {
                     $LifeCycle = (Get-OctopusLifeCycle $LifeCycle).id
                     if (-not $LifeCycle) {throw 'Could not resolve the lifecycle provided'}
        }
        $ProjectDefinition  = @{
            Name            = $Name
            Description     = $Description
            ProjectGroupId  = $ProjectGroup
            LifeCycleId     = $LifeCycle
        }
        if ($Force -or $pscmdlet.ShouldProcess($Name,'Create new project')) {
            Invoke-OctopusMethod -PSType OctopusProject -EndPoint 'Projects' -Method Post -Item $ProjectDefinition
        }
    }
}

function Add-OctopusProjectDeploymentStep   {
<#
 $p         = Get-OctopusProject -Name "Test Project 77"
$newport    = "1001"
$newservice = "portal"
$p.DeploymentProcess().steps[0] | Add-OctopusProjectDeploymentStep  'Test Project 77' -NewStepName "Add $newService"  -UpdateScript {
            $NewStep.Actions[0].Name = $NewStep.Name; $NewStep.Actions[0].Properties.Port = $newport; $NewStep.Actions[0].Properties.ServiceName =  $newservice
}
#>
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,
        [Parameter(Mandatory=$true,Position=1)]
        [string]$NewStepName,

        [Parameter(ValueFromPipeline=$true,Mandatory=$true,Position=3)]
        $SourceStep,

        [Parameter(Position=4)] # Mandatory=$true,
        $UpdateScript
    )
    process {
        $process             = Get-OctopusProject -Name $Project -DeploymentProcess
        $actionCount         = 0
        #we need to use $psobject.copy() to avoid changing the original source
        $process.Steps      += $SourceStep.psobject.Copy()
        $NewStep             = $process.steps[-1]
        $NewStep.id          = [guid]::NewGuid().tostring()
        $NewStep.Name        = $newStepName
        $NewStep.Actions     = @($SourceStep.Actions.foreach({ $_.psobject.Copy() })  )
        $NewStep.Actions     | ForEach-Object {
            $_.id            = [guid]::NewGuid().tostring()
            $_.Properties    =   $SourceStep.Actions[$actionCount].Properties.psobject.Copy()
            $_.Packages      = @($SourceStep.Actions[$actionCount].Packages.foreach({ $_.psobject.Copy() }) )
            foreach ( $p    in   $_.Packages) {
                    $p.id  = [guid]::NewGuid().tostring()
            }
        }

        if  ($UpdateScript -is [scriptblock]) { #re-hcreate the script block otherwise variables from this function are out of scope.
            & ([scriptblock]::create( $UpdateScript ))
        }

        Update-OctopusObject $process -Force:$force
    }
}
#need equivalent for runbooks

Function Export-OctopusProject              {
    param (
        [Parameter(Mandatory=$true,ValueFromPipeline=$true,Position=0)]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [object[]]$Project,
        $ZipFilePwd = "DontTellany1!",
        $ZipDestination,
        $TimeOut=300
    )
    begin {
        if ((Invoke-OctopusMethod api).version -lt [version]::new(2021,1)) {
            throw "This requires at least version 2021.1 of Octopus Deploy"
        }
        if ($PSBoundParameters['$ZipFilePwd'] -and -not $ZipDestination) {$ZipDestination = $pwd}
        elseif ($ZipDestination -and -not (Test-Path -PathType Container $ZipDestination)) {
            throw 'FileDestination should be a directory'
        }
    }
    process {
        $Body = @{
            IncludedProjectIds = @();
            Password           = @{HasValue = $True; NewValue = $ZipFilePwd; }
        }
        foreach     ($p in $project) {
            if      ($p.id ) {$body.IncludedProjectIds += $p.Id}
            elseif  ($p -is [string] -and $p -match "^projects-\d+$") {$Body.IncludedProjectIds += $p}
            else    {$Body.IncludedProjectIds += (Get-OctopusProject $p ).id }
        }

        $startTime        = [datetime]::now
        $exportServerTask = Invoke-OctopusMethod -EndPoint "/projects/import-export/export" -Method Post -Item $body

        if     (-not $ZipDestination ) {
            Write-Progress -Activity "Waiting for server task to complete" -Completed
            return {Get-OctopusTask $exportServerTask.TaskId}
        }
        #else ...
        do     {
            $t = Get-OctopusTask $exportServerTask.TaskId
            if ($t.State  -eq "Success") {
                $t.Artifacts() | Where-Object filename -like "*.zip" | ForEach-Object {$_.download($ZipDestination)}
            }
            elseif (-not $t.IsCompleted) {
                Write-Progress -Activity "Waiting for server task to complete" -SecondsRemaining ($startTime.AddSeconds($TimeOut).Subtract([datetime]::now).seconds) -Status $t.State
            }
        }
        While  ((-not $t.IsCompleted) -and [datetime]::now.Subtract($startTime).totalseconds -lt $TimeOut -and
                (-not (start-sleep -Seconds 5))   #Sneaky trick. This waits for 5 seconds and returs true. So we only wait if we're going to go round again.
                )
        if     ( -not $t.IsCompleted) {
                Write-warning "Task Timed out. Cancelling"
                Write-Progress -Activity "Waiting for server task to complete" -SecondsRemaining 0 -Status $t.State
                $null = Invoke-OctopusMethod  -EndPoint $t.Links.Cancel -Method post
        }
        elseif ($t.State -ne "Success") {
                Write-warning "Task completed with Status of $($t.State)"
        }
        Write-Progress -Activity "Waiting for server task to complete" -Completed
    }
}

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
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(Position=1)]
        $Destination = $pwd,

        [Alias('PT')]
        [switch]$PassThru,

        [switch]$Force
    )

    process {
        if ($Project.Name -and $Project.DeploymentProcess ) {
            $name        = $Project.Name
            $process    = $Project.DeploymentProcess()
        }
        else {
            $process    = Get-OctopusProject -Name $Project -DeploymentProcess
            if ($process.count -gt 1)  {
                $process.ProjectId | Export-OctopusDeploymentProcess -Destination $Destination -PassThru:$PassThru -Force:$Force
                return
            }
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
        if     (Test-Path $Destination -PathType Container )    {$DestPath = (Join-Path $Destination $name) + '.json' }
        elseif (Test-Path $Destination -IsValid -PathType Leaf) {$DestPath = $Destination}
        else   {Write-Warning "Invalid destination" ;return}
        ConvertTo-Json $Steps -Depth 10 | Out-File $DestPath -NoClobber:(-not $Force)
        if     ($PassThru) {Get-Item $DestPath}
    }
}
# to do . Import ! You don't know if the export is good or bad until you import. morning Mr Schrodinger