function Get-OctopusSpace                   {
<#
.SYNOPSIS
    Gets spaces, on versions of Octopus which support them

.PARAMETER Space
    The Space ID or name or ID to search for - wild cards are suported in the name, and names should tab-complete

.EXAMPLE
    C:> Get-Space Def*
    Returns the 'Default' space and any others starting D-E-F

.NOTES
General notes
#>
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Space
    )
    process {
        if (-not ((Invoke-OctopusMethod -EndPoint 'api' -spaceId $null).links.Spaces)) {
            Write-Error "This version of Octopus pre-dates spaces."
            return
        }
        if      ($Space.ID  ) {$Space = $Space.Id}
        elseif  ($Space.Name) {$Space = $Space.Name}
        if      ($Space -match '^Spaces-\d+$') {
                Invoke-OctopusMethod -PSType 'OctopusSpace' -EndPoint "spaces/$Space" -SpaceId $null
        }
        else    {
                Invoke-OctopusMethod -PSType 'OctopusSpace' -EndPoint spaces -ExpandItems -Name $Space -SpaceId $null | Sort-Object -Property name
        }
    }
}