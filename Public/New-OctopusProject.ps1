function New-OctopusProject                 {
    <#
        .SYNOPSIS
            Creates a new project

        .DESCRIPTION
            Creates a new project, setting some but not all of its settings.
            The parameters support "From-pipeline by property value" so you can import a list of projects by piping into the command

        .PARAMETER Name
            The Short display-name for the new project which appears under any icon in the portal

        .PARAMETER Description
            Longer descriptive information

        .PARAMETER ProjectGroup
            The project group which should contain the new project if none is specified the first available group will be used

        .PARAMETER LifeCycle
            The lifecycle the project uses by default this appears in Channels in the portal, where additional lifecycles can be added.

        .PARAMETER VariableSets
            Library Variable Sets available to the project's  deployment process - these appear under Variables / Library Sets in the portal

        .PARAMETER ScriptModules
            Library Script Modules available to the project's deployment process  - these appear on the Process page, on the right hand side.

        .EXAMPLE
        c:> New-OctopusProject -Name "Web services" -Description "Set up all web services" -ProjectGroup 'Active Services' -LifeCycle 'Dev, Test, UAT and prod' -VariableSets 'Common Values'
        This creates, and returns, a new projected Named "Web services" in the "Active Services" group.
        It has a default channel using a named lifecycle, and uses one libraray variable set
        There will not, yet, be any project specific variables, additional channels, or triggers.
        No runbooks  have been defined and no steps or shared script modules have been added to the deployement process.
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param (
        [parameter(Mandatory=$true, position=0,ValueFromPipeline=$true)]
        $Name,

        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        [string]$Description,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        $ProjectGroup,

        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        $LifeCycle,

        [ArgumentCompleter([OptopusLibVariableSetsCompleter])]
        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        $VariableSets,

        [ArgumentCompleter([OptopusLibScriptModulesCompleter])]
        [parameter(Mandatory=$false,ValueFromPipelineByPropertyName=$true)]
        $ScriptModules
    )
    <# xxxx todo  Look at adding these properties
        DiscreteChannelRelease
        DefaultToSkipIfAlreadyInstalled
        TenantedDeploymentMode
        DefaultGuidedFailureMode
        VersioningStrategy
        ReleaseCreationStrategy
        Templates
        AutoDeployReleaseOverrides
        IsDisabled
        AutoCreateRelease
        ProjectConnectivityPolicy
    #>
    process {
        if     (-not $ProjectGroup)    {$ProjectGroup = Get-OctopusProjectGroup | Select-Object -First 1 -ExpandProperty Id}
        elseif      ($ProjectGroup.id) {$ProjectGroup = $ProjectGroup}
        elseif      ($ProjectGroup -notmatch '^ProjectGroups-\d+$') {
                     $ProjectGroup = (Get-OctopusProjectGroup $ProjectGroup).id
                     if (-not $ProjectGroup) {throw 'Could not resolve the project group provided.'}
        }
        if     (-not $LifeCycle)       {$LifeCycle = Get-OctopusLifeCycle| Select-Object -First 1 -ExpandProperty Id}
        elseif      ($LifeCycle.id)    {$LifeCycle = $LifeCycle.id}
        elseif      ($LifeCycle -notmatch '^Lifecycles-\d+$') {
                     $LifeCycle = (Get-OctopusLifeCycle $LifeCycle).id
                     if (-not $LifeCycle) {throw 'Could not resolve the lifecycle provided.'}
        }
        $ProjectDefinition  = @{
            Name            = $Name
            Description     = $Description
            ProjectGroupId  = $ProjectGroup
            LifeCycleId     = $LifeCycle
        }
        $setIds             = @()
        if ($VariableSets)        {
            foreach ($set in $VariableSets) {
                if      ($set.id)                                 {$setIds += $set.id}
                elseif  ($set -match '^LibraryVariableSets-\d+$') {$setIds += $set}
                else    {
                        $set = (Get-OctopusLibraryVariableSet $set ).id
                        if (-not $set) {throw 'Could not resolve the Library Variable Set provided'}
                        else {$setIds += $set}
                }
            }
        }
        if ($ScriptModules)       { #script modules are special variable sets and added to the same IncludedLibraryVariableSetIds section
            foreach ($module in $ScriptModules) {
                if      ($module.id)                                 {$setIds += $module.id}
                elseif  ($module -match '^LibraryVariableSets-\d+$') {$setIds += $module}
                else    {
                        $module = (Get-OctopusLibraryScriptModule $module ).id
                        if (-not $module) {throw 'Could not resolve the Script module provided'}
                        else {$setIds += $module}
                }
            }
        }
        if ($setIds.count -ge 1)  {$ProjectDefinition['IncludedLibraryVariableSetIds'] = $SetIds }
        if ($Force -or $pscmdlet.ShouldProcess($Name,'Create new project')) {
            Invoke-OctopusMethod -PSType OctopusProject -EndPoint 'Projects' -Method Post -Item $ProjectDefinition
        }
    }
}
