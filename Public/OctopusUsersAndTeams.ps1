
function Get-OctopusTeam                    {
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [Parameter(ParameterSetName='Default',  Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Roles',    Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Users',    Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Name','Id')]
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Team,
        [Parameter(ParameterSetName='Roles', Mandatory=$true)]
        [alias('ScopedUserRoles')]
        [switch]$Roles,
        [Parameter(ParameterSetName='Users', Mandatory=$true)]
        [switch]$ExpandUsers
    )
    process {
        if      ($Team.ID  ) {$Team = $Team.Id}
        elseif  ($Team.Name) {$Team = $Team.Name}
        if      ($Team -match '^teams-\d+$') {
                 $item   = Invoke-OctopusMethod -PSType OctopusTeam -EndPoint "teams/$Team" -SpaceId $null
        }
        else    {$item   = Invoke-OctopusMethod -PSType OctopusTeam -EndPoint Teams -ExpandItems -Name $Team -SpaceId $null | Sort-Object -Property name}
        if      ($Roles)       {$item.Roles()}
        elseif  ($ExpandUsers) {$item.Users()}
        else                   {$item  }
    }
}
## https://Octopus.com/docs/Octopus-rest-api/examples/users-and-teams

function Get-OctopusUser                    {
    [cmdletbinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OptopusUserNamesCompleter])]
        [Parameter(ParameterSetName='Default',      Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Teams',        Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Spaces',       Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Parameter(ParameterSetName='Permissions',  Mandatory=$true,  Position=0, ValueFromPipeline=$true)]
        [Alias('Name','ID')]
        $User,
        [Parameter(ParameterSetName='Teams',        Mandatory=$true)]
        [switch]$Teams,
        [Parameter(ParameterSetName='Spaces',       Mandatory=$true)]
        [switch]$Spaces,
        [Parameter(ParameterSetName='Permissions',  Mandatory=$true)]
        [switch]$Permissions
    )
    #if teams or perms convert name / object to ID
    # Invoke-OctopusMethod "users/Users-21/teams" -spaceId $null  /Invoke-OctopusMethod "/api/users/Users-22/permissions/configuration" -Verbose -spaceId $null)
    #else
    if (-not $User) {
         Invoke-OctopusMethod -PSType OctopusUser 'users' -spaceId $null -ExpandItems
    }
    foreach ($u in $User) {
        if ($u -match '^users-\d+$') {
            $item = Invoke-OctopusMethod -PSType OctopusUser "users/$u"   -spaceId $null
        }
        else{
            $item = Invoke-OctopusMethod -PSType OctopusUser 'users'   -spaceId $null -ExpandItems |
                     Where-Object {$_.UserName -like $u -or $_.DisplayName -like $u -or $_.id -eq $u}
        }
        if     ($Teams)       {$item.Teams($true)}
        elseif ($Spaces)      {$item.Spaces() }
        elseif ($Permissions) {$item.Permissions()}
        else   {$item}
    }
}

function Get-OctopusUserRole                {
    [cmdletbinding()]
    param   (
        [Parameter(Mandatory=$false, Position=0 ,ValueFromPipeline=$true)]
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        [Alias('Name','ID')]
        $UserRole
    )
    if     ($UserRole.Id)   {$UserRole = $UserRole.id}
    elseif ($UserRole.Name) {$UserRole = $UserRole.Name}
    if     ($UserRole -match '^userroles-') {
            Invoke-OctopusMethod -PSType OctopusUserRole -EndPoint "userroles/$UserRole"   -spaceId $null
    }
    else   {Invoke-OctopusMethod -PSType OctopusUserRole -EndPoint userroles -ExpandItems -Name $UserRole -spaceId $null  }
}
