function Get-OctopusLibraryScriptModule     {
<#
    .example
    Get-OctopusLibraryScriptModule  | foreach { Get-OctopusLibraryScriptModule $_.name -ExpandModules  > "$pwd\$($_.name).ps1"}
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    [Alias('Get-OctopusScriptModule')]
    param   (
        [ArgumentCompleter([OptopusLibScriptModulesCompleter])]
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0, ValueFromPipeline=$true )]
        [Parameter(ParameterSetName='Expand',   Mandatory=$true,  Position=0, ValueFromPipeline=$true )]
        $ScriptModule,

        [Parameter(ParameterSetName='Expand',   Mandatory=$true  )]
        [switch]$Expand
    )
    process {
        $item = Get-Octopus -Kind libraryvariableset -Key $ScriptModule |
                    Where-Object ContentType -eq 'ScriptModule' | Sort-Object -Property name
        if     (-not $Expand) {$item}
        else   {
            foreach ($m in $item) {
                $hash = [ordered]@{Name=$m.Name}
                Invoke-OctopusMethod $m.Links.Variables | Select-Object -ExpandProperty variables | ForEach-Object {
                    #names have "[script name]" appended - we don't want that so remove them
                    $n = $_.name -replace '\s*\[.*\]\s*$',''
                    $hash[$n]=$_.value
                }
                $result = [pscustomobject]$hash
                $result.pstypenames.add('OctopusLibraryScriptModule')
                $result
            }
        }
    }
}

function New-OctopusLibraryScriptModule     {
    [Alias('New-OctopusScriptModule')]
    param   (
        [Parameter(Mandatory=$true,  Position=0,ValueFromPipelineByPropertyName=$true)]
        $Name,
        [Parameter(Mandatory=$true,  Position=1,ValueFromPipelineByPropertyName=$true)]
        $ScriptBody,
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        [ValidateSet('Bash', 'CSharp', 'FSharp', 'PowerShell', 'Python')]
        $Syntax = 'PowerShell',
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $Description
    )
    $moduleDefinition = @{
            Id            = $null
            ContentType   = 'ScriptModule'
            Name          = $Name
            syntax        = $Syntax
            scriptBody    = $ScriptBody -replace "(?<!\r)\n","`r`n"
            Description   = $Description
            Links         = $null
            VariableSetId = $null
            variableSet   = $null
            Templates     = @()
    }
    $result = Invoke-OctopusMethod -PSType OctopusLibraryVariableSet  -Method Post -EndPoint "libraryvariablesets" -Item $moduleDefinition
    Set-OctopusLibraryVariable -LibraryVariableSet $result.id -VariableName "Octopus.Script.Module[$Name]" -Value $ScriptBody
    Set-OctopusLibraryVariable -LibraryVariableSet $result.id -VariableName "Octopus.Script.Module.Language[$Name]" -Value $Syntax
    $result
}

function Set-OctopusVariableSetMember      {
<#
    import-csv foo.csv |  select -ExcludeProperty IsSensitive -Property *, @{n='IsSensitive';e={$_.IsSensitive.toString -match "true|[1-9]" }} |  Set-OctopusVariableSetMember -VariableSet $variableset
#>
    [alias('sov')]
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName='Default')]
        $VariableSet,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
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
        [Parameter(ValueFromPipelineByPropertyName=$true)]
        $ScopeEnvironment,
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
        [switch]$PassThru
    )
    begin   {
        #region ensure we have the variables and scopes (not their parent or the ID for them) before we proceed
        #We may have been given the name or the ID for a project or for a library variable set.
        if         ($Project)            {$VariableSet = Get-OctopusProject             -Variables -Project $Project }
        elseif     ($LibraryVariableSet) {$VariableSet = Get-OctopusLibraryVariableSet  -Variables -LibraryVariableSet $LibraryVariableSet}
        #If not we may we got the parent of the set object or its ID,
        if  ( -not ($VariableSet.id  -and $VariableSet.OwnerId -and $VariableSet.ScopeValues -and $VariableSet.Variables)) {
            if     ($VariableSet.Links.Variables) {
                    Write-Verbose "Getting variable set for '$($VariableSet.Name)'', ($($VariableSet.Id))."
                    $VariableSet = Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint $VariableSet.Links.Variables
            }
            elseif ($VariableSet -is [string] -and $VariableSet -match '^variableset-.*\d$') {
                    Write-Verbose "Getting variable set  with ID $VariableSet' ."
                    $VariableSet = Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint "variables/$VariableSet"
            }
            else   {throw 'That does not appear to be a valid variable set'}
        }
        #endregion
        if ($variableSet.count -gt 1) {
            throw "The details provided matched matched multiple variable sets"
        }

        $restParams     = @{Method ='Put'; EndPoint = $VariableSet.Links.Self}
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
                $NameHash[$IdNamePair.ID]= $IdNamePair.ID
            }
            $scopeNamesHash[$ScopeType] = $NameHash
            $scopeIDsHash[$ScopeType] = $IDHash
         }
         Write-Verbose "Variable set has the ID $($VariableSet.Id) and is owned by '$($VariableSet.OwnerId) and contained $($VariableSet.Variables.Count) variables at the start"
        #endregion
    }
    process {
        #if this variable isn't scoped, see if there is an existing variable to update, prepare to add it if not
        if (-not ($ScopeEnvironment -or $ScopeRole -or $ScopeChannel -or $ScopeMachine -or $ScopeAction -or $ScopeProcessOwner )) {
            $variableToUpdate = $VariableSet.Variables | Where-Object {$_.Name -eq $VariableName -and -not $_.Scope.psobject.Properties.count}
            #Sensitive values export as blank. No reimport blank over a sensitive value
            if ($variableToUpdate -and $variableToUpdate.value -ne $value -and -not ($Sensitive -and [string]::IsNullOrEmpty($value) ) ) {
                $variableToUpdate.Value = $Value
                $changes ++
                Write-Verbose "Change $changes. Update existing, unscoped variable '$VariableName' with internal ID $($variableToUpdate.Id). "
            }
            elseif ($variableToUpdate) {
                Write-Verbose "Unscoped variable '$VariableName' was not changed"
            }
            else {
                $changes ++
                Write-Verbose "Change $changes. Adding new unscoped variable '$VariableName'."
                $varsToAdd +=  [pscustomobject]@{Name = $VariableName; Value = $value; Type = $type; IsSensitive = ($Sensitive -as [bool]) }
            }
        }
        else { #we're scoped .

            #Allow 0 or  False  but not not "" or null
            if ([string]::IsNullOrEmpty($value) )  {
                $skipped++
                Write-Warning "Skipping '$VariableName' as its value is empty,"
            }
            else {
                $varScope = @{}
                $badScope = $false
                #region foreach of the scope-types, split strings at , or ; and look up the corresponding ID
                #The are 3 gotchas (1) the need to ensure the result is an array most of the time there will be one, and that's bad data to the API
                #By Design has lookups returns a null for a miss. So if $ScopeEnvironment is Dev, Prod" and the hash has "Development", "Production"
                #so (2) we need to stop $null,$null going into the results. Because ...(3) If we have scoped variables and (e.g.) environments
                #don't match we'll get multiple instances of the same unscoped variable
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
                }
            }
        }
    }
    end     {
        #at the end of process we have updated existing unscoped variables but not written back. We have new unscoped and all scoped in varstoAdd
        if ($varsToAdd.Count -gt 0) {
            # To avoid complexity if we have any instances of VarName with a scope, we will delete ALL existing scoped instances of it and add whats specified.
            # This means we can pipe in 2 or more scoped values for VarName, but if we run two commands to add the first and the second, the second will delete the first
            $varnamesToDelete = $varstoadd | Where-Object {$_.scope} | Select-Object -expand name | Sort-Object -unique
            if ($varnamesToDelete.Count -ge 1) {
                Write-Verbose "Scoped versions of $($varnamesToDelete -join ', ') will be replaced."
                $variableSet.Variables = $variableSet.Variables.Where( {$_.Name -notin $varnamesToDelete -or -not $_.Scope.psobject.Properties.count})
                Write-Verbose "Removed $($varsBefore - $VariableSet.Variables.Count) variable(s)."
            }
            $VariableSet.Variables += $varsToAdd
        }
        Write-Verbose "Updated variable set contains $($VariableSet.Variables.Count) variable(s), with $changes new value(s) and $skipped item(s) skipped."
        if ($changes -and ($Force -or $PSCmdlet.ShouldProcess($VariableSet.Id,"Apply $changes variable updates"))) {
             $result = Invoke-OctopusMethod @restParams -Item $VariableSet
             if ($Passthru) {$result}
        }
    }
}

function Remove-OctopusVariable             {
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName='Default')]
        $VariableSet,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        [Parameter(Mandatory=$true,Position=1,ValueFromPipelineByPropertyName)]
        [Alias('Name')]
        $VariableName,

        [switch]$Force
    )
    begin   {
        #region ensure we have the variables and scopes (not their parent or the ID for them) before we proceed
        #We may have been given the name or the ID for a project or for a library variable set.
        if         ($Project)            {$VariableSet = Get-OctopusProject             -Variables  -Project $Project }
        elseif     ($LibraryVariableSet) {$VariableSet = Get-OctopusLibraryVariableSet  -Variables -LibraryVariableSet $LibraryVariableSet}
        #If not we may we got the parent of the set object or its ID,
        if  ( -not ($VariableSet.id  -and $VariableSet.OwnerId -and $VariableSet.ScopeValues -and $VariableSet.Variables)) {
            if     ($VariableSet.Links.Variables) {
                    Write-Verbose "Getting variable set for '$($VariableSet.Name)'', ($($VariableSet.Id))."
                    $VariableSet = Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint $VariableSet.Links.Variables
            }
            elseif ($VariableSet -is [string] -and $VariableSet -match '^variableset-.*\d$') {
                    Write-Verbose "Getting variable set  with ID $VariableSet' ."
                    $VariableSet = Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint "variables/$VariableSet"
            }
            else   {throw 'That does not appear to be a valid variable set'}
        }
        #endregion
        if ($variableSet.count -gt 1) {
            throw "The details provided matched matched multiple variable sets"
        }
        $restParams  = @{Method ='Put'; EndPoint = $variableSet.Links.Self}
        $intialCount = $variableSet.Variables.count
    }
    process {
        if ($VariableName.name) {$VariableName=$VariableName.name}
        $variableSet.Variables = $variableSet.Variables.where({$_.Name -notlike $VariableName})
    }
    end     {
        $removedCount = $intialCount - $variableSet.Variables.count
        if ($removedCount -and ($Force -or $PSCmdlet.ShouldProcess($variableSet.Id,"Remove $removedCount variables"))) {
            $result = Invoke-OctopusMethod @RestParams -Item $variableSet
            if ($Passthru) {$result}
        }
    }
}

function New-OctopusLibraryVariableSet      {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $Name,
        $Description
    )
    process {
        foreach ($n in $name) {
            $item = @{Name=$n}
            if ($Description) {$item['Description']= $Description}
            if ($PSCmdlet.ShouldProcess($name,'Add Octopus Library Variable Set')) {
                Invoke-OctopusMethod -PSType OctopusLibraryVariableSet -Method Post -EndPoint 'libraryvariablesets' -Item $item
            }
        }
    }
}

function Expand-OctopusVariableSet          {
<#
    .example
         Get-OctopusProject 'Hello World' -Variables | Expand-OctopusVariableSet
    .example
        Get-OctopusLibraryVariableSet Public -Variables | Expand-OctopusVariableSet
     .example
        Get-OctopusLibraryVariableSet Public -Variables | Expand-OctopusVariableSet
    .example
        Get-OctopusProject | Get-OctopusProject -Variables | Expand-OctopusVariableSet -Destination varexport.xlsx

#>
    [Alias('Export-OctopusVariableSet')]
    [CmdletBinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ParameterSetName='Default',ValueFromPipeline=$true)]
        $VariableSet,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        $Destination,
        [switch]$GridView
    )
    begin   {
        if           ($Destination -and -not (Test-Path -IsValid -PathType Leaf $Destination)) {
                throw " '$Destination' is a valid filepath."
        }
        elseif       ($Destination -match    '\.xlsx$' -and (-not (Get-Command Export-Excel -ErrorAction SilentlyContinue ))) {
                    throw 'xlsx export requires the import Excel module, which was not found, use Install-Module  importexcel to add it.'
        }
        elseif       ($Destination -notmatch '\.xlsx$|\.csv$|') {
                      throw "Destination needs to be a .csv file, or a .xlsx file if the ImportExcel module is installed"
        }
        if           ($Project)                     {$VariableSet = Get-OctopusProject             -Variables  -Project $Project }
        elseif       ($LibraryVariableSet)          {$VariableSet = Get-OctopusLibraryVariableSet  -Variables -LibraryVariableSet $LibraryVariableSet}
    }
    process {
        if (-not     ($VariableSet.Variables    -and $VariableSet.OwnerId -and $VariableSet.ScopeValues)) {
            if       ($VariableSet -is [string] -and $VariableSet -match '^variableset-.*\d$') {
                                                     $VariableSet = Get-OctopusLibraryVariableSet $variableSet -Variables}
            elseif   ($VariableSet.Links.Variables) {$VariableSet = Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint $variableSet.Links.Variables}
            else     {throw "Invalid object passed as a variable set "}
        }

        #id will look like Objects-1234 and the endpoint will be Objects/Objects-1234 make that with a regex.
        $OwnerName      =  (Invoke-OctopusMethod ($variableset.ownerid  -replace "^(.*)(-\d+)$",'$1/$1$2')).name

        #region For different kinds of scope (environments, roles, etc). we need to swap ID <--> name
        #So build two hashes with scope-Kind as keys and values of hash tables which map one way or the other
        $scopeNamesHash = @{}
        $scopeIDsHash   = @{}
        foreach ($ScopeType in $VariableSet.ScopeValues.psobject.Properties.Name) {
            $IDHash     = @{}
            $NameHash   = @{}
            foreach ($IdNamePair in $VariableSet.ScopeValues.$scopeType) {
                $IDHash[$IdNamePair.id]     = $IdNamePair.Name
                #What if we get asked to find the ID for an ID? As well as name-->ID, ensure we have ID-->ID
                $NameHash[$IdNamePair.Name] = $IdNamePair.ID
                $NameHash[$IdNamePair.ID]   = $IdNamePair.ID
            }
            $scopeNamesHash[$ScopeType]     = $NameHash
            $scopeIDsHash[$ScopeType]       = $IDHash
        }
        #endregion
        foreach ($v in $VariableSet.Variables) {
            Add-Member       -Force -InputObject $v -NotePropertyName SetId             -NotePropertyValue  $VariableSet.id
            Add-Member       -Force -InputObject $v -NotePropertyName SetOwnerId        -NotePropertyValue  $VariableSet.OwnerId
            Add-Member       -Force -InputObject $v -NotePropertyName SetOwnerType      -NotePropertyValue ($VariableSet.OwnerId -replace '-\d*$')
            Add-Member       -Force -InputObject $v -NotePropertyName SetOwnerName      -NotePropertyValue  $OwnerName
            #region expand scopes
            $ExpandedScope = ''
            if   ($v.Scope.Environment) {
                  $scopeText = $scopeIDsHash.Environments[$v.Scope.Environment] -join '; '
                  $ExpandedScope += ' / Environment: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeEnvironment  -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeEnvironment  -NotePropertyValue  '' }
            if   ($v.Scope.Role) {
                  $scopeText = $scopeIDsHash.Roles[$v.Scope.Role] -join '; '
                  $ExpandedScope += ' / Role: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeRole         -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeRole         -NotePropertyValue  '' }
            if   ($v.Scope.Machine) {
                  $scopeText = $scopeIDsHash.Machines[$v.Scope.Machine] -join '; '
                  $ExpandedScope += ' / Machine: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeMachine      -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeMachine      -NotePropertyValue  '' }
            if   ($v.Scope.ProcessOwner) {
                  $scopeText = $scopeIDsHash.Processes[$v.Scope.ProcessOwner] -join '; '
                  $ExpandedScope += ' / ProcesOwner: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeProcessOwner -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeProcessOwner -NotePropertyValue  '' }
            if   ($v.Scope.Action) {
                  $scopeText = $scopeIDsHash.Actions[$v.Scope.Action] -join '; '
                  $ExpandedScope += ' / Action: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeAction       -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeAction       -NotePropertyValue  '' }
            if   ($v.Scope.Channel) {
                  $scopeText = $scopeIDsHash.Channels[$v.Scope.Channel] -join '; '
                  $ExpandedScope += ' / Channel: ' + $scopeText
                  Add-Member -Force -InputObject $v -NotePropertyName ScopeChannel      -NotePropertyValue $scopeText
            }
            else {Add-Member -Force -InputObject $v -NotePropertyName ScopeChannel      -NotePropertyValue  '' }
            Add-Member       -Force -InputObject $v -NotePropertyName ExpandedScope     -NotePropertyValue ($ExpandedScope -replace '^ / ','')
            #endregion
        }
        $result     =  $VariableSet.Variables | Select-Object -Property * -ExcludeProperty Scope |  Sort-Object Name,ExpandedScope | ForEach-Object {
            $_.pstypenames.add('OctopusVariable')
            $_
        }
        if  ($Destination -is  [scriptblock]) { #re-create the script block otherwise variables from this function are out of scope.
                $destPath = & ([scriptblock]::create( $Destination ))
        }
        elseif ($Destination ) {$destPath = $Destination }
        if     ($destPath -match '\.csv$') {
                                $result | Export-Csv   -Path $destPath -NoTypeInformation
        }
        elseif ($destPath)     {$result | Export-Excel -Path $destPath -WorksheetName $OwnerName -TableStyle Medium6 -Autosize }
        elseif ($GridView)     {$result | Out-GridView -Title           "Variables in $OwnerName"}
        else                   {$result}
    }
}

function Import-OctopusVariableSetFromCSV   {
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $Path,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project
    )
    process {
        Import-Csv -Path $Path | ForEach-Object {if ($_.isSensitive -is [string]) {$_.isSensitive = $_.isSensitive -eq 'true'} ; $_}  |
             Group-Object -Property SetId, SetOwnerName  |  ForEach-Object {
                #region Get the variable set, by name because can't trust having a valid ID (e.g. multiple instances involved.)
                if     (-not $LibraryVariableSet -and ($Project -or  $_.name -match '^Project')) {
                     if ($Project) {$VariableSet = Get-OctopusProject  -variables -Project $Project }
                     else          {$VariableSet = Get-OctopusProject  -variables -Project $_.group[0].SetOwnerName}
                }
                else   {
                    if      ($LibraryVariableSet) {
                                    $VariableSet = Get-OctopusLibraryVariableSet -variables -LibraryVariableSet $LibraryVariableSet
                                    if (-not $VariableSet ) {$VariableSet = New-OctopusLibraryVariableSet -Name $LibraryVariableSet}
                    }
                    else {
                                    $VariableSet = Get-OctopusLibraryVariableSet -variables -LibraryVariableSet $_.group[0].SetOwnerName
                                    if (-not $VariableSet ) {$VariableSet = New-OctopusLibraryVariableSet -Name $_.group[0].SetOwnerName}
                    }
                }
                if     (-not $VariableSet) {throw "Could not get the a variable set from the parameters and data file provided."}
                #endregion

                Write-Verbose "Updating VariableSet '$($VariableSet.ID)' from '$Path'"
                $_.group | Set-OctopusVariableSetMember -VariableSet $VariableSet
            }
    }
}

function Import-OctopusVariableSetFromXLSX  {
    [cmdletbinding(DefaultParameterSetName='Default',SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        $Path ,

        [Parameter(Position=1)]
        $workSheetName  = '*',

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Library')]
        $LibraryVariableSet,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,ParameterSetName='Project')]
        $Project,

        [Switch]$NoArtifact
    )
    if (-not (Get-command Import-Excel)) {
        throw "To import a .XLSX file you need the importExcel Module ( install-Module importexcel)"
    }
    $excel           = Open-ExcelPackage -Path $Path -ErrorAction stop
    $sheetsProcessed = @()
    foreach ($ws in $excel.Workbook.Worksheets.Where({$_.Name -like $workSheetName -and $_.name -notmatch '-Before$|-After$' } )) {
        #keep track of what's imported, and make sure if we do multiple sheets we don't acccidentally re-use a variable set
        $sheetsProcessed += $ws.name
        if ($excel.Workbook.Worksheets.Where({$_.Name -eq ($ws.name + '-Before') } )) {
            $excel.Workbook.Worksheets.Delete(($ws.name + '-Before'))
        }
        if ($excel.Workbook.Worksheets.Where({$_.Name -eq ($ws.name + '-After') } )) {
            $excel.Workbook.Worksheets.Delete(($ws.name + '-After'))
        }
        $VariableSet      = $null
        Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Reading data"
        #Import the sheet, ensuring sensitivity is a boolean. To allow one sheet to update multiple things group by the destination and import each group
        Import-Excel -ExcelPackage $Excel -WorksheetName $ws.Name |
            ForEach-Object  {if ($_.isSensitive -is [string]) {$_.isSensitive = $_.isSensitive -eq 'true'} ; $_} |
              Group-Object -Property SetOwnerType, SetOwnerName | ForEach-Object {
                #region Get the variable set, by name because can't trust having a valid ID (e.g. multiple instances involved.) If we're making an artifact export the 'before' state.
                if  (-not $LibraryVariableSet -and ($Project -or  $_.name -match '^Project')) {
                    if ($Project)  {$VariableSet = Get-OctopusProject  -variables -Project $Project }
                    else           {$VariableSet = Get-OctopusProject  -variables -Project $_.group[0].SetOwnerName}
                }
                else {
                    if ($LibraryVariableSet) {
                                    $VariableSet = Get-OctopusLibraryVariableSet -variables -LibraryVariableSet $LibraryVariableSet
                                    if (-not $VariableSet ) {$VariableSet = New-OctopusLibraryVariableSet -Name $LibraryVariableSet}
                    }
                    else {
                                    $VariableSet = Get-OctopusLibraryVariableSet -variables -LibraryVariableSet $_.group[0].SetOwnerName
                                    if (-not $VariableSet ) {$VariableSet = New-OctopusLibraryVariableSet -Name $_.group[0].SetOwnerName}
                    }
                }
                if     (-not $VariableSet) {
                    throw "Could not get the a variable set from the parameters and data file provided."
                }
                elseif (-not $NoArtifact) {
                    Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Writing 'before' snapshot for '$($VariableSet.OwnerId)'"
                     $varsbefore = Expand-OctopusVariableSet $VariableSet |  Select-Object Id,Name,Type,Scope,IsSensitive,Value
                     $excel =    $varsbefore | Export-excel -WorksheetName ($ws.name + "-Before") -BoldTopRow -FreezeTopRow -AutoSize -Append -ExcelPackage $excel -PassThru
                }
                #endregion
                Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Updating VariableSet for '$($VariableSet.OwnerId)'"
                Write-Verbose "Updating VariableSet '$($VariableSet.ID)' from worksheet '$($ws.name)'"
                $result = $_.group | Set-OctopusVariableSetMember -VariableSet $VariableSet -PassThru
                if (-not $result) {Write-Warning "--NO UPDATES WERE MADE--"}
                #region If we're making an artifact export the 'After' state
                if (-not $NoArtifact) {
                    if ($result) {$varsafter =  Expand-OctopusVariableSet $result |Select-Object Id,Name,Type,Scope,IsSensitive,Value }
                    else         {$varsafter = $varsBefore}
                    Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Writing 'after' snapshot for '$($VariableSet.OwnerId)'"
                    $excel =      $varsafter | Export-excel -WorksheetName ($ws.name + "-After" ) -BoldTopRow -FreezeTopRow -AutoSize -Append -ExcelPackage $excel -PassThru
                }
                #endregion
            }
    }
    #Save the Changes we've made to the excel file - compare-worksheet (if run) wants the file to be closed, it will open compare each before and after, markup changes and save.
    Close-ExcelPackage $excel
    if (-not $NoArtifact) {
        foreach ($wsname in $sheetsProcessed) {
             Write-Progress -Activity "Importing from worksheet $($ws.name)" -Status "Comparing 'before' and 'after'."
             $null = Compare-Worksheet -Referencefile $path -Differencefile $Path  -WorkSheetName "$wsName-Before","$wsName-After" -Key "id" -BackgroundColor lightgreen
        }
        if ((Get-Command New-OctopusArtifact -ErrorAction SilentlyContinue )) {New-OctopusArtifact $Path}
        else {Write-warning "$Path has been updated, but could not be sent to Octopus find command 'New-OctopusArtifact' " }
    }
    Write-Progress -Activity "Importing from worksheet $($ws.name)" -Completed
}

