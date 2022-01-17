function Get-OctopusPackage                 {
    <#
      .SYNOPSIS
        Gets details of octopus packages.

      .DESCRIPTION
        Gets packages from an external or built in feed built in feed.
        The command can get information about versions or the a specific version, and for items
        stored in a built in feed, it can download the item.

      .PARAMETER Package
        A package object or the package ID for one or more packages. If not specified all the packages for the selected feed will be returned

      .PARAMETER Feed
        The name, ID or object describing a feed. If none is specified the built in feed will be used.

      .PARAMETER AllVersions
        If specifed all returns all versions of the package which are available for download

      .PARAMETER Version
        A specific version for the package - if not specified the latest version is returned.

      .PARAMETER Destination
        Downloads the package to a to specified directory.

     .PARAMETER PassThru
        When used with Destination, returns the files which are downloaded

      .PARAMETER ProgressPreference
        Allows the Progress bar act differently in the function, specifying silentlyContinue will suppress it.

      .EXAMPLE
        ps > Get-OctopusPackage PowerShellScripts -AllVersions
        Gets details of all the version of the package named "PowerShellScripts" in the built-in feed.

      .EXAMPLE
        ps > Get-OctopusPackage PowerShellScripts -version  1.2* -Destination ~\Downloads
        Downloads matching versions of the named package to the current users Downloads Directory.

      .EXAMPLE
        ps > Get-OctopusPackage -Feed 'AzureDevOps'
        lists all packages available from an external feed.
    #>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OctopusPackageNamesCompleter])]
        [Parameter(ParameterSetName='Default',           Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Feed',              Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='AllVersions',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Version',           Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Download',          Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Name','ID','PackageID')]
        $Package,

        [ArgumentCompleter([OctopusGenericNamesCompleter])]
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
        [switch]$AllVersions,

        [ActionPreference]$ProgressPreference = $PSCmdlet.GetVariableValue('ProgressPreference')

    )
    process {
        if      ($Package.count -gt 1) {
                $null = $PSBoundParameters.Remove('Package')
                $Package | Get-OctopusPackage @PSBoundParameters
                return
        }
        if      ($Package.FeedID)               {$Feed = $Package.FeedID}
        elseif  ($Feed.id)                      {$Feed = $Feed.ID}
        elseif  ($Feed -is [string] -and
                 $Feed -notmatch '^feeds-\d+$') {$Feed = (Get-OctopusFeed $Feed).id }
        if      ($Feed.count -gt 1)    {
                Write-Warning 'The command does not support multiple feeds'
        }

        if      ($Package.PackageID) {$Package = $Package.PackageID}
        elseif  ($Package.ID)        {$Package = $Package.Id}

        if      ($Package -is [string] -and $Package -match '^packages-(?!Feeds-\d+-).*\.\d+$')  { #package is the ID for an internal package
                 $item = Invoke-OctopusMethod -PSType OctopusPackage -EndPoint "packages/$Package"
        }
        elseif ((-not $Feed) -or $Feed -match 'builtin')              { #package comes from the built-in feed or
                 if (-not $Package) {$Package = '*'}
                 $item = Invoke-OctopusMethod -PSType OctopusPackage -EndPoint packages -ExpandItems |
                     Where-Object {$_.packageID -like $Package}
        }
        elseif (($package -is [string] -or -not $Package))            { #package is from an external feed
                 if ($Destination)   {Write-Warning 'Only packages from the built in feed can be downloaded' ; return}
                 Write-Progress -Activity 'Getting Packages' -Status "Getting Information from Feed: $Feed"
                 $pkgs      = Invoke-OctopusMethod  -EndPoint "/feeds/$Feed/packages/search?term=$($Package -replace '\*$' ,'')&partialmatch=true"  -ExpandItems
                 $count     = 0
                 $item      = foreach ($p in $pkgs) {
                    Write-Progress -Activity 'Getting Packages' -Status "Getting Details of $($p.id)" -PercentComplete ($count/$pkgs.count)
                    Invoke-OctopusMethod -PSType OctopusPackage "/feeds/$Feed/packages/versions?packageid=$($p.id)&versionrange=$($p.latestversion)" -ExpandItems
                    $count += 100
                 }
                 Write-Progress -Activity 'Getting Packages' -Completed
        }
        else   {Write-Warning "Could not make sense of the supplied package and/or feed parameter"}

        if     (-not $item) {return}
        elseif ($Version -or $AllVersions) {
                if (-not $Version) {$Version = "*"}
                $item = $item | ForEach-Object AllVersions | Where-Object {$_.version -like $Version}
        }
        if     (-not $Destination) {return $item} #if we have a destination directory download the package
        elseif (-not (Test-path -PathType Container -Path $Destination)) { throw "$Destination is not a valid directory"}
        else {
            foreach ($i in $item) {
                $Outfile =  Join-Path (Resolve-Path $Destination) "$($i.PackageId).$($i.Version)$($i.FileExtension)"
                Invoke-OctopusMethod -EndPoint $i.Links.Raw -RawParams @{outfile = $Outfile}
                if ($PassThru) {Get-Item $outfile}
            }
        }
    }
}
