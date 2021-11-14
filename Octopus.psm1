[Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
#sCreate an xml file (only decodable by you on the same computer) in your powershell-profile directory with
# Get-Credential -Message "URI as username, API Key as password" | Export-Clixml (Join-path (split-path $profile) "Octopus.xml")

if (Test-Path "$PSScriptRoot\Private" -PathType Container) {
    Get-ChildItem "$PSScriptRoot\Private\*.ps1" | ForEach-Object {. $_.FullName}
}
if (Test-Path "$PSScriptRoot\Public"  -PathType Container) {
    Get-ChildItem "$PSScriptRoot\Public\*.ps1"  | ForEach-Object {. $_.FullName}
}

#region if  credentials are available, and try to logon if current session is using different creds to the file, prefer those).
if        ($profile) {$credfile = Join-path (split-path $profile) "Octopus.xml"}  # profile isn't there in a remote ps session.
if        ($env:OctopusUrl -and $env:OctopusApiKey -and (Test-path Env:\OctopusSpaceID) ) {
           $logonResult = Connect-Octopus -OctopusUrl $env:OctopusUrl -OctopusApiKey $env:OctopusApiKey -space:$env:OctopusSpaceID
}
elseif    ($env:OctopusUrl -and $env:OctopusApiKey ) {
           $logonResult = Connect-Octopus -OctopusUrl $env:OctopusUrl -OctopusApiKey $env:OctopusApiKey
}
elseif    ($credfile       -and (Test-Path $credfile)) {
    if    (Test-path Env:\OctopusSpaceID) {
           $logonResult = Connect-Octopus -Credential (Import-Clixml $credfile) -Space $env:OctopusSpaceID
    }
    else { $logonResult = Connect-Octopus -Credential (Import-Clixml $credfile) }
}
else      {$logonResult =  "Ready for Connect-Octopus."}
Write-Host $logonResult
#endregion
