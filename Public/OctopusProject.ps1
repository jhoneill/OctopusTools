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
        if      (-not $item)                               {return}
        elseif  ($PSCmdlet.ParameterSetName -eq 'Default') {$item}
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

function Copy-OctopusProjectStep            {
<#
 $p         = Get-OctopusProject -Name "Test Project 77"
$newport    = "1001"
$newservice = "portal"
$p.DeploymentProcess().steps[0] | Add-OctopusProjectDeploymentStep  'Test Project 77' -NewStepName "Add $newService"  -UpdateScript {
            $NewStep.Actions[0].Name = $NewStep.Name; $NewStep.Actions[0].Properties.Port = $newport; $NewStep.Actions[0].Properties.ServiceName =  $newservice
}
#>
    [cmdletbinding(DefaultParameterSetName='ByProjectName')]
    param (
        [Parameter(Mandatory=$false, ParameterSetName='PipedAndProject',    Position=0 )]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProjectName', Position=0 )]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project,

        [Parameter(Mandatory=$false, ParameterSetName='PipedAndProcess')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProcess')]
        $Process,

        [Parameter(Mandatory=$false, ParameterSetName='PipedAndStep')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProjectName',  Position=1)]
        [Parameter(Mandatory=$true,  ParameterSetName='ByProcess',      Position=1)]
        $SourceStep,

        [Parameter(Mandatory=$true, ParameterSetName='PipedAndProject',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true, ParameterSetName='PipedAndProcess',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true, ParameterSetName='PipedAndStep',ValueFromPipeline=$true)]
        $InputObject,

        [Parameter(Position=2)]
        $NewStepName,

        [Parameter(Position=3)]
        [hashtable]$NewActionParameters,

        [Parameter(Position=4)]
        $RoleReplace,

        [Parameter(Position=5)]
        [scriptblock]$UpdateScript,

        [switch]$Apply,

        [switch]$Force
    )
    begin   { #check parameters have the right types, and get project's deployment process if need be
        if     ($NewStepName   -and       $NewStepName -isnot [string] -and $NewStepName -isnot [scriptblock]) {
                throw 'The new step name must be a string or a scriptblock'
        }
        if     ($SourceStep    -and       $SourceStep.pstypenames  -notcontains    'OctopusDeploymentStep') {
                 throw 'SourceStep is not valid, it must be a step from an existing process.'
        }
        elseif ($Process       -and       $Process.pstypenames     -notcontains    'OctopusDeploymentProcess') {
                throw 'Process is not valid, it must be an existing deployment process.'
        }
        elseif (-not $Process  -and       $Project.pstypenames     -contains       'OctopusProject' ) {
                     $Process  = $Project.DeploymentProcess()
        }
        elseif ($Project       -and -not  $Process) {
                $Process = Get-OctopusProject -Project $Project -DeploymentProcess
                if (-not $Process) {throw 'Project is not valid, it must be or resolve to an existing project' }
        }
    }
    process {
        #region  figure out what to do with piped input we should get to a process and the step going into it
        $outputAtEnd           = $false  # Have steps been piped in with a single process having multiple updates ?
        if     ($InputObject   -and -not ($InputObject.pstypenames.where({$_ -in @('OctopusProject','OctopusDeploymentStep','OctopusDeploymentProcess')}))) {
                Write-Warning 'Input object is not valid it must be a project, a deployment step, or a Deployment process' ; Return
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusProject') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project)  {
                  Write-Warning 'Input object cannot be a project when a project or process is specified' ; Return}
            else {$Process     = $InputObject.DeploymentProcess()}
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentProcess') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project) {
                  Write-Warning 'Input object cannot be a deployment process when a project or process is specified' ; Return
        }
            else {$Process = $InputObject}
        }
        elseif ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentStep') {
            if   ($PSBoundParameters.SourceStep)  {Write-Warning 'Input object cannot be a deployment step when a step parameter is specified' ; Return}
            else {
                  $SourceStep   = $InputObject
                  $outputAtEnd = $true
            }
        }

        if     (-not ($Process -and $SourceStep)) {
            Write-warning "You must supply a project or its process, and a source step either as parameters or via the pipeline" ; return
        }
        #endregion

        #we need to use select and/or $psobject.copy() to avoid changing the original source
        #We also need to remove some of the properties added to actions and steps to make them nicer
        $process.Steps        += $SourceStep  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName'
        $newStep               = $process.steps[-1]
        if     ($NewStepName -is [string])       { $newStep.Name = $NewStepName}
        elseif ($NewStepName -is [scriptblock])  {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                $name = $newStep.Name  # for use in the script block
                #re-create the script block otherwise variables from this function are out of scope.
                $newstep.name = & ([scriptblock]::create( $NewStepName ))
        }
        Write-Verbose "New step: $($newStep.Name) - source was $($SourceStep.Name)."
        if ($RoleReplace.count -eq 2 -and $newStep.Properties.'Octopus.Action.TargetRoles') {
                $newStep.Properties = $newStep.Properties.psobject.Copy()
                $newStep.Properties.'Octopus.Action.TargetRoles' = $newStep.Properties.'Octopus.Action.TargetRoles'  -replace $RoleReplace
                Write-verbose "    Step target-roles = $($newStep.Properties.'Octopus.Action.TargetRoles'), was '$($SourceStep.Properties.'Octopus.Action.TargetRoles')'."
        }

        $newStep.pstypeNames.add('OctopusDeploymentStep')
        $newStep.id            = [guid]::NewGuid().tostring()
        $actionCount           = 0
        $newStep.Actions       = @($SourceStep.Actions  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName'  )
        $newStep.Actions       | ForEach-Object {
            if ($NewStepName -is [string] -and $newstep.Actions.count -eq 1) {
                $_.Name = $NewStepName
            }
            elseif ($NewStepName -is [string])      {
                Write-Warning "Cannot use '$NewStepName' as the name for multiple actions."
            }
            elseif ($NewStepName -is [scriptblock]) {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                $name = $_.Name  # for use in the script block
                #re-create the script block otherwise variables from this function are out of scope.
                $_.name = & ([scriptblock]::create( $NewStepName ))
            }
            Write-Verbose "    Action $($_.name) - was $($SourceStep.Actions[$actionCount].Name)."
            $_.pstypeNames.add('OctopusDeploymentAction')
            $_.id            = [guid]::NewGuid().tostring()
            $_.Properties    =   $SourceStep.Actions[$actionCount].Properties.psobject.Copy()
            $_.Packages      = @($SourceStep.Actions[$actionCount].Packages.foreach({ $_.psobject.Copy() }) )
            foreach ( $p     in  $_.Packages) {
                      $p.id  = [guid]::NewGuid().tostring()
            }
            foreach ($k in $NewActionParameters.Keys) {
                if ($_.properties.$k) {
                    $_.properties.$k = $NewActionParameters.$k
                    Write-verbose "        Property '$k' = $($_.properties.$k)"
                }
            }
            if ($RoleReplace.count -eq 2 -and $_.TargetRoles) {
                $_.TargetRoles = $_.TargetRoles -replace $RoleReplace
                Write-verbose "        Action target-roles = $($_.TargetRoles), was '$($SourceStep.Actions[$actionCount].TargetRoles)'."
            }
            $actionCount ++
        }

        if     ($UpdateScript) { & ([scriptblock]::create( $UpdateScript )) }

        if     (-not ($outputAtEnd -or $Force -or $Apply))   {$Process}
        elseif (-not  $outputAtEnd) {
            $Process.Steps = @($Process.Steps   | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
            foreach ($s      in $Process.steps) {
                $s.Actions = @($S.Actions       | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
            }
            Update-OctopusObject $Process -Force:$force
        }
        else {  Write-Verbose "Step completed."}
    }
    end {
        if     ($outputAtEnd -and -not ($Force -or $Apply)) {$Process}
        elseif ($outputAtEnd) {
            $Process.Steps = @($Process.Steps   | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName')
            foreach ($s      in $Process.steps) {
                $s.Actions = @($S.Actions       | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName')
            }
            Update-OctopusObject $Process -Force:$force
        }
    }
}
#need equivalent for runbooks
