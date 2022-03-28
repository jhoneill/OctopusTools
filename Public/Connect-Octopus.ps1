function Connect-Octopus                    {
<#
    .SYNOPSIS
        Sets variables holding the Server and API key, confirms the space (if used), and flags whether RunBooks are available.

    .PARAMETER OctopusUrl
        The URL of the Octopus Deploy server, without the "/API/etc" to use for the rest of the session.

    .PARAMETER OctopusApiKey
        The Octopus Deploy API Key, this will become available to commands run for the rest of the session.

    .PARAMETER SpaceName
        The Octopus Space, if the server supports them.
        If no Space name is given but the server supports Spaces, "Default" will be  used as the name.

    .PARAMETER StatusOnly
        If specified, reports connection information without changing it

    .EXAMPLE
        C:> Connect-Octopus -OctopusUrl $env:OctopusUrl -OctopusApiKey $env:OctopusApiKey -Verbose
        [re]connects with credentials held in environment variables, and provides information about the
        server version. If this is the first logon of the PowerShell session and the server supports
        spaces, the connection will use the space named 'default',

    .EXAMPLE
        C:> $null = Connect-Octopus -space nasa
        Connects to a nominated space and discards the status message.

    .EXAMPLE
        C:> (Connect-Octopus -StatusOnly) -replace "^.*?'(.*)'\.$", '$1'
        Extracts the user name from the status message.
#>
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(Position=0,ParameterSetName='Default',   Mandatory=$true)]
        [Parameter(Position=0,ParameterSetName='SpaceURLKey',Mandatory=$true)]
        $OctopusUrl ,

        [Parameter(Position=1,ParameterSetName='Default',    Mandatory=$true)]
        [Parameter(Position=1,ParameterSetName='SpaceURLKey',Mandatory=$true)]
        $OctopusApiKey,

        [Parameter(ParameterSetName='Cred',Mandatory=$true)]
        [pscredential]
        $Credential,

        [Parameter(ParameterSetName='Cred')]
        [Parameter(ParameterSetName='SpaceOnly')]
        [Parameter(ParameterSetName='SpaceURLKey')]
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Space  =  'Default',

        [Parameter(ParameterSetName='Status',Mandatory=$true)]
        [switch]$StatusOnly
    )
    if       ($StatusOnly) {Write-Verbose "Checking the connection, but not updating it."}
    elseif   ($Credential) {
              $env:OctopusApiKey = $OctopusApiKey = $Credential.GetNetworkCredential().Password
              if ($Credential.userName -Match "^https?://") {$env:OctopusUrl = $OctopusUrl = $Credential.userName }
              else                                          {$env:OctopusUrl = $OctopusUrl = "http://$($Credential.userName )"}
              $OctopusApiInformation  = Invoke-OctopusMethod -EndPoint 'api' -spaceId $null -APIKey $OctopusApiKey -OctopusUrl $OctopusUrl -ErrorAction stop -Verbose:$False
    }
    elseif   ($OctopusApiKey -and $OctopusUrl ) {
              $OctopusApiInformation  = Invoke-OctopusMethod -EndPoint 'api' -spaceId $null -APIKey $OctopusApiKey -OctopusUrl $OctopusUrl -ErrorAction stop -Verbose:$False
              $env:OctopusUrl         = $OctopusUrl -replace '/$',""
              $env:OctopusApiKey      = $OctopusApiKey
    }
    elseif   ((-not $OctopusApiKey -and -not $env:OctopusApiKey )-or (-not $OctopusUrl -and -not $env:OctopusUrl)) {
              Write-Warning "OctopusApiKey and OctopusUrl must either be passed as parameters or set as environment variables"
              return
    }
    else     {
              $OctopusApiInformation  = Invoke-OctopusMethod -EndPoint 'api' -spaceId $null -ErrorAction stop -Verbose:$False
    }
    $splitVersion                     = $OctopusApiInformation.Version -split '\.'
    $majorVersion                     = [int]$splitVersion[0]
    $minorVersion                     = [int]$splitVersion[1]
    if   ($majorVersion -lt 2019) {
                if ($PSBoundParameters.('Space')) {
                      Write-Warning "-Space ignored: this version of Octopus ($majorVersion.$minorVersion) does not have spaces or runbooks."
                      $space = $null
                }
                else {Write-Verbose                 "This version of Octopus ($majorVersion.$minorVersion) does not have spaces or runbooks."}
                $script:HasRunbooks   = $false
                $env:OctopusSpaceID   = $null
    }
    else {
        if ( ($script:HasRunbooks = ($majorVersion -eq 2019 -and $minorVersion -ge 11) -or $majorVersion -ge 2020)) {
                Write-Verbose "This version of Octopus ($majorVersion.$minorVersion) supports both spaces and runbooks."
        }
        else  {
                Write-Verbose "This version of Octopus ($majorVersion.$minorVersion) supports spaces but not runbooks."
        }
        if ((-not $StatusOnly) -and $Space) {
                $env:OctopusSpaceID   = (Get-OctopusSpace $Space -Verbose:$false).id
                if ($env:OctopusSpaceID)  { Write-Verbose "The ID for space '$Space' is $env:OctopusSpaceID."}
                else                      {throw "Unable to find a space ID for '$Space' on $OctopusUrl"}
        }
    }
    $me = Invoke-OctopusMethod -EndPoint 'users/me' -SpaceId $null -Verbose:$false
    "Using the Octopus Deploy server at $env:OctopusUrl/$env:OctopusSpaceID with API key for user '$($me.displayname)'."
}
