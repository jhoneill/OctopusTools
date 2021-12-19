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

function Remove-OctopusVariable             {
    <#
      .SYNOPSIS
        Removes one or more Octopus variables in a library or project variable set

    .PARAMETER VariableSet
        A variable set object or the ID of a variable set object. If specfied no libraryVariableSet or Project parameter is used.

    .PARAMETER LibraryVariableSet
        The library entry whose variable set should be used. If specfied no VariableSet  or Project parameter is used.

    .PARAMETER Project
        The Project whose variable set should be used be If specfied no VariableSet  or libraryVariableSet parameter is used.

    .PARAMETER VariableName
        The name of the variable to be deleted

    .PARAMETER Force
        Supresses any confirmation prompts

#>
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

        [Parameter(Mandatory=$true,Position=1,ValueFromPipeline=$true)]
        [Alias('Name')]
        $VariableName,

        [switch]$Force
    )
    begin   {
        $VariableSet = Resolve-VariableSet -Project $Project -LibraryVariableSet $LibraryVariableSet -VariableSet $VariableSet
        if (-not $VariableSet -or $VariableSet.count -gt 1) {throw "Could not get a unique variable set from the parameters provided"; return }
        else {
            $restParams  = @{Method ='Put'; EndPoint = $variableSet.Links.Self; PSType='OctopusVariableSet'}
            $intialCount = $VariableSet.Variables.count
        }
    }
    process {
        foreach ($v in $VariableName ) {
            if ($v.name) {$v=$v.name}
            $variableSet.Variables = $variableSet.Variables.where({$_.Name -notlike $v})
        }
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
