function Resolve-VariableSet {
    param (
        $Project,
        $LibraryVariableSet,
        $VariableSet
    )
    #ensure we have the variables and scopes (not their parent or the ID for them) before we proceed
    #We may have been given the name or the ID for a project or for a library variable set.
    if         ($VariableSet.id  -and $VariableSet.OwnerId -and  $VariableSet.Variables) {
                return $VariableSet
    }
    elseif     ($Project -and $Project.Variables )                       {$Project.Variables() }
    elseif     ($Project)                                                {Get-OctopusProject            -Variables -Project $Project }
    elseif     ($LibraryVariableSet -and $LibraryVariableSet.Variables)  {$LibraryVariableSet.Variables()}
    elseif     ($LibraryVariableSet)                                     {Get-OctopusLibraryVariableSet  -Variables -LibraryVariableSet $LibraryVariableSet}
    elseif     ($VariableSet -is [string] -and $VariableSet -match '^variableset-.*\d$') {
                Write-Verbose "Getting variable set  with ID $VariableSet' ."
                Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint "variables/$VariableSet"
    }
    elseif     ($VariableSet -and (Get-Member -InputObject $VariableSet -MemberType ScriptMethod -Name variables)) {
                $VariableSet.Variables()
    }
    elseif     ($VariableSet.Links.Variables) {
                Write-Verbose "Getting variable set for '$($VariableSet.Name)'', ($($VariableSet.Id))."
                Invoke-OctopusMethod -PSType OctopusVariableSet -EndPoint $VariableSet.Links.Variables
    }

}
