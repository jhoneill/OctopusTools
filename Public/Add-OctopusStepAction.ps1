function Add-OctopusStepAction            {
    <#
      .SYNOPSIS
        Adds an Action definition to a step in a project's deployment process

      .DESCRIPTION
        Each step in an octopus deployment processs contains one or more actions.
        This command takes a step object and new action (either an action in an
        existing step or a JSON block describing one) and adds the Action to the step,
        updating names, parameters, and applicable environments

      .PARAMETER Step
        An object representing the deployment Step to be modified, taken from a project's deployment process

      .PARAMETER SourceAction
        An object representing the Action to be copied into the project

      .PARAMETER InputObject
        When input is piped into the command it can be a Step or am Action. InputObject is used so
        the object and other parameters can be checked and the piped input assigned to the right parameter.
        It should not be used from the command line.

      .PARAMETER NewActionName
        If the parameter is a script block it can use the variable $Name to access the existing name of the Action;
        whatever the script block returns will become the new new name of the script / action.
        A typical script block might be  {$Name -replace 'ServiceFoo', 'ServiceBar' }

      .PARAMETER Before
        Zero-based index of the Action before which the new Action should be inserted.
        To insert as the first step use Zero. If not specified, or if before is greater than the number of
        existing actions, the new action will become the last action in the setp.

      .PARAMETER NewActionParameters
        A hash table containing Parameter-name / parameter-value pairs. Any  property (parameter) whose name
        matches a key in the table, has its value updated to the one in the table.

      .PARAMETER RoleReplace
        Two parameters for a -Replace operation to update the machine-role assigned to the Action,
         forexample 'ServiceFoo', 'ServiceBar'

      .PARAMETER ExcludeEnvironmentIDs
        If specified will add environments to the Skip-specific-environments setting or remove them
        from the "Run-only-for-specified-environments" settting

      .EXAMPLE
        ps >$p         = Get-OctopusProject -Name "Test Project 77"
        ps >$newport    = "1001"
        ps >$newservice = "portal"
        ps >$p.DeploymentStep().Actions[0] | Add-OctopusProjectAction  'Test Project 77' -NewActionName "Add $newService"  -UpdateScript {
        >>            $NewAction.Actions[0].Name = $NewAction.Name; $NewAction.Actions[0].Properties.Port = $newport; $NewAction.Actions[0].Properties.ServiceName =  $newservice
        >>  }

        The first line gets a project and the final line passeses the first Action of its deployment Step into Add-OctopusProjectAction.
        In the case, Add-OctopusProjectAction is modifying the same projct. It sets the name of the copied Action
        using a varaible, and uses a script to modifiy only the first action in the Action, changing its name, "port" property and "ServiceName" property.

      .EXAMPLE
        ps >$Actions = Get-OctopusProject 'enable*Banana' -DeploymentStep | Select-Object -ExpandProperty Actions | Select-List -multiple -Property Name
        ps >Import-Csv Service.csv |ForEach-Object {
        >>      $params = @{
        >>            RoleReplace         = @('Banana.*',$_.TargetRoles)
        >>            NewActionName         = [scriptblock]::Create("`$name -replace 'Banana','$($_.serviceName)'")
        >>            NewActionParameters = @{Port = $_.port; SiteName = $_.SiteName; WhatIf = 'False'}
        >>      }
        >>     $Actions  | Add-OctopusProjectAction @params -Project 'Enable-Everything' -Force
        >>  }

        The first line gets the Actions in an existing  deployment Step, and uses SELECT-LIST  -Multiple to select a sequence of Actions.
        The rest of the example is a loop which repeats for each line in a .csv file
        1 It builds a set of parameters for Add-OctopusProjectAction which:
          * Sets new action parameters,using values from the csv file
          * Sets new names for the Actions by replacing part of their name with a value from the csv
          * Sets a new role with a similar substituation
        2. It then pipes the selected Actions into Add-OctopusProjectAction with these parameters to add them to a project named "Enable-Everything",
        so if the first line selected 4 Actions and the second imported 5 sevices the whole Step would add 20 Actions to "enable-Everything"

    #>
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSShouldProcess', '', Justification = "Should process is set in this function to apply in a function it calls.")]
    [cmdletbinding(DefaultParameterSetName='ByStep',SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$false, ParameterSetName='PipedAndStep')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByStep')]
        $Step,

        [Parameter(Mandatory=$false, ParameterSetName='PipedAndAction')]
        [Parameter(Mandatory=$true,  ParameterSetName='ByStep',      Position=1)]
        $SourceAction,

        [Parameter(Mandatory=$true, ParameterSetName='PipedAndStep',ValueFromPipeline=$true)]
        [Parameter(Mandatory=$true, ParameterSetName='PipedAndAction',ValueFromPipeline=$true)]
        $InputObject,

        [Parameter(Position=2)]
        $NewActionName,

        [hashtable]$NewActionParameters,

        [int32]$Before,

        $RoleReplace,

        $ExcludeEnvironmentIDs,

        [Parameter(DontShow=$true)]
        [ActionPreference]$VerbosePreference = $PSCmdlet.GetVariableValue('VerbosePreference')
    )
    begin   { #check parameters have the right types, and get project's deployment Step if need be
        if     ($NewActionName -and $NewActionName -isnot [string] -and $NewActionName -isnot [scriptblock]) {
                throw 'The new Action name must be a string or a scriptblock'
        }
        if     ($Step          -and $Step.pstypenames -notcontains    'OctopusProcessStep') {
                throw 'Step is not valid, it must be an existing deployment Step.'
        }
        #if before is specified split the Actions into those before that one, and that one and after.
        $AfterActions = @()
        if ($PSBoundParameters.ContainsKey('Before') -and $Step) {
            if ($before -eq 0 ) {
                $AfterActions  = $Step.Actions
                $Step.Actions  = @()
                $outputAtEnd   = $true
            }
            if ($before -lt $Step.Actions.count -1) {
                $AfterActions  = $Step.Actions[($before)..($Step.Actions.count -1) ]
                $Step.Actions  = $Step.Actions[0..($before-1)]
                $outputAtEnd   = $true
            }
        }
        else {  $outputAtEnd   = $false}  # Have Actions been piped in with a single step having multiple updates ?
    }
    process {
        #region  figure out what to do with piped input we should get to a Step and the Action going into it
        #first reject anything which isn't a Action, a project or a proces, and convert projects to their Step
        if       ($InputObject   -and -not ($InputObject.pstypenames.where({$_ -in @('OctopusProcessAction','OctopusProcessStep')}))) {
                  Write-Warning 'Input object is not valid it must be a deployment Action, or a deployment step' ; Return
        }

        #if Input object was a project and became its Step OR if was a Step to start with
        if       ($InputObject   -and       $InputObject.pstypenames -contains       'OctopusProcessStep') {
            if   ($PSBoundParameters.Step) {
                  Write-Warning 'Input object cannot be a deployment Step when a step is specified as a parameter' ; Return
            }
            else {
                $Step = $InputObject
                #if before is specified split the Actions into those before that one, and that one and after.
                if     ($PSBoundParameters.ContainsKey('Before') -and $Before -eq 0 ) {
                        $AfterActions = $Step.Actions
                        $Step.Actions = @()
                }
                elseif ($PSBoundParameters.ContainsKey('Before') -and $before -lt $Step.Actions.count -1) {
                        $AfterActions = $Step.Actions[($Before)..($Step.Actions.count -1) ]
                        $Step.Actions = $Step.Actions[0..($Before-1)]
                }
            }
        }
        elseif   ($InputObject)    {
            if   ($PSBoundParameters.SourceAction)  {Write-Warning 'Input object cannot be a deployment Action when an action parameter is specified' ; Return}
            else {
                  $SourceAction = $InputObject
                  $outputAtEnd  = $true
            }
        }
        if       ($SourceAction    -is [string]) { $SourceAction     = $SourceAction | ConvertFrom-Json -ErrorAction Stop }
        foreach  ($prop  in @('Id', 'Name', 'Packages', 'Properties', 'IsDisabled', 'IsRequired','ActionType')) {
                    if (-not $SourceAction.psobject.Properties[$prop]) {
                        Write-Warning "The source action needs to describeg a deployment action, but the one provided is missing the $prop property."; return
                    }
        }
        if       (-not ($Step -and $SourceAction)) {
                Write-warning "You must supply a project or its Step, and a source Action either as parameters or via the pipeline" ; return
        }
        #endregion

        #we need to use select and/or $psobject.copy() to avoid changing the original source
        #We also need to remove some of the properties added to actions and Actions to make them nicer
        $Step.Actions        += $SourceAction  |  Select-Object -Property * -ExcludeProperty 'ProjectId','ProjectName','StepName'
        $newAction            = $Step.Actions[-1]
        $newAction.Properties = $SourceAction.Properties.psobject.Copy()
        $newAction.Packages   = @($SourceAction.Packages.foreach({ $_.psobject.Copy() }) )
        $newAction.pstypenames.add('OctopusProcessAction')
        Add-Member     -InputObject $newAction -NotePropertyName StepName    -NotePropertyValue $Step.Name
        if ($Step.ProjectID) {
            Add-Member -InputObject $newAction -NotePropertyName ProjectId   -NotePropertyValue $Step.ProjectId
            Add-Member -InputObject $newAction -NotePropertyName ProjectName -NotePropertyValue $Step.ProjectName
        }


        foreach (   $p in $newAction.Packages) {
                    $p.id  = [guid]::NewGuid().tostring()
        }
        if  ($NewActionName) { $SetParams = @{Action = $newAction ; NewActionName = $NewActionName  }}
        else                 { $SetParams = @{Action = $newAction}}
        foreach ($param in @('NewActionParameters', 'ExcludeEnvironmentIDs', 'RoleReplace')) {
            if  ($PSBoundParameters.ContainsKey($param)) {
                    $SetParams[$param] = $PSBoundParameters[$param]
            }
        }
        Set-OctopusAction @SetParams | Out-Null

        if     (-not $outputAtEnd) {$Step.Actions += $AfterActions}
    }
    end     {if     ($outputAtEnd) {$Step.Actions += $AfterActions} }
}
