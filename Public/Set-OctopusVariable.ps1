function Set-OctopusVariable                {
    <#
      .SYNOPSIS
        Adds or updates one or more Octopus variables in a library or project variable set

      .DESCRIPTION
        Projects link to a variable set which holds their variables. Variable sets can also be found via a placeholder in the library.
        The Command accepts EITHER a project (object, name, or ID) OR a library-variableSet (object, Name or ID),
        OR the set obtained from either (object or ID) and adds one or more variables to it.

    .PARAMETER VariableSet
        A variable set object or the ID of a variable set object. If specfied no libraryVariableSet or Project parameter is used.

    .PARAMETER LibraryVariableSet
        The library entry whose variable set should be used. If specfied no VariableSet  or Project parameter is used.

    .PARAMETER Project
        The Project whose variable set should be used be If specfied no VariableSet  or libraryVariableSet parameter is used.

    .PARAMETER VariableName
        The name of the variable to be added or changed. If input is piped into the command this can come from a "name" or "variableName" property/column

    .PARAMETER Value
        The New value for the variable. If input is piped into the command this can come from a "Value" property/column

    .PARAMETER Type
        The data type for the variable - "String" by default. If input is piped into the command this can come from a "Type" property/column

    .PARAMETER Sensitive
        Indicates the variable should be treated as sensitive and not disaplayed. If input is piped into the command this can come from a "Sensitive" or "IsSensitive" property/column

    .PARAMETER ScopeEnvironment
        Sets the scope of the variable to one or more environment specified by ID or name (s, either as a string array or a list separated by , or ; characters).
         If input is piped into the command this can come from a "ScopeEnvironment" property/column

    .PARAMETER ScopeRole
        Sets the scope of the variable to one or more server roles (either as a string array or a list separated by , or ; characters).
        If input is piped into the command this can come from a "ScopeRole" property/column

    .PARAMETER ScopeChannel
        Sets the scope of the variable to one or more project channels specified by ID or name (not used with library variable sets) either as a string array or a list separated by , or ; characters.
        If input is piped into the command this can come from a "ScopeChannel" property/column

    .PARAMETER ScopeMachine
        Sets the scope of the variable to one or more machines specified by ID or name, (either as a string array or a list separated by , or ; characters).
        If input is piped into the command this can come from a "ScopeMachine" property/column

    .PARAMETER ScopeAction
        Sets the scope of the variable to one or more project actions specified by ID or name (not used with library variable sets) either as a string array or a list separated by , or ; characters.
        If input is piped into the command this can come from a "ScopeMachine" property/column.

    .PARAMETER ScopeProcessOwner

    .PARAMETER Force
        If specified prevents any confirmation prompt being displayed.

    .PARAMETER PassThru
        If specified returns the variable set instead of running silently.

    import-csv foo.csv |  select -ExcludeProperty IsSensitive -Property *, @{n='IsSensitive';e={$_.IsSensitive.toString -match "true|[1-9]" }} |  Set-OctopusVariable -VariableSet $variableset
#>
    [alias('sov')]
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default',ConfirmImpact='High')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName='Default')]
        $VariableSet,

        [ArgumentCompleter([OctopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        [Parameter(Mandatory=$true,Position=1,ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        $VariableName ,

        [Parameter(Mandatory=$true,Position=2,ValueFromPipelineByPropertyName)]
        $Value,

        [Parameter(Position=3,ValueFromPipelineByPropertyName)]
        $Type  = 'String',

        [Parameter(ValueFromPipelineByPropertyName)]
        [Alias('IsSensitive')]
        [switch]$Sensitive,

        [ArgumentCompleter([OctopusEnvironmentNamesCompleter])]
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeEnvironment,

        [ArgumentCompleter([OctopusMachineRolesCompleter])]
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeRole,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeChannel,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeMachine,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeAction,

        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeProcessOwner,

        [switch]$Force,

        [Alias('PT')]
        [switch]$PassThru,

        [Parameter(DontShow=$true)]
        [PSCmdlet]$psc
    )
    begin   {
        $VariableSet = Resolve-VariableSet -Project $Project -LibraryVariableSet $LibraryVariableSet -VariableSet $VariableSet
        if (-not $VariableSet -or $VariableSet.count -gt 1) {throw "Could not get a unique variable set from the parameters provided"; return }
        $restParams     = @{Method ='Put'; EndPoint = $VariableSet.Links.Self; PSType ='OctopusVariableSet'}
        $changes        = 0
        $skipped        = 0
        $varsToAdd      = @()
        $varsBefore     = $VariableSet.Variables.Count
        #region For different kinds of scope (environments, roles, etc). we need to swap ID <--> name
        #So build two hashes with scope-Kind as keys and values of hash tables which map one way or the other
        $scopeNamesHash = @{}
        $scopeIDsHash   = @{}
        foreach ($ScopeType in $VariableSet.ScopeValues.psobject.Properties.Name) {
            $IDHash     = @{}
            $NameHash   = @{}
            foreach ($IdNamePair in $VariableSet.ScopeValues.$scopeType) {
                $IDHash[$IdNamePair.id]    = $IdNamePair.Name
                #What if we get asked to find the ID for an ID? As well as name-->ID, ensure we have ID-->ID
                $NameHash[$IdNamePair.Name]= $IdNamePair.ID
                $NameHash[$IdNamePair.ID]  = $IdNamePair.ID
            }
            $scopeNamesHash[$ScopeType]    = $NameHash
            $scopeIDsHash[$ScopeType]      = $IDHash
         }
         Write-Verbose "Variable set has the ID '$($VariableSet.Id)' and is owned by '$($VariableSet.OwnerId) and contained $($VariableSet.Variables.Count) variables at the start."
        #endregion
    }
    process {
        #if this variable isn't scoped, see if there is an existing variable to update, prepare to add it if not
        if (-not ($ScopeEnvironment -or $ScopeRole -or $ScopeChannel -or $ScopeMachine -or $ScopeAction -or $ScopeProcessOwner )) {
            $variableToUpdate = $VariableSet.Variables | Where-Object {$_.Name -eq $VariableName -and -not $_.Scope.psobject.Properties.count}
            #Sensitive values export as blank. Don't re-import blank over a sensitive value.
            # Also skip If we have multiple values with blank scope (we shouldn't but it happens)
            if ($variableToUpdate.count -eq 1 -and $variableToUpdate.value -ne $value -and -not ($Sensitive -and [string]::IsNullOrEmpty($value) ) ) {
                $variableToUpdate.Value = $Value
                $changes ++
                Write-Verbose "Change $changes. Update existing, unscoped variable '$VariableName' with internal ID $($variableToUpdate.Id). "
            }
            elseif ($variableToUpdate) {
                Write-Verbose "Unscoped variable '$VariableName' was not changed"
            }
            else { #if variable doesn't exist
                $changes ++
                Write-Verbose "Change $changes. Adding new unscoped variable '$VariableName'."
                $varsToAdd +=  [pscustomobject]@{Name = $VariableName; Value = $value; Type = $type; IsSensitive = ($Sensitive -as [bool]) }
            }
        }
        else { #we're scoped
            #Allow 0 or  False  but not not "" or null
            if ([string]::IsNullOrEmpty($value) )  {
                $skipped ++
                Write-Warning "Skipping '$VariableName' as its value is empty,"
            }
            else {
                $varScope = @{}
                $badScope = $false
                #region foreach of the scope-types, split strings at , or ; and look up the corresponding ID
                <#The are 3 gotchas
                 (1) Most of the time there will be one, item and the API requires an array
                 (2) By design hash-table lookups return a null for a miss.
                     So if $ScopeEnvironment is "Dev, Prod" and the hash has "Development", "Production"
                     we need to stop $null,$null going into the results. Because ...
                 (3) If we have scoped variables and (e.g.) environments don't match we'll get
                     multiple instances of the same unscoped variable
                #>
                if ($ScopeEnvironment)  {
                    $ScopeEnvironment = $ScopeEnvironment -split '\s*,\s*|\s*;\s*'
                    $varScope['Environment'] = @() + $scopeNamesHash.Environments[$ScopeEnvironment].where({$null -ne $_})
                    if ($varScope['Environment'].count -ne $ScopeEnvironment.count) {$badScope = $true}
                }
                if ($ScopeRole)         {
                    $ScopeRole = $ScopeRole -split '\s*,\s*|\s*;\s*'
                    $varScope['Role'] = @() + $scopeNamesHash.Roles[$ScopeRole].where({$null -ne $_})
                    if ($varScope['Role'].count -ne $ScopeEnvironment.count) {$badScope = $true}
                }
                if ($ScopeChannel)      {
                    $ScopeChannel = $ScopeChannel -split '\s*,\s*|\s*;\s*'
                    $varScope['Channel'] = @() + $scopeNamesHash.Channels[$ScopeChannel].where({$null -ne $_})
                    if ($varScope['Channel'].count -ne $ScopeChannel.count) {$badScope = $true}
                }
                if ($ScopeMachine)      {
                    $ScopeMachine = $ScopeMachine -split '\s*,\s*|\s*;\s*'
                    $varScope['Machine'] = @() + $scopeNamesHash.Machines[$ScopeMachine].where({$null -ne $_})
                    if ($varScope['Machine'].count -ne $ScopeMachine.count) {$badScope = $true}
                }
                if ($ScopeAction)       {
                    $ScopeAction = $ScopeAction -split '\s*,\s*|\s*;\s*'
                    $varScope['Action'] = @() + $scopeNamesHash.Actions[$ScopeAction].where({$null -ne $_})
                    if ($varScope['Action'].count -ne $ScopeAction.count) {$badScope = $true}
                }
                if ($ScopeProcessOwner) {
                    $ScopeProcessOwner = $ScopeProcessOwner -split '\s*,\s*|\s*;\s*'
                    $varScope['ProcessOwner'] = @() + $scopeNamesHash.Processeses[$ScopeProcessOwner].where({$null -ne $_})
                    if ($varScope['ProcessOwner'].count -ne $ScopeProcessOwner.count) {$badScope = $true}
                }
                #endregion
                if ($badScope) {
                    Write-Warning "$VariableName had scopes which could not be matched correctly. It will NOT be processed."
                    $skipped ++
                }
                else {
                    $newVar = @{Name = $VariableName; Value = $value; Type = $type; IsSensitive = ($Sensitive -as [bool]) }
                    if ($varScope.count) {
                        $newVar['Scope'] = [PSCustomObject]$varScope
                    }
                    $varsToAdd +=  [pscustomobject]$newvar
                    $changes ++
                }
            }
        }
    }
    end     {
        #at the end of process we have updated existing unscoped variables but not written back. We have new unscoped and all scoped in varstoAdd
        if ($varsToAdd.Count -gt 0) {
            # To avoid complexity if we have any instances of VarName with a scope, we will delete ALL existing scoped instances of it and add whats specified.
            # This means we can pipe in 2 or more scoped values for VarName, but if we run two commands to add the first and the second, the second will delete the first
            $existingScopedVars = $variableset.Variables.where({$_.Scope.psobject.properties.count}).name | Sort-Object -Unique
            $varnamesToDelete   = $varstoadd | Where-Object {$_.scope -and $_.Name -in $existingScopedVars} | Select-Object -expand name | Sort-Object -unique
            if ($varnamesToDelete.Count -ge 1) {
                Write-Verbose "Scoped versions of $($varnamesToDelete -join ', ') will be replaced."
                $variableSet.Variables = $variableSet.Variables.Where( {$_.Name -notin $varnamesToDelete -or -not $_.Scope.psobject.Properties.count})
                Write-Verbose "Removed $($varsBefore - $VariableSet.Variables.Count) variable(s)."
            }
            foreach ($v in $varsToAdd) {$v.pstypenames.Add('OctopusVariable')}
            $VariableSet.Variables += $varsToAdd
        }
        $varsToAdd | Out-String | Write-Verbose
        Write-Verbose "Updated variable set contains $($VariableSet.Variables.Count) variable(s), with $changes new value(s) and $skipped item(s) skipped."
        if (-not $psc) {$psc = $PSCmdlet}
        if ($changes -and  ($Force -or $psc.ShouldProcess($VariableSet.Id,"Apply $changes variable updates"))) {
            $result = Invoke-OctopusMethod @restParams -Item $VariableSet
            if ($Passthru) {$result}
        }
    }
}
