function Expand-OctopusPermission           {
    <#
      .SYNOPSIS
        Helper functon
      .DESCRIPTION
         Core logic for Get-OctopusUserAccessReport and Get-OctopusProjectAccessReport
    #>
    param (
        [ArgumentCompleter([OptopusPermissionsCompleter])]
        [Parameter(Mandatory=$true,Position=0)]
        $Permission,

        $UnscopedPermission,
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Space              = "",

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        $Environment        = "",

        [ArgumentCompleter([OptopusUserNamesCompleter])]
        $User               = "",

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project            = "",

        $PermissionDisplayNames = @{}
    )

    $permission  | Where-Object {-not $PermissionDisplayNames.ContainsKey($_) }  | ForEach-Object {$permissionDisplayNames[$_] = $_ -replace '^(.*)(view|edit|create|delete|SubmitResponsible)(.*)$', '$2 $1$3' }

    $userList               = Get-OctopusUser -User $User
    if (-not $userList)     {Write-Error "'$User' does not match any users"; return}

    #Cache roles in a hash tables so we can look them up from their IDs
    $userRoles              = @{}
    Get-OctopusUserRole     | ForEach-Object {$userroles[$_.id] = $_}
    #We will cache each teams roles when we first meet it
    $teamRoles              = @{}

    <#we have SIX nestings of for loops. We already have a list of permissions passed in, we've got a list of users, and we have a list of user roles.
     Now, for each space of interest, for each project of interest in that space, for each user of interest, for permission passed in, for each team
     the user belongs to, look at the team'ss role: if a role includes the permission of interest AND its scope includes the current space (or
      all spaces), AND the current project or it's group (or all projects/groups), and all environments or at least one of the project's environments
      and  all tenants or at least one of associated with the project then we have something to output!
         Because two team memberships might give the same user different access to the same project; if the one grants that access to the project
      over all tenants and environments we don't need to look any further, otherwise we look at each membership to see if it adds to partial access.
     #>

    # if space is set to null (no spaces on the release in use) itereate over one null space.
    $spacebefore  = $env:OctopusSpaceID
    if   ((Test-Path Env:\OctopusSpaceID) -and ($null -eq $env:OctopusSpaceID)) {
        $spaces = @($null)
    }
    else {
        $spaces = Get-OctopusSpace $Space
        if (-not $spaces) { Write-Error "'$Space' does not match any spaces."; return  }
    }
    foreach ($s in $spaces) {
        # We've already got users and user-roles they're space independent. For each space get its tennants & the environments build hash tables
        # so we can look them up by ID, we can tell if a project uses environments we care about by checking the hash table.
        # We will want eachs users' team memberships later more than once per space, get ready to cache those. Then we ready to get projects.
        $env:OctopusSpaceID = $s.Id # $null.ID is null so this works for a null space.
        $membership         = @{}
        $tenants            = @{}
        $environmentNames   = @{}
        Get-Octopus  tenant | ForEach-Object {$tenants[$_.id]   = $_}
        Get-OctopusEnvironment  -Environment  $Environment | ForEach-Object {$environmentNames[$_.id] = $_.name}
        if ($environmentNames.Count -eq 0) {   Write-Warning "'$Environment' matches no environments in space $($s.name)." ; continue }

        $projectlist = Get-OctopusProject -Project $Project
        if      ( -not $projectlist) {         Write-Warning "'$Project' matches no projects in space $($s.name).";          continue }
        foreach ($p in $projectList) {
            #We will want to know if permissions scoped to an environment apply to this project.
            $projectEnvironmentList =  $p.Environments().where({$environmentNames[$_]})
            if (-not $projectEnvironmentList) {Write-Verbose "Project $($p.Name) does not use any environments of interest"; continue}

            foreach ($u in $userList) {
                if (-not $membership.ContainsKey($u.id) ) {$membership[$u.id] = $u.teams($true,$s.Id).id }
                foreach ($permissionToCheck in $permission) {
                    $IncludeScope =  $UnscopedPermission -notcontains $permissionToCheck
                    $userAccess = $null
                    foreach ($t in $membership[$u.id]) {
                        if (-not $teamRoles.ContainsKey($t)) {$teamRoles[$t]  = Invoke-OctopusMethod -endpoint "teams/$t/scopeduserroles" -ExpandItems -SpaceId $null}
                        $teamRoles[$t] | Where-Object {
                            Write-verbose "Checking $permissionToCheck on project $($p.Name) for user $($u.DisplayName) / having $($_.userRoleID) via $t)"
                            ( $permissionToCheck -in $userRoles[$_.UserRoleId].GrantedSpacePermissions -or
                              $permissionToCheck -in $userRoles[$_.UserRoleId].GrantedSystemPermissions    ) -and                      # The role carries the permission of interest AND  it applies to
                            (  (-not $_.spaceId)        -or  ($_.spaceid -eq $s.id))                         -and                      # All spaces or this space AND to
                            ( ((-not $_.ProjectIds)     -and (-not $_.ProjectGroupIds)) -or                                            # All projects & project groups, or this project or its group AND to
                                    ($_.ProjectIds      -contains  $p.id)               -or
                                    ($_.ProjectGroupIds -contains  $p.ProjectGroupId)        ) -and
                            (  (-not $_.EnvironmentIds) -or ($_.EnvironmentIds.where({$projectEnvironmentList -contains $_ }))  ) -and  # All environments or one of this project's environments AND to
                            (  (-not $_.TenantIds)      -or ($_.TenantIds.where({  $tenants[$_].ProjectEnvironments.($p.Id) })) )       # All Tenants or a tenant having this project
                        } | ForEach-Object {
                                Write-verbose "$permissionToCheck granted"
                                $newPermission = @{EnvironmentIDs = @() ; TenantIDs = @() }
                                if ($IncludeScope) {
                                    $newPermission.Environments = $_.EnvironmentIds.where({$projectEnvironmentList -notcontains $environmentId})
                                    $newPermission.Tenants = $_.tenantIds.where({$tenantList[$_].ProjectEnvironments.($p.Id)})
                                }
                                if (-not $userAccess) {$userAccess = $newPermission}
                                else{                                                  # clear them if the new permission has none, or merge if the new has some.
                                            if     ($userAccess.EnvironmentIDs -and -not $newPermission.EnvironmentIDs) { $userAccess.EnvironmentIDs = @()}
                                            elseif ($userAccess.EnvironmentIDs -and      $newPermission.EnvironmentIDs) {
                                                    $userAccess.EnvironmentIDs +=        $newPermission.EnvironmentIDs
                                                    $userAccess.EnvironmentIDs =         $userAccess.EnvironmentIDs | Sort-Object -Unique
                                            }
                                            if     ($userAccess.TenantIDs      -and -not $newPermission.TenantIDs)      { $userAccess.TenantIDs = @()}
                                            elseif ($userAccess.TenantIDs      -and      $newPermission.TenantIDs)      {
                                                    $userAccess.TenantIDs      +=        $newPermission.TenantIDs
                                                    $userAccess.TenantIDs      =         $userAccess.TenantIDs      | Sort-Object -Unique
                                            }
                            }
                        }
                        if (-not ($useraccess.EnvironmentIDs) -and -not ($userAccess.TenantIDs)) {break} # we've unscoped access to for this right on this project.
                    }
                    #if the user we're looking at has access to project bring all the info together as an object/
                    if ($userAccess) {
                        $permissionObj = [ordered]@{
                            Permission       = $permissionToCheck
                            PermissionDisplayName = $PermissionDisplayNames[$permissionToCheck]
                            SpaceName        = $s.Name
                            ProjectName      = $p.Name
                            ProjectID        = $p.ID
                            UserDisplayName  = $u.DisplayName;
                            UserId           = $u.Id;
                            EnvironmentScope = ""
                            TenantScope      = ""
                        }
                        if      ( $permissionScope.Environments) {$permissionObj.EnvironmentScope =  $environmentNames[$permissionScope.Environments] -join ";" }
                        elseif  ( $IncludeScope) {$permissionObj.EnvironmentScope = "All" }
                        else                                     {$permissionObj.EnvironmentScope = "N/A"}

                        if      ($permissionScope.Tenants)       {$permissionObj.TenantScope = $tenantList[$permissionScope.Tenants].Name -join ";" }
                        elseif  ( $IncludeScope)                 {$permissionObj.TenantScope = "All" }
                        else                                     {$permissionObj.TenantScope = "N/A" }

                        [PSCustomObject]$permissionObj
                        $userAccess = $null
                    }
                }
            }
        }
    }
    $env:OctopusSpaceID = $spacebefore
}

function Get-OctopusUserAccessReport        {
    #
    param (

        [ArgumentCompleter([OptopusPermissionsCompleter])]
        [Parameter(Mandatory=$true,Position=0)]
        $Permission,
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Space              = "",

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        $Environment        = "",

        [ArgumentCompleter([OptopusUserNamesCompleter])]
        $User               = "",

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project            = "",

        $Path,

        $OrderBy            = @('Permission', 'SpaceName', 'ProjectName', 'UserDisplayName'),

        [switch]$GridView,
        [switch]$Show
    )

    if     ($Path -like '*.xlsx' -and -not (Get-Command -ErrorAction SilentlyContinue Export-Excel)) {
        Write-Error 'To export as an .xlsx file please run Install-Module importExcel' ; returj
    }
    elseif ($Path -and      (Test-Path $Path -PathType Container))     {$Path = Join-Path $Path 'Permission.csv' }
    if     ($Path -and -not (Test-Path $Path -IsValid)) {Write-Error   "$Path is not a valid output path."; return}
    elseif ($Path -notlike  '*.xlsx'  -and $Show)       {Write-Warning '-Show is ignored for .CSV files'}

    #ensure we leave space as we found it,
    $spacebefore        = $env:OctopusSpaceID
    $permissionsReport  = Expand-OctopusPermission -Permission $Permission -UnscopedPermission @() -Space $Space -Environment $Environment -User $user -Project $Project
    $env:OctopusSpaceID = $spacebefore

    if     ($Path -and $Path -like "*.xlsx" ) {$permissionsReport | Sort-Object -Property $OrderBy | Export-Excel -path $Path -Show:$Show}
    elseif ($Path)                            {$permissionsReport | Sort-Object -Property $OrderBy | Export-Csv   -path $Path -NoTypeInformation}
    elseif ($GridView)                        {$permissionsReport | Sort-Object -Property $OrderBy | Out-GridView -Title "Permissions"}
    else                                      {$permissionsReport | Sort-Object -Property $OrderBy}

}

function Get-OctopusProjectAccessReport     {
#https://Octopus.com/docs/Octopus-rest-api/examples/reports/project-permissions-report
    param (
        [ArgumentCompleter([OptopusNullSpaceNamesCompleter])]
        $Space              = "",

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        $Environment        = "",

        [ArgumentCompleter([OptopusUserNamesCompleter])]
        $User               = "",

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project            = "",

        $Path,

        $OrderBy            = @('Permission', 'SpaceName', 'ProjectName', 'UserDisplayName'),

        [switch]$GridView,
        [switch]$Show
    )

    if     ($Path -like '*.xlsx' -and -not (Get-Command -ErrorAction SilentlyContinue Export-Excel)) {
        Write-Error 'To export as an .xlsx file please run Install-Module importExcel' ; returj
    }
    elseif ($Path -and      (Test-Path $Path -PathType Container)) {$Path = Join-Path $Path 'Permission.csv' }
    if     ($Path -and -not (Test-Path $Path -IsValid))  {Write-Error "$Path is not a valid output path."; return}
    elseif ($Path -notlike  '*.xlsx'  -and $Show)       {Write-Warning '-Show is ignored for .CSV files'}

    $permission             = @('ProjectView', 'ProjectEdit', 'VariableView', 'VariableEdit', 'VariableViewUnscoped', 'VariableEditUnscoped',
                                'LibraryVariableSetView', 'LibraryVariableSetEdit', 'LibraryVariableSetCreate', 'LibraryVariableSetDelete',
                                 'TenantView', 'TenantEdit', 'TenantCreate', 'TenantDelete', 'RunbookView', 'RunbookEdit',
                                 'RunbookRunView', 'RunbookRunCreate', 'ProcessView', 'ProcessEdit', 'ReleaseView', 'ReleaseCreate',
                                 'DeploymentView', 'DeploymentCreate', 'ArtifactView', 'InterruptionView', 'InterruptionViewSubmitResponsible')
    $unscopedPermission     = @('ProjectEdit', 'VariableViewUnscoped', 'VariableEditUnscoped', 'RunbookView', 'RunbookEdit', 'ProcessView', 'ProcessEdit', 'ReleaseView', 'ReleaseCreate' )
    $permissionDisplayNames = @{}
    $permission        | ForEach-Object {
        $permissionDisplayNames[$_] = $_ -replace '^(.*)(view|edit|create|delete|SubmitResponsible)(.*)$', '$2 $1$3' -replace "RunbookRun" ,
                          "Runbook-Run"  -replace "LibraryVariableSet" , "Library-Variable-Set" -replace "VariableUnscoped","Unscoped-Variable"
   }
    $permissionDisplayNames.InterruptionViewSubmitResponsible = "View and Submit Interruption"

    $permissionsReport = Expand-OctopusPermission -Permission $permission -Environment $Environment -Space $space -User $User -UnscopedPermission $unscopedPermission -Project $Project -PermissionDisplayNames $permissionDisplayNames

    if     ($Path -and $Path -like "*.xlsx" ) {$permissionsReport | Sort-Object -Property $OrderBy | Export-Excel -path $Path -Show:$Show}
    elseif ($Path)                            {$permissionsReport | Sort-Object -Property $OrderBy | Export-Csv   -path $Path -NoTypeInformation}
    elseif ($GridView)                        {$permissionsReport | Sort-Object -Property $OrderBy | Out-GridView -Title "Permissions"}
    else                                      {$permissionsReport | Sort-Object -Property $OrderBy}
}

function Get-OctopusDeploymentReport        {
    # https://Octopus.com/docs/Octopus-rest-api/examples/reports/deployments-per-target-role-report
    #WorksheetName Deployments -FreezeTopRow -AutoSize -TableStyle Medium6 -ClearSheet -PivotRows "Project Name" -PivotColumns "State" -PivotData @{"Release ID" = "Count"}  -PivotFilter Month -PivotChartType ColumnStacked
    [cmdletBinding(DefaultParameterSetName='Default')]
    param   (
        [ArgumentCompleter([OptopusMachineRolesCompleter])]
        [Parameter(ParameterSetName='Default',   Mandatory=$true,Position=0)]
        $Role           ,

        [Parameter(ParameterSetName='ByMachine', Mandatory=$true,  ValueFromPipeline=$true)]
        [Alias('Id','Name','TargetName')]
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Machine,

        [Parameter(Position=1)]
        $Path ,

        [ArgumentCompleter([OptopusEnvironmentNamesCompleter])]
        $Environment = '',

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $Project     = '',

        $DaysToQuery = 365,

        #For example @{PivotRows = "Project Name"; PivotColumns = "State"; PivotData = @{"Release ID" = "Count"}; PivotFilter = "Month"; PivotChartType = ColumnStacked}
        [hashtable]$ExcelOptions,
        [switch]$Show
    )
    begin   {
            if     ($Path -like '*.xlsx' -and -not (Get-Command -ErrorAction SilentlyContinue Export-Excel)) {
                Write-Error 'To export as an .xlsx file please run Install-Module importExcel' ; return
            }
            elseif ($Path -and      (Test-Path $Path -PathType Container))    {$Path = Join-Path $Path 'Permission.csv' }
            if     ($Path -and -not (Test-Path $Path -IsValid))               {Write-Error "$Path is not a valid output path."; return}
            elseif ($Path -notlike  '*.xlsx'  -and ($Show -or $ExcelOptions)) {Write-Warning '-Show and -ExcelOptions are ignored for .CSV files'}
            $calendar        = (Get-Culture).Calendar
            $minDate         = [datetime]::Now.AddDays( - $DaysToQuery )

            Write-Progress -Activity "Reading deployment information" -Status 'Getting projects and environments'

            #cache environment and project names, but only the ones we are interested in, so if the name isn't cached, we can discard items
            $environmentNames= @{}
            Get-OctopusEnvironment -Environment $Environment | ForEach-Object {$environmentNames[$_.id] = $_.name}
            $projectNames    = @{}
            Get-OctopusProject -Project $Project             | ForEach-Object {$projectNames[$_.id] = $_.name}

            #We'll also cache tasks in case there are multiple roles, and releases/deployments which may go to more than one machine / role combo
            $machineTasks    = @{}
            $releaseversions = @{}
            $deployments     = @{}

            $machinesToCheck = @()
    }
    process {
        # the tests if machine and if role deliberately exclude empty string or empty array.
        if ($Machine) {
            foreach    ($m in $Machine) {
                if     ($m.Id -and $m.name -and $m.Tasks) {$machinesToCheck += $m}
                elseif ($m -is [string])                  {$machinesToCheck += Get-OctopusMachine $m}
                else   {Write-Warning "Did not recognize what was passed as a machine"}
            }
        }
        elseif ($Role) {
            foreach ($r in $Role) {
                Write-Progress -Activity "Reading deployment information" -Status "Getting machines in role $r"
                Get-OctopusMachine -Role $R -Environment $Environment | Where-Object {$_.id -notin $machinesToCheck.id} |
                    ForEach-Object {$machinesToCheck += $_}
            }
        }
    }
    end     {
        if ($machinesToCheck.count -eq 0) {Write-Warning 'No Machines were selected'}
        $machinecount = 1
        $report       = foreach ($m in $machinesToCheck) {
            if (-not $machineTasks.ContainsKey($m.id)) {
                Write-Progress -Activity "Reading deployment information" -Status "Getting tasks for machine $($m.Name), ($machinecount of $($machinesToCheck.count))"
                $machineTasks[$m.id] = $m.Tasks().where({$_.queuetime -ge $minDate -and $_.Arguments.DeploymentId })
            }
            Write-Verbose "$( $machineTasks[$m.id].Count) matching tasks for machine $($m.name)    "
            $taskcount = 0
            foreach ($t in $machineTasks[$m.id] ) {

                if (-not $deployments.ContainsKey($t.Arguments.DeploymentId )) {
                         $deployments[$t.Arguments.DeploymentId] = Get-OctopusDeployment $t.Arguments.DeploymentId
                }
                $deployment =  $deployments[$t.Arguments.DeploymentId]
                $taskcount += 100
                Write-Progress -Activity "Reading deployment information" -Status "Processing Tasks on machine $($m.Name), ($machinecount of $($machinesToCheck.count))"-PercentComplete ($taskcount / $machineTasks[$m.id].Count)
                if (-not ($projectNames.ContainsKey($deployment.projectID) -and
                      $environmentNames.ContainsKey($deployment.EnvironmentID))) {
                    #this is not a deployment we are looking for
                    continue
                }
                if (-not $releaseVersions.ContainsKey($deployment.ReleaseId) ) {
                         $releaseVersions[$deployment.ReleaseId] = (Get-Octopusrelease  $deployment.ReleaseId ).Version
                }

                [pscustomObject][ordered]@{
                    'Machine with Role'  = ($m.Roles | Sort-Object) -join "; "
                    'Environment ID'     = $deployment.EnvironmentID
                    'Environment Name'   = $environmentNames[$deployment.EnvironmentID]
                    'Machine ID'         = $m.Id
                    'Machine Name'       = $m.Name
                    'Project ID'         = $deployment.projectID
                    'Project Name'       = $projectNames[$deployment.projectID]
                    'Release ID'         = $deployment.ReleaseId
                    'Release Version'    = $releaseVersions[$deployment.ReleaseId]
                    'Deployments ID'     = $t.Arguments.DeploymentId
                    'Task ID'            = $t.id
                    'State'              = $t.State
                    'Month'              = $t.QueueTime.ToString('yyyy-MM')
                    'Week'               = $t.QueueTime.ToString('yyyy-') + $calendar.GetWeekOfYear($t.QueueTime, 'FirstFullWeek', 'Monday').ToString('00')
                    'Queued DateTime'    = $t.QueueTime
                    'Start DateTime'     = $t.StartTime
                    'Completed DateTime' = $t.CompletedTime
                }
            }
        }
        if     (-not $report)                     {Write-Warning 'No data was generated with this selection and date range.'}
        elseif ($GridView)                        {$report | Out-GridView -Title "Permissions"}
        elseif (-not $Path)                       {$report}
        elseif (     $Path -notlike "*.xlsx" )    {$report | Export-Csv   -path $Path -NoTypeInformation}
        else   {
                if (-not $ExcelOptions)               {$ExcelOptions = @{}}
                if (-not $ExcelOptions.TableStyle)    {$ExcelOptions['TableStyle']    = 'Medium6'}
                if (-not $ExcelOptions.WorksheetName) {$ExcelOptions['WorksheetName'] = 'Deployments'}

                $ExcelOptions['Show'] = $Show -as [boolean]
                $excel = $report | Export-Excel -PassThru -Path $Path -FreezeTopRow -AutoSize -ClearSheet @ExcelOptions
                $ws = $excel.Workbook.Worksheets[1]
                #hide ID columns, week and month which are there for summarizing
                foreach ($c in @(2 ,4,6,8,10,11,13,14) ) {$ws.Column($c).Hidden = $true}
                Close-ExcelPackage -ExcelPackage $excel -Show:$show
        }
    }
}

function Export-OctoMatrixToExcel           {
    <#
        .description
            Export a matrix Of
            |       | Environment, | EnvironmentB|
            --------------------------------------
            |Role 1 |              |             |
            |Role 2 |              |             |
            Once for Target machines in those environments / roles
            And once projects whose lifecycle touches those environments, and whose steps relate to those roles.
    #>

    #Get Environments, Projects and Machines
    $environmentList    = Get-OctopusEnvironment
    $projectlist        = Get-OctopusProject
    $machineList        = Get-OctopusMachine

    #Get a list of roles assigned to machines, and for each role, output a row of data with role name, and machine-names in each environment
    $rolehash           = @{}
    foreach ($m in $machineList) {
        foreach ($role in $m.Roles) {$rolehash[$role]=$true}
    }
    $machineRoleMatrix  = foreach ($role in ($rolehash.Keys | Sort-Object -Unique) ) {
        $roleMembers    = [ordered]@{Role=$Role}
        foreach ($e in $environmentList) {
            $roleMembers[$e.name] = $machineList.where({$_.roles -contains $role -and $_.EnvironmentIds -contains $e.id }).Name -join '; '
        }
        [pscustomobject]$roleMembers
    }
    $machineRoleMatrix | Export-Excel

    #Repeat for projects. Get the roles an environments for each project (which is more complicated so put them in hash tables indexed by project)
    $rolehash           = @{}
    $projectRolesHash   = @{}
    $projectEnvsHash    = @{}
    foreach ($p in $projectlist) {
        $projectRolesHash[$p.Name] = ((Invoke-OctopusMethod $p.Links.DeploymentProcess).steps.Where({$_.properties.'Octopus.Action.TargetRoles'}).properties.'Octopus.Action.TargetRoles') -split '\s*,\s*' | Sort-Object -Unique
        foreach ($role in  $projectRolesHash[$p.Name]) {$rolehash[$role] = $true }
        $projectEnvsHash[$p.name] = Get-ProjectEnvironmentIds $p
    }

    #And for each role seen on projects, output a row of data with role name, and projects whose lifecycle says they touch that environment
    $ProjectRoleMatrix  = foreach ($role in ($rolehash.Keys | Sort-Object -Unique) ) {
        $roleMembers    = [ordered]@{Role=$Role}
        foreach ($e in $environmentList) {
            $roleMembers[$e.name] = $projectlist.where({$projectRolesHash[$_.name] -contains $role -and $projectEnvsHash[$_.name] -contains $e.id }).Name -join '; '
        }
        [pscustomobject]$roleMembers
    }
    $ProjectRoleMatrix | Export-Excel
}
