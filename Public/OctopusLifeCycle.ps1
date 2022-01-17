function New-OctopusLifeCyclePhase          {
    [cmdletbinding(DefaultParameterSetName='AllMustComplete')]
    param   (
        [Alias('LifecycleName')]
        [Parameter(Mandatory=$true,Position=0)]
        $Name,

        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        $AutomaticEnvironments,

        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        $OptionalEnvironments,

        [Parameter(ParameterSetName='SomeMustComplete',Mandatory=$true)]
        $MinimumEnvironmentsBeforePromotion = 0,

        [Parameter(ParameterSetName='OptionalPhase',Mandatory=$true)]
        [switch]$IsOptional,

        [switch]$KeepReleaseForever,
        [int]$KeepReleaseQuantity     = 0 ,

        #Ignored if quantity is omitted or zero
        [ValidateSet('Days','Units')]
        [String]$KeepReleaseUnits     = 'Days',

        [switch]$KeepOnTentacleForever,
        [int]$KeepOnTentacleQuantity  = 0 ,

        #Ignored if quantity is omitted or zerop
        [ValidateSet('Days','Units')]
        [String]$KeepOnTentacleUnits  = 'Days'
    )
    if ($AutomaticEnvironments -is [string]) {$AutomaticEnvironments = $AutomaticEnvironments -split '\s*,\s*|\s*;\s*'}
    if ($OptionalEnvironments  -is [string]) {$OptionalEnvironments  = $OptionalEnvironments  -split '\s*,\s*|\s*;\s*'}

    $phase = @{
        Id              = $null
        Name            = $Name
        IsOptionalPhase = $IsOptional -as [bool]
        MinimumEnvironmentsBeforePromotion = [int]$MinimumEnvironmentsBeforePromotion
        AutomaticDeploymentTargets         = @() + $(foreach ($e in $AutomaticEnvironments) { (Get-OctopusEnvironment $e).id})
        OptionalDeploymentTargets          = @() + $(foreach ($e in $OptionalEnvironments)  { (Get-OctopusEnvironment $e).id})
    }
    if (($phase.AutomaticDeploymentTargets.count   -ne  $AutomaticEnvironments.count) -or
        ($phase.OptionalDeploymentTargets.count    -ne  $OptionalEnvironments.count) -or
        ($phase.MinimumEnvironmentsBeforePromotion -gt ($AutomaticEnvironments.count +
                                                        $OptionalEnvironments.count))) {
        Write-Warning "The automatic and optional environments look wrong. Some may not have resolved or Minimum before promotion may be too large."
    }
    if  ($KeepOnTentacleForever -or $KeepOnTentacleQuantity) {
        $phase['TentacleRetentionPolicy'] = @{
            unit              = $KeepOnTentacleUnits
            QuantityToKeep    = $KeepOnTentacleQuantity
            ShouldKeepForever = $KeepOnTentacleForever -as [bool]
        }
    }
    if  ($KeepReleaseForever    -or $KeepReleaseQuantity   ) {
        $phase['ReleaseRetentionPolicy'] = @{
            unit              = $KeepReleaseUnits
            QuantityToKeep    = $KeepReleaseQuantity
            ShouldKeepForever = $KeepReleaseForever -as [bool]
        }
    }

    $phase
}

function  New-OctopusLifeCycle              {
    [cmdletbinding(SupportsShouldProcess)]
    param   (
        [Parameter(Mandatory=$true,Position=0)]
        [Alias('LifecycleName')]
        $Name,
        $Phases,
        $Description,
        #if set to zero Keep forever will be set
        [int]$KeepReleaseQuantity     = 0 ,
        [ValidateSet('Days','Units')]
        #Ignored if quantity is omitted or zero
        [String]$KeepReleaseUnits     = 'Days',
        #if set to zero Keep forever will be set
        [int]$KeepOnTentacleQuantity  = 0 ,
        #Ignored if quantity is omitted or zerop
        [ValidateSet('Days','Units')]
        [String]$KeepOnTentacleUnits  = 'Days',
        [switch]$Force
    )
    process {
        $LifeCycleDefinition = [Ordered]@{
            Name    = $Name
            Id      = $null
            Links   = $null
            SpaceId = ""
            Phases                  = @()
            ReleaseRetentionPolicy  = [ordered]@{
                ShouldKeepForever   = (-not $KeepReleaseQuantity)
                QuantityToKeep      =       $KeepReleaseQuantity
                Unit                =       $KeepReleaseUnits
            }
            TentacleRetentionPolicy = [ordered]@{
                ShouldKeepForever   = (-not $KeepOnTentacleQuantity)
                QuantityToKeep      =       $KeepOnTentacleQuantity
                Unit                =       $KeepOnTentacleUnits
            }
        }
        $phaseCount = 0
        foreach ($p in $Phases.Where({$null -ne $_})) {
            $phaseCount ++
            $LifeCycleDefinition.Phases += $p
        }
        if ($phaseCount) {$TargetMsg = "Add Lifecycle with $phaseCount Phases"}
        else             {$TargetMsg = "Add Lifecycle using the default 'any environment' conventions."}
        if     ($DefinitionOnly) {$LifeCycleDefinition}
        elseif ($Force -or $PSCmdlet.ShouldProcess($Name,$TargetMsg)) {
            Invoke-OctopusMethod -Method Post -EndPoint  lifecycles -Item $LifeCycleDefinition -PSType  OctopusLifeCycle
        }
    }
}

function Set-OctopusLifeCycle               {
    [cmdletbinding(SupportsShouldProcess)]
    param   (
        [Parameter(Mandatory=$true,Position=0)]
        [Alias('Name','ID')]
        $LifeCycle,
        $Phases,
        $Description,
        #if set to zero Keep forever will be set
        [int]$KeepReleaseQuantity ,
        [ValidateSet('Days','Units')]
        [String]$KeepReleaseUnits    ,
        #if set to zero Keep forever will be set
        [int]$KeepOnTentacleQuantity  ,
        [ValidateSet('Days','Units')]
        [String]$KeepOnTentacleUnits ,
        [switch]$Force
    )
    $existing = Get-OctopusLifeCycle $LifeCycle
    #if not existing, or exist > 1
    $changed = $false
    if ($PSBoundParameters.ContainsKey('Description')            -and $existing.Description -ne $Description) {
        $changed = $true
        $existing.Description =  $Description
    }
    if ($PSBoundParameters.ContainsKey('KeepReleaseQuantity')    -and $existing.ReleaseRetentionPolicy.QuantityToKeep -ne $KeepReleaseQuantity) {
        $changed = $true
        Write-Verbose "Updating release quantity to keep to  $KeepReleaseQuantity"
        $existing.ReleaseRetentionPolicy.ShouldKeepForever = $KeepReleaseQuantity -eq 0
        $existing.ReleaseRetentionPolicy.QuantityToKeep    = $KeepReleaseQuantity
    }
    if ($PSBoundParameters.ContainsKey('KeepReleaseUnits')       -and $existing.ReleaseRetentionPolicy.Unit -ne $KeepReleaseUnits) {
        $changed = $true
        Write-Verbose "Updating release units to keep to  $KeepReleaseUnits"
        $existing.ReleaseRetentionPolicy.Unit = $KeepReleaseUnits
    }
    if ($PSBoundParameters.ContainsKey('KeepOnTentacleQuantity') -and $existing.TentacleRetentionPolicy.QuantityToKeep -ne $KeepOnTentacleQuantity) {
        $changed = $true
        Write-Verbose  "Updating tentacle quantity to keep to $KeepOnTentacleQuantity"
        $existing.TentacleRetentionPolicy.ShouldKeepForever = $KeepOnTentacleQuantity -eq 0
        $existing.TentacleRetentionPolicy.QuantityToKeep    = $KeepOnTentacleQuantity
    }
    if ($PSBoundParameters.ContainsKey('KeepOnTentacleQuantity') -and $existing.TentacleRetentionPolicy.Unit -ne $KeepOnTentacleUnits) {
        $changed = $true
        Write-Verbose "Updating tentacle units to keep to $KeepOnTentacleUnits"
        $existing.TentacleRetentionPolicy.Unit = $keep
    }
    if ($Phases) {
        $preExistingPhaseNames = $existing.phases.name -join " "
        $existing.Phases = @{} + $(foreach ($p in $phases) {
                $updatedPhase = $existing.Phases.where{$name -eq $p.name}
                if ($updatedPhase) {
                    if ($p.AutomaticDeploymentTargets -and (($p.AutomaticDeploymentTargets -join " ") -ne ($updatedPhase.AutomaticDeploymentTargets -join " "))){
                        $updatedPhase.AutomaticDeploymentTargets = $p.AutomaticDeploymentTargets
                        $changed = $true
                    }
                    if ($p.OptionalDeploymentTargets  -and (($p.OptionalDeploymentTargets -join " ")  -ne ($updatedPhase.OptionalDeploymentTargets  -join " "))){
                        $updatedPhase.OptionalDeploymentTargets = $p.OptionalDeploymentTargets
                        $changed = $true
                    }
                    if ($p.MinimumEnvironmentsBeforePromotion -ne $updatedPhase.MinimumEnvironmentsBeforePromotion) {
                        $changed = $true
                        $updatedPhase.MinimumEnvironmentsBeforePromotion = $p.MinimumEnvironmentsBeforePromotion
                    }
                    if ($p.IsOptionalPhase -ne $updatedPhase.IsOptionalPhase) {
                        $changed = $true
                        $updatedPhase.IsOptionalPhase = $p.IsOptionalPhase
                    }
                    if ($p.ReleaseRetentionPolicy -and ($p.ReleaseRetentionPolicy.unit +$p.ReleaseRetentionPolicy.QuantityToKeep + $p.ReleaseRetentionPolicy.ShouldKeepForever) -ne
                       ($updatedPhase.ReleaseRetentionPolicy.unit +$updatedPhase.ReleaseRetentionPolicy.QuantityToKeep + $updatedPhase.ReleaseRetentionPolicy.ShouldKeepForever) )  {
                        $changed = $true
                        $updatedPhase.ReleaseRetentionPolicy.unit              = $p.ReleaseRetentionPolicy.unit
                        $updatedPhase.ReleaseRetentionPolicy.QuantityToKeep    = $p.ReleaseRetentionPolicy.QuantityToKeep
                        $updatedPhase.ReleaseRetentionPolicy.ShouldKeepForever = $p.ReleaseRetentionPolicy.ShouldKeepForever
                    }
                    if ($p.TentacleRetentionPolicy -and ($p.TentacleRetentionPolicy.unit +$p.TentacleRetentionPolicy.QuantityToKeep + $p.TentacleRetentionPolicy.ShouldKeepForever) -ne
                       ($updatedPhase.TentacleRetentionPolicy.unit +$updatedPhase.TentacleRetentionPolicy.QuantityToKeep + $updatedPhase.TentacleRetentionPolicy.ShouldKeepForever) )  {
                        $changed = $true
                        $updatedPhase.TentacleRetentionPolicy.unit              = $p.TentacleRetentionPolicy.unit
                        $updatedPhase.TentacleRetentionPolicy.QuantityToKeep    = $p.TentacleRetentionPolicy.QuantityToKeep
                        $updatedPhase.TentacleRetentionPolicy.ShouldKeepForever = $p.TentacleRetentionPolicy.ShouldKeepForever
                    }

                    $updatedPhase
                }
                else {
                    $changed = $true
                    $p
                }
         } )
        if ($preExistingPhaseNames -eq  ($existing.phases.name -join " ")) {
            $changed = $true
        }
    }

    if ($changed -and $Force -or $PSCmdlet.ShouldProcess($Existing.Name,'Update lifecycle')) {
        Invoke-OctopusMethod -PSType OctopusLifeCycle -Method put -EndPoint $existing.Links.Self -Item $existing
    }
}
