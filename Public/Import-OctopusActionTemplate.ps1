function Import-OctopusActionTemplate       {
<#
.SYNOPSIS
    Imports an action template from a file (or a handy block of JSON text you may have)

.DESCRIPTION
    This command does some basic checks that it has been given parsable JSON and that the file at
    least has a name and an action type, and checks that the template does not already exist.

.PARAMETER Path
    The path to a JSON file it can be a wildcard that matches ONE file; multiple files can be piped into the command

.PARAMETER JsonText
    Instead of getting the text from a file accepts it as a string (or array of strings)

.PARAMETER Force
    Supresses any confirmation message. By default the command prompts for confirmation before importing.

.EXAMPLE
    C:> dir *.json | import-OctopusActionTemplate -force
    Attempts to import all JSON files in the current directory as action templates without prompting for confirmation

#>
[cmdletbinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default',ConfirmImpact='High')]
param (
    [Parameter(Position=0,ValueFromPipeline=$true,Mandatory=$true,ParameterSetName='Default')]
    $Path,
    [Parameter(Mandatory=$true,ParameterSetName='AsText')]
    $JsonText,
    [switch]$Force
)
    process {
        if (-not $JsonText) {
            $r = (Resolve-Path $Path)
            if     (-not $r)        {Write-Warning "Could not find $Path" ; return}
            elseif ($r.count -gt 1) {Write-Warning   "$Path matches more than one file." ; return}
            else                    {$JsonText = Get-Content -Raw $Path}
        }
        if ($JsonText -is [array]) {
            $JsonText= $JsonText -join [System.Environment]::NewLine
        }
        try   {$j =  ConvertFrom-Json -InputObject $JsonText -Depth 10}
        catch {Write-warning 'That does not appear to be valid JSON ' ;return }
        if (-not ($j.ActionType -and $j.Name )) {
               Write-warning 'The file parses as JSON but does not appear to be an action template  ' ;return
        }
        elseif (Get-OctopusActionTemplate -custom $j.Name) {
               Write-warning "A custom action template named '$($j.name)' already exists." ;return
        }
        elseif ($Force -or $pscmdlet.ShouldProcess($j.Name,'Import template')) {
                Invoke-OctopusMethod -PSType OctopusActionTemplate  -Method Post -EndPoint actiontemplates -JSONBody $JsonText
        }
    }
}
