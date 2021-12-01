function Get-OctopusFeed                    {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Search',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Feed,
        [Parameter(ParameterSetName='Search',  Mandatory=$true, Position=1 ,ValueFromPipelineByPropertyName=$true)]
        $SearchTerm
    )
    process {
        $item = Get-Octopus -Kind Feed -Key $Feed -ExtraId FeedID
        if ($SearchTerm) {$item.search($searchTerm)}
        else             {$item}
    }
}

function New-OctopusNugetFeed               {
    [cmdletbinding(SupportsShouldProcess=$true)]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', '', Justification = "Will be sent as plain text")]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        $Name,
        [Parameter(Mandatory=$true,Position=1)]
        [Alias('URI')]
        $FeedURI,
        [Parameter(Mandatory=$false,Position=2)]
        [string]$Username,
        [Parameter(Mandatory=$false,Position=3)]
        $Password,
        $MaxAttempts    = 5,
        $BackoffSeconds = 10,
        [switch]$ExtendedApi,
        [switch]$Force
    )

    if (-not [System.Uri]::IsWellFormedUriString($FeedURI , [System.UriKind]::Absolute) ) {
        Write-Warning "'$FeedURI' does not look a valid URI"
    }

    $body = @{
            Id                            =  $null
            FeedType                      = 'NuGet'
            DownloadAttempts              =  $MaxAttempts
            DownloadRetryBackoffSeconds   =  $BackoffSeconds
            EnhancedMode                  = ($ExtendedApi -as [bool])
            Name                          =  $Name
            FeedUri                       =  $FeedURI}
    if     ($Username) {$body['Username'] =  $Username}
    if     ($Password -is [securestring]) {
                        $body['Password'] = @{HasValue=$true; NewValue=([pscredential]::new('x',$Password).GetNetworkCredential().Password) }
    }
    elseif ($Password) {$body['Password'] = @{HasValue=$true; NewValue=$Password} }

    if ($Force -or $PSCmdlet.ShouldProcess($Name,'Create new Nuget Feed')) {
        Invoke-OctopusMethod -PSType OctopusFeed -EndPoint feeds -Item $body -Method post
    }
}

#not sure if this should be named copy, publish, set, or send but docs call it push so ...
function Push-OctopusPackage                {
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(Mandatory=$true,position=1,ValueFromPipeline=$true)]
        $Path,
        #If force is specified, file will be over-written, version number issues will be ignored and any confirmation will be skipped
        [switch]$Force,
        $APIKey     = $env:OctopusApiKey,
        $OctopusUrl = $env:OctopusUrl,
        $SpaceId    = $env:OctopusSpaceID
    )
    begin   {# The invoke cmdlets don't work  for this so set up a System.Net.WebClient object and the URi it will use
        if (-not $ApiKey -or -not $OctopusUrl) {
            throw "The Octopus API and server URL must be passed as parameters or set in the environment variables 'OctopusApiKey' and 'OctopusUrl'."
        }
        $wc = New-Object System.Net.WebClient
        $OctopusUrl = $OctopusUrl -replace '/$',''
        if   ($SpaceId){$uri  =  "$OctopusUrl/api/$SpaceId/packages/raw?apikey=$APIKey" }
        else           {$uri  =  "$OctopusUrl/api/packages/raw?apikey=$APIKey" }
        if ($Force)    {$uri += '&replace=true'}
    }
    process {#Allowing path to be a piped in or a wildcard;
        if (-not (Test-Path $Path)) {Write-Warning "Could not find '$path'." ; return}
        foreach ($item in (Get-Item $path)) {
            if  ($item.name -notmatch '\d+\.\d+\.ZIP|\d+\.\d+\.nupkg' -and -not $Force) {
                Write-Warning "$($item.Name) does not look valid for a package (you can use the -Force switch to bypass this check)."
                continue
            }
            if  ($Force -or $PSCmdlet.ShouldProcess($item.Name,"Upload to $OctopusUrl/$SpaceId")) {
                trap {Write-Warning $error[0].exception.InnerException.Message; continue}
                $bytes  = $wc.UploadFile($uri, $item.FullName)
                if ($bytes) {
                    $result = convertFrom-json ([System.Text.Encoding]::ASCII.GetString($bytes))
                    $result.pstypenames.add('OctopusPackage')
                    $result
                }
            }
        }
    }
}
