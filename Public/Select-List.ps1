function Select-List {
<#
  .SYNOPSIS
    Returns one or object selected by the user from a table of numbered rows.

  .DESCRIPTION
    Takes a collection of objects and the list of properties to be displayed.
    This is used to show a table with numbered rows.
    The user is prompted to make either a single or multiple choice, by row
    numbers and the selected objects are returned.

.PARAMETER InputObject
        An array of objects which provide the data for the selection list.
        The data returned comes from this parameter as well.
        If a single item is provided, it is returned without showing the list.

.PARAMETER Property
        One or more property names used to format the selection list, defaults to "Name"

.PARAMETER multiple
    Specifies that multiple items can be selected.

.EXAMPLE
    C:> dir *.ps1 | select-list -Property name
    Displays a list of files and asks the user to select one.

.EXAMPLE
    C:> get-service | select-list  -multiple -Prompt "Stop which services ?" | Stop-Service
    Displays a list of services and asks the user to Select services to stop and will accept multiple numbers (separated with , ; or space), and ranges in the form 10..12
#>
    param   (
        [Parameter(Mandatory=$true  ,valueFromPipeline=$true )]
        $InputObject,

        $Property = @("Name"),
        [string]$Prompt,
        [switch]$Multiple
    )
    begin   { $i= @()  }
    process { $i += $inputobject  }
    end     {
        if   ($i.count -eq 1) {$i[0]}
        else {
            $Global:counter=-1
            $Property=@(@{Label="ID"; Expression={ ($global:Counter++) }}) + $Property
            Format-Table -InputObject $i -AutoSize -Property $Property | Out-Host
            if         ($Multiple) {            # allow , ; or space as a separator and 1..10 for sequences
                if    (-not $Prompt) {$Prompt = "Which one(s) ?"}
                do    {     $response = Read-Host -Prompt $Prompt}
                while (     $response -match "[^.\s\d;,]")
            }
            else       {                        # allow only digits
                if    (-not $Prompt) {$Prompt = "Which one ?"}
                do    {     $response = Read-Host -Prompt $Prompt}
                while (     $response -match "\D")
            }
            if         (    $response -gt "") { # allow empty for "select none"
                while  (    $response-match "(\d+)\.\.(\d+)") {
                            $response = $response -replace ([regex]::Escape($Matches[0])),  ($matches[1]..$matches[2] -join ",")
                }
                $i[ [int[]]($response.trim() -Split "\D+")]
            }
        }
    }
}
