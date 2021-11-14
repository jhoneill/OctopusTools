param(
        $OctopusApiKey ,
        $OctopusUrl    ,
        $SpaceName     =  'Default'
)
Import-Module "$PSScriptRoot\OctopusTools.psd1"

if ($OctopusApiKey -and $OctopusUrl) {
    Connect-Octopus @PSBoundParameters
    Get-OctopusActionTemplate -Custom | Format-Table

    Import-OctopusVariableSetFromXLSX -Path "$PSScriptRoot\PubVars.xlsx" -workSheetName sheet1
}
else {
    Write-Host "-------------------------------------"
    Get-ChildItem variable:\oct* | Format-Table Name,Value
    Write-Host "-------------------------------------"
    Get-ChildItem env:\oct* | Format-Table Name,Value
    Write-Host "-------------------------------------"
    $OctopusParameters
    Write-Host "-------------------------------------"
}
