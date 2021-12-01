function Add-OctopusProjectStep            {
    <#
      .SYNOPSIS
        Adds a step to a project's deployment process, either importing from JSON, copying form  another Project, or duplicatingwithin the same project

      .DESCRIPTION
        Steps can be complicated, and often the best way to add one to a project is to copy it from somewhere.
        This command can take either projects (as name, ID, or Object), or their deployment process objects
        and a source step, either directly from a deployment process, or exported as JSON, and add the step
        to the project, updating names, parameters, and applicable environments.
        It can make custom alterations specified in a scriptblock paramter

      .PARAMETER Project
        The project whose process is to be updated, this can be the project name, ID or a project object,
        if you have the project object you have the option to use its deployment process in
        the process parameter instead

      .PARAMETER Process
        An object representing the deployment process to be modified, this can come from a project,
        or can be a modified process  for example from a previous call to Add-OctopusProjectSteps

      .PARAMETER SourceStep
        An object representing the step to be copied into the project, or a block of JSON describing it.

      .PARAMETER InputObject
        When input is piped into the command it can be a project, a process or a step. InputObject is used so
        the object and other parameters can be checked and the piped input assigned to the right parameter.
        It should not be used from the command line.

      .PARAMETER NewStepName
        The name for the new step. If this a string it will be assigned directly as the step name
        and if there is a single action for the step the same name will be applied to the action.
        If the parameter is a scriptblock it can use the variable $Name to access the existing name of the
        step and its actions and what ever the script block returns will become the new new name of the
        step / action. A typical script block might be  {$Name -replace 'ServiceFoo', 'ServiceBar' }

      .PARAMETER Before
        Zero-based index of the step before which the new step should be inserted. To insert at the start
        use zero, been the first and second step use 1 and so on. If not specified, or if before is greater
        than the number of  existing steps, the new action will become the last action in the Step.

      .PARAMETER NewActionParameters
        A hash table containing Parameter-name / parameter-value pairs. Each time an action is found with
        a property (parameter) name which matches one in the table, its value is updated to the one in the table.

      .PARAMETER RoleReplace
        Two parameters for a -Replace operation to update the machine-role assigned to the step,
        for example 'ServiceFoo', 'ServiceBar'

      .PARAMETER UpdateScript
        A script block to change the step being added.

      .PARAMETER ExcludeEnvironmentIDs
        If specified will add environments to the Skip-specific-environments setting or remove them
        from the "Run-only-for-specified-environments" settting.

      .PARAMETER Apply
        By default the command returns the updated deployment process but does not send a request to
        Octopus to apply the changes;  Apply (and Force) cause the changes to be applied

      .PARAMETER Force
        Supresses any confirmation message. Force is a superset of Apply; so -Apply -Force does the same as -Force alone.

      .EXAMPLE
        ps >$p         = Get-OctopusProject -Name "Test Project 77"
        ps >$newport    = "1001"
        ps >$newservice = "portal"
        ps >$p.DeploymentProcess().steps[0] | Add-OctopusProjectStep  'Test Project 77' -NewStepName "Add $newService"  -UpdateScript {
        >>            $NewStep.Actions[0].Name = $NewStep.Name; $NewStep.Actions[0].Properties.Port = $newport; $NewStep.Actions[0].Properties.ServiceName =  $newservice
        >>  }

        The first line gets a project and the final line passeses the first step of its deployment process into Add-OctopusProjectStep.
        In the case, Add-OctopusProjectStep is modifying the same projct. It sets the name of the copied step
        using a varaible, and uses a script to modifiy only the first action in the step, changing its name, "port" property and "ServiceName" property.

      .EXAMPLE
        ps >$steps = Get-OctopusProject 'enable*Banana' -DeploymentProcess | Select-Object -ExpandProperty steps | Select-List -multiple -Property Name
        ps >Import-Csv Service.csv |ForEach-Object {
        >>      $params = @{
        >>            RoleReplace         = @('Banana.*',$_.TargetRoles)
        >>            NewStepName         = [scriptblock]::Create("`$name -replace 'Banana','$($_.serviceName)'")
        >>            NewActionParameters = @{Port = $_.port; SiteName = $_.SiteName; WhatIf = 'False'}
        >>      }
        >>     $steps  | Add-OctopusProjectStep @params -Project 'Enable-Everything' -Force
        >>  }

        The first line gets the steps in an existing  deployment process, and uses SELECT-LIST  -Multiple to select a sequence of steps.
        The rest of the example is a loop which repeats for each line in a .csv file
        1 It builds a set of parameters for Add-OctopusProjectStep which:
          * Sets new action parameters,using values from the csv file
          * Sets new names for the steps by replacing part of their name with a value from the csv
          * Sets a new role with a similar substituation
        2. It then pipes the selected steps into Add-OctopusProjectStep with these parameters to add them to a project named "Enable-Everything",
        so if the first line selected 4 steps and the second imported 5 sevices the whole process would add 20 steps to "enable-Everything"

    #>
    [cmdletbinding(DefaultParameterSetName='ByProjectName',SupportsShouldProcess=$true)]
    param   (
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
        [Alias('NewActionName')]
        $NewStepName,

        [hashtable]$NewActionParameters,

        [int32]$Before,

        $RoleReplace,

        [scriptblock]$UpdateScript,

        $ExcludeEnvironmentIDs,

        [switch]$Apply,

        [switch]$Force
    )
    begin   { #check parameters have the right types, and get project's deployment process if need be
        if     ($NewStepName   -and       $NewStepName -isnot [string] -and $NewStepName -isnot [scriptblock]) {
                throw 'The new step name must be a string or a scriptblock'
        }
        if     ($SourceStep    -isnot [string] -and
                                          $SourceStep.pstypenames  -notcontains    'OctopusDeploymentStep') {
                 throw 'SourceStep is not valid, it must be a step from an existing process, or a JSON block describing a step.'
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
        #if before is specified split the steps into those before that one, and that one and after.
        $AfterSteps = @()
        if ($PSBoundParameters.ContainsKey('Before') -and $Process) {
            if ($before -eq 0 ) {
                $AfterSteps    = $Process.Steps
                $Process.steps = @()
                $outputAtEnd   = $true
            }
            if ($before -lt $Process.steps.count -1) {
                $AfterSteps    = $Process.steps[($before)..($process.steps.count -1) ]
                $Process.steps = $Process.steps[0..($before-1)]
                $outputAtEnd   = $true
            }
        }
        else {  $outputAtEnd   = $false}  # Have steps been piped in with a single process having multiple updates ?
    }
    process {
        #region  figure out what to do with piped input we should get to a process and the step going into it
        #first reject anything which isn't a step, a project or a proces, and convert projects to their process
        if       ($InputObject   -and -not ($InputObject.pstypenames.where({$_ -in @('OctopusProject','OctopusDeploymentStep','OctopusDeploymentProcess')}))) {
                  Write-Warning 'Input object is not valid it must be a project, a deployment step, or a Deployment process' ; Return
        }
        elseif   ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusProject') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project)  {
                  Write-Warning 'Input object cannot be a project when a project or process is specified' ; Return}
            else {$InputObject  =         $InputObject.DeploymentProcess()}
        }

        #if Input object was a project and became its process OR if was a process to start with
        if       ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentProcess') {
            if   ($PSBoundParameters.Process -or $PSBoundParameters.Project) {
                  Write-Warning 'Input object cannot be a deployment process when a project or process is specified' ; Return
            }
            else {
                $Process = $InputObject
                #if before is specified split the steps into those before that one, and that one and after.
                if     ($PSBoundParameters.ContainsKey('Before') -and $before -eq 0 ) {
                        $AfterSteps    = $Process.Steps
                        $Process.steps = @()
                }
                elseif ($PSBoundParameters.ContainsKey('Before') -and $before -lt $Process.steps.count -1) {
                        $AfterSteps    = $Process.steps[($before)..($process.steps.count -1) ]
                        $Process.steps = $Process.steps[0..($before-1)]
                }
            }
        }
        elseif   ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusDeploymentStep')    {
            if   ($PSBoundParameters.SourceStep)  {Write-Warning 'Input object cannot be a deployment step when a step parameter is specified' ; Return}
            else {
                  $SourceStep  = $InputObject
                  $outputAtEnd = $true
            }
        }
        if       ($SourceStep    -is [string]) {
                $SourceStep     = $SourceStep | ConvertFrom-Json -ErrorAction Stop
                foreach ($prop  in @('Id', 'Name', 'PackageRequirement', 'Properties', 'Condition', 'StartTrigger','Actions')) {
                    if (-not $SourceStep.psobject.Properties[$prop]) {
                        Write-Warning "The source step needs to be JSON describing a deployment step, but the one provided is missing the $prop property."; return
                    }
                }
                $sourceStep.psTypeNames.Add('OctopusDeploymentStep')
                foreach ($a in $SourceStep.Actions) {$a.pstypeNames.Add('OctopusDeploymentAction')}
        }
        if       (-not ($Process -and $SourceStep)) {
                Write-warning "You must supply a project or its process, and a source step either as parameters or via the pipeline" ; return
        }
        #endregion

        #we need to use select and/or $psobject.copy() to avoid changing the original source
        #We also need to add or remove and re-add our extension properties, and give the step a New GUID.
        $process.Steps         += $SourceStep  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName'
        $newStep                = $process.steps[-1]
        $newStep.id             = [guid]::NewGuid().tostring()
        $newStep.pstypeNames.add('OctopusDeploymentStep')
        if ($Process.ProjectID) {
                Add-Member -InputObject $newStep -NotePropertyName 'ProjectID'   -NotePropertyValue $Process.ProjectId -Force
                Add-Member -InputObject $newStep -NotePropertyName 'ProjectName' -NotePropertyValue (Convert-OctopusID $Process.ProjectId) -Force
        }

        if     ($NewStepName  -is [string])       { $newStep.Name = $NewStepName}
        elseif ($NewStepName  -is [scriptblock])  {
                [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseDeclaredVarsMoreThanAssignments', '', Justification = "Var used in scriptblock passed as param")]
                $name = $newStep.Name  # for use in the script block
                #re-create the script block otherwise variables from this function are out of scope.
                $newstep.name   = & ([scriptblock]::create( $NewStepName ))
        }
        Write-Verbose "New step:   '$($newStep.Name)' - source name was '$($SourceStep.Name)''."

        if ($RoleReplace.count -eq 2 -and $newStep.Properties.'Octopus.Action.TargetRoles') {
                $newStep.Properties = $newStep.Properties.psobject.Copy()
                $newStep.Properties.'Octopus.Action.TargetRoles' = $newStep.Properties.'Octopus.Action.TargetRoles'  -replace $RoleReplace
                Write-verbose ("    Step target-roles         set to '{0}', source was '{1}'." -f $newStep.Properties.'Octopus.Action.TargetRoles', $SourceStep.Properties.'Octopus.Action.TargetRoles')
        }

        $actionCount            = 0
        #As with the step avoid changing the source, add or remove and re-add extension properties and set a new guid.
        #Also make sure we don't change the properties or packages in the source and give  package objects new guids
        $newStep.Actions        = @($SourceStep.Actions  | Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName'  )
        $newStep.Actions        | ForEach-Object {
            $_.id               = [guid]::NewGuid().tostring()
            $_.Properties       =   $SourceStep.Actions[$actionCount].Properties.psobject.Copy()
            $_.Packages         = @($SourceStep.Actions[$actionCount].Packages.foreach({ $_.psobject.Copy() }) )
            foreach ( $p in $_.Packages) {
                      $p.id  = [guid]::NewGuid().tostring()
            }
            $_.pstypeNames.add('OctopusDeploymentAction')
            Add-Member     -InputObject $_ -NotePropertyName StepName    -NotePropertyValue $newstep.Name
            if ($NewStep.ProjectID) {
                Add-Member -InputObject $_ -NotePropertyName ProjectId   -NotePropertyValue $newstep.ProjectId
                Add-Member -InputObject $_ -NotePropertyName ProjectName -NotePropertyValue $newstep.ProjectName
            }

            if      ($NewStepName -is [string] -and $newstep.Actions.count -ne 1)      {
                    Write-Warning "Cannot use '$NewStepName' as the name for multiple actions. Will try to continue with the old action name."
                    $SetParams = @{Action = $_}
            }
            elseif  ($NewStepName) {
                    $SetParams = @{Action = $_ ; NewActionName = $NewStepName  }

            }
            foreach ($param in @('NewActionParameters', 'ExcludeEnvironmentIDs', 'RoleReplace')) {
                if  ($PSBoundParameters.ContainsKey($param)) {
                     $SetParams[$param] = $PSBoundParameters[$param]
                }
            }
            Set-OctopusAction @SetParams | Out-Null
            $actionCount ++
        }

        if     ($UpdateScript)  { & ([scriptblock]::create( $UpdateScript )) }

        if     (-not ($outputAtEnd -or $Force -or $Apply))   {
            $Process.steps  +=   $AfterSteps
            $Process
        }
        elseif (-not  $outputAtEnd) {
            $Process.steps  +=   $AfterSteps
            #Note we DON'T need to remove our extensions. Provided the data in Octopus' schema is valid it ignores data NOT in the schema.
            Update-OctopusObject $Process -Force:$force
        }
        else   {Write-Verbose "Step completed."}
    }
    end     {
        if     ($outputAtEnd -and -not ($Force -or $Apply)) {
            $Process.steps  +=   $AfterSteps
            $Process
        }
        elseif ($outputAtEnd) {
            $Process.steps  +=   $AfterSteps
            Update-OctopusObject $Process -Force:$force
        }
    }
}
#need equivalent for runbooks and for project actions.
