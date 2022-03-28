function Get-OctopusLibraryScriptModule     {
    <#
      .SYNOPSIS
        Gets script modules stored in the library.

      .DESCRIPTION
        Octopus stores script modules using library variable sets with their content type set to indicate they are modules
        This command returns the "holder" object or if the expand switch is used, expands the script itself.

      .PARAMETER ScriptModule
        Name of the module of interest

      .PARAMETER Expand
        If specifed with ScriptModule, expands the script stored from the variable set

      .EXAMPLE
        C:> Get-OctopusLibraryScriptModule 'DNSTools'
            Gets the libraray variable set object whcih holds the module named "DNSTtools"

      .EXAMPLE
        C:> Get-OctopusLibraryScriptModule  | foreach { (Get-OctopusLibraryScriptModule $_.name -Expand).'Octopus.Script.Module' > "$pwd\$($_.name).psm1"}
        Gets a list of all modules, and for each one calls the command again with the expand option,
        and writes the script out to a PSM1 file with the same name as the module
    #>

    [cmdletBinding(DefaultParameterSetName='Default')]
    [Alias('Get-OctopusScriptModule')]
    param   (
        [ArgumentCompleter([OptopusLibScriptModulesCompleter])]
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0, ValueFromPipeline=$true )]
        [Parameter(ParameterSetName='Expand',   Mandatory=$true,  Position=0, ValueFromPipeline=$true )]
        $ScriptModule,

        [Parameter(ParameterSetName='Expand',  Mandatory=$true,  ValueFromPipelineByPropertyName=$true )]
        [switch]$Expand
    )
    process {
        if ($ScriptModule) {
            $item = Get-Octopus -Kind libraryvariableset -Key $ScriptModule |
                    Where-Object ContentType -eq 'ScriptModule' | Sort-Object -Property name
        }
        else   {
            $item = Invoke-OctopusMethod -PSType "OctopusLibraryVariableSet" -EndPoint 'libraryvariablesets?contentType=ScriptModule' -ExpandItems
        }
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
