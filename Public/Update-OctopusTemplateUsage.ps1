function  Update-OctopusTemplateUsage       {
<#
.SYNOPSIS
    Updates Steps using an Action Template to use its latest version

.DESCRIPTION
    Action templates are versioned, and a step is bound not just to a template, but to a version of one.
    A template can find which steps are using it, and which versions they have, and this command
    will go through any which are not current and change their version number

.PARAMETER ActionTemplate
    The Template of interest; either as an object, or the name or ID of a template.
    Multiple items can be passed via the pipeline or the command line, and names should tab complate

.PARAMETER Force
    Supresses any confirmation message. By default the command will prompt for confirmation before updating.

.EXAMPLE
     C:> Get-OctopusActionTemplate 'Create an IIS Application Host web site' -force
     Updates steps for the named template without prompting.

#>

    [cmdletbinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        [Parameter(Position=0,Mandatory=$true,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        $ActionTemplate,
        $Force
    )
    process {
        foreach      ($a in $ActionTemplate ) {
            if (-not ($a.usage -and $a.version -and $a.Links.ActionsUpdate  )) {
                      $a = Get-OctopusActionTemplate $a
            }
            $hash = @{
                version               = $a.Version
                actionIdsByProcessId  = @{}
                defaultPropertyValues = @{}
                overrides             = @{}
            }
            $a.Usage().where({$_.Version -ne $a.Version})  |
                Group-Object -Property DeploymentProcessId |
                    ForEach-Object  {$hash.actionIdsByProcessId[$_.Name] = @($_.group.actionID)}
            if      ($hash.actionIdsByProcessId.count -eq 0) {
                    Write-warning "Nothing to update"
            }
            elseif ($Force -or $PSCmdlet.ShouldProcess($a.Name,"Update $($hash.actionIdsByProcessId.count) usages to version $($a.Version)")) {
                    Invoke-OctopusMethod -EndPoint $a.Links.ActionsUpdate -Method Post -Item $hash
            }
        }
    }
}
