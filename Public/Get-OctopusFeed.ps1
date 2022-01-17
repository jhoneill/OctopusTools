function Get-OctopusFeed                    {
    <#
      .SYNOPSIS
        Gets Octopus pacakge feeds, and optionally information about their packages, or searches within a feed.

    .DESCRIPTION
        Returns Built-in and external package feeds.
        If a feed and search term are specified, searches the feed for packages with that term
        If a feed is specified with -Package list returns a summary of the package infomation

    .PARAMETER Feed
        The name or ID of a feed to search for.

    .PARAMETER SearchTerm
        If specified returns packages matching the term.

    .PARAMETER PackageList
        If specified gets the package list for the selected feed(s)

    .EXAMPLE
        ps > Get-OctopusFeed
        Returns the list of available package-feeds

    .EXAMPLE
        ps > Get-OctopusFeed -Feed 'AzureDevOps','Octopus Server (built-in)' -PackageList
        Gets a list of packages available on two feeds

    .NOTES
    General notes
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default', Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Search',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='List',    Mandatory=$false, Position=0, ValueFromPipeline=$true)]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Alias('Id','Name')]
        $Feed,

        [Parameter(ParameterSetName='Search',  Mandatory=$true,  Position=1 ,ValueFromPipelineByPropertyName=$true)]
        $SearchTerm,

        [Parameter(ParameterSetName='List',    Mandatory=$true,  ValueFromPipelineByPropertyName=$true)]
        [switch]$PackageList
    )
    process {
        $item = Get-Octopus -Kind Feed -Key $Feed -ExtraId FeedID
        if     (-not $item)   {return}
        elseif ($SearchTerm)  {$item | ForEach-Object {$_.search($searchTerm)} }
        elseif ($PackageList) {$item | ForEach-Object {$_.PackageList()} }
        else                  {$item}
        }
}
