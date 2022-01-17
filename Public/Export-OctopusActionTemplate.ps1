function Export-OctopusActionTemplate       {
<#
.SYNOPSIS
    Exports one or more custom action-templates

 .PARAMETER ActionTemplate
    One or more custom-templates either passed as an object or a name or template ID. Accepts input from the pipeline

.PARAMETER Destination
    The file name or directory to use to create the JSON file. If a directory is given the file name will be "tempaltename.Json". If nothing is specified the files will be output to the current directory.

.PARAMETER PassThru
    If specified the newly created files will be returned.

.PARAMETER Force
    By default the file will not be overwritten if it exists, specifying -Force ensures it will be.

.EXAMPLE
    ps > Export-OctopusActionTemplate  'Configure DNS' .\DNS.json -Force

    Exports a template, overwrtiing any existing file
#>
    param (
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        $ActionTemplate ,

        [Parameter(Position=1)]
        $Destination = $pwd,

        [Alias('PT')]
        [switch]$PassThru,

        [switch]$Force
    )
    process {
        foreach ($t in $ActionTemplate) {
            $baretemplate = Get-OctopusActionTemplate $t -Custom | Select-Object -Property export #export is a property set
            if ($baretemplate.count -gt 1) {
                Write-Warning "'$t' match more than one template, please try again or use 'Get-OctopusActionTemplate $t | Export-OctopusActionTemplate '."
            }
            $baretemplate.Parameters = $baretemplate.Parameters  | Select-Object -Property * -ExcludeProperty  id
            foreach ($p in $baretemplate.Packages) {$p.id=$null}

            if     (Test-Path $Destination -PathType Container )    {$DestPath = (Join-Path $Destination $baretemplate.Name) + '.json' }
            elseif (Test-Path $Destination -IsValid -PathType Leaf) {$DestPath = $Destination}
            else   {Write-Warning "Invalid destination" ;return}
            ConvertTo-Json $baretemplate -Depth 10 | Out-File $DestPath -NoClobber:(-not $Force)
            if     ($PassThru) {Get-Item $DestPath}
        }
    }
}
