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

function Get-OctopusPackage                 {
<##example fodder Get-OctopusPackage | ft *id,version,published
Get-OctopusPackage PowerShellScripts -AllVersions
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OptopusPackageNamesCompleter])]
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Feed',              Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='AllVersions',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Version',           Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Download',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Name','ID','PackageID')]
        $Package,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(ParameterSetName='Feed',              Mandatory=$true, Position=1)]
        $Feed,

        [Parameter(ParameterSetName='Download',          Mandatory=$false)]
        [Parameter(ParameterSetName='Feed',              Mandatory=$false)]
        [Parameter(ParameterSetName='Version',           Mandatory=$true)]
        $Version,

        [Parameter(ParameterSetName='Download',          Mandatory=$True,  Position= 2)]
        $Destination,

        [Parameter(ParameterSetName='Download',          Mandatory=$false)]
        [Alias('PT')]
        [switch]$PassThru,

        [Parameter(ParameterSetName='AllVersions',       Mandatory=$true)]
        [Parameter(ParameterSetName='Feed',              Mandatory=$false)]
        [switch]$AllVersions

    )
    process {
        if     ( $Package.FeedID  )  {$Feed    = $Package.FeedID}
        elseif ( $Feed.id)           {$Feed    = $Feed.ID}
        elseif ( $Feed -is [string] -and $feed -notmatch '^feeds-\d+$') {$Feed = (Get-OctopusFeed $Feed).id }

        if     ( $Package.ID  )      {$Package = $Package.Id}
        elseif ( $Package.PackageID) {$Package = $Package.PackageID}
        #the id for an internal feed is packages-PkgID.V.V.V ; for external it's packages-feeds-1234-PkgID.V.V.V
        if     ( $Package -match '^packages-(Feeds-\d+)-.*\.\d+$' -and -not $Feed)  { #Package is an ID with an external feed - save the feed.
                $Feed = $Matches[1]
        }

        if     ( $Package -match '^packages-(?!Feeds-\d+-).*\.\d+$')              { #package is the ID for an internal package
                $item = Invoke-OctopusMethod -PSType OctopusPackage -EndPoint "packages/$Package" |
                                Add-Member -PassThru -MemberType ScriptMethod -Name AllVersions -Value {Invoke-OctopusMethod -PSType OctopusPackage -EndPoint $this.Links.AllVersions -ExpandItems}
        }
        elseif ((-not $feed) -or $Feed -match 'builtin')                          { #package is a name in the built-in feed or blank
                $item = Invoke-OctopusMethod -PSType OctopusPackage -EndPoint packages -ExpandItems
                if ($Package) {
                    $item = $item.Where({$_.packageID -like $Package}) |
                                Add-Member -PassThru -MemberType ScriptMethod -Name AllVersions -Value {Invoke-OctopusMethod -PSType OctopusPackage -EndPoint $this.Links.AllVersions -ExpandItems}
                    }
        }
        elseif (($package -is [string] -or -not $Package) -and $Feed -and $Feed -notmatch 'builtin') { #package is in an external feed or blank
                # package is its it's packages-feeds-1234-PkgID.V.V.V  search for that package ID and version - we already have the feed ID
                if ($Package -match '^packages-Feeds-\d+-(.*?)\.([.\d]+)$') {
                     $item = Invoke-OctopusMethod -PSType OctopusPackage "/feeds/$Feed/packages/versions?packageid=$($Matches[1])&versionrange=$($Matches[2])" -ExpandItems |
                                Add-Member -PassThru -MemberType ScriptMethod -Name AllVersions -Value {Invoke-OctopusMethod -PSType OctopusPackage -EndPoint "/feeds/$($this.Feedid)/packages/versions?packageid=$($this.PackageID)" -ExpandItems}
                }
                else {
                    $Package = $Package -replace '\*$' ,''
                    $item = Invoke-OctopusMethod  -EndPoint "/feeds/$Feed/packages/search?term=$Package&partialmatch=true"  -ExpandItems | ForEach-Object {
                              Invoke-OctopusMethod -PSType OctopusPackage "/feeds/$Feed/packages/versions?packageid=$($_.id)&versionrange=$($_.latestversion)" -ExpandItems |
                                Add-Member -PassThru -MemberType ScriptMethod -Name AllVersions -Value {Invoke-OctopusMethod -PSType OctopusPackage -EndPoint "/feeds/$($this.Feedid)/packages/versions?packageid=$($this.PackageID)" -ExpandItems}
                    }
                }

        }
        else   {Write-Warning "Could not make sense of the supplied package and/or feed parameter"}

        if ($version -or $AllVersions) {
                $item = $item.allVersions()
                if ($version)  {$item = $item | Where-Object {$_.version -like $Version}}
        }
        if (-not $Destination) {return $item }
        else  { #if we have a destination directory download the package
            if (-not (Test-path -PathType Container -Path $Destination)) {
                throw "$Destination is not a valid directory"
            }
            else {
            ### xxxx todo not handling multiple items
                $Outfile =  Join-Path (Resolve-Path $Destination) "$($item.PackageId).$($item.Version)$($item.FileExtension)"
                Invoke-OctopusMethod -EndPoint $item.Links.Raw -RawParams @{outfile = $Outfile}
                if ($PassThru) {Get-Item $outfile}
            }
        }
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
