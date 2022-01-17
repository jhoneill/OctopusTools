
<#
#see also https://Octopus.com/docs/Octopus-rest-api/examples/step-templates/export-step-templates
$h =  Get-OctopusActionTemplate $TEMPATE  | Undo-JsonConversion
$h.Remove('Version')
$h.Remove('ID')
$h.Remove('Links')
$h.Remove('CommunityActionTemplateId)
$h.Parameters | foreach {$_.remove('ID')}
convertto-json $h -Depth 10 > deleteme.json
#api/Spaces-1/actiontemplates/categories
#>


function New-OctopusActionTemplateParameter {
    param        (
        [Parameter(Position=0,Mandatory=$true)]
        $Name,
        $Label,
        $HelpText     = "",
        $DefaultValue = "",
        [validateSet('AmazonWebServicesAccount','AzureAccount','Certificate','Checkbox',
        'GoogleCloudAccount','MultiLineText','Package','Select','Sensitive','SingleLineText')]
        $ControlType   = 'SingleLineText',
        $SelectOptions
    )
    process {
        if (-not $Label) {$Label = $Name}
        $NewParam = @{
            Name            = $Name
            Label           = $Label
            HelpText        = $HelpText
            DefaultValue    = $DefaultValue
            DisplaySettings = @{'Octopus.ControlType' = $ControlType}
        }
        if     ($SelectOptions -and $ControlType -ne 'Select') {
            Write-Warning "Can't specify selection options with control type of '$ControlType'."
            return
        }
        elseif ($SelectOptions) {
            $NewParam.DisplaySettings['Octopus.SelectOptions'] = $SelectOptions -join "`n"
        }
        elseif ($ControlType -eq 'Select') {
            Write-Warning "Selection options are required when the control type is 'Select'."
            return
        }
        $NewParam
    }
}

function New-OctopusScriptActionTemplate    {
    <#
        example fodder
        $p1 = New-OctopusActionTemplateParameter -Name "Port"
        $p2 = New-OctopusActionTemplateParameter -Name "ServiceName" -HelpText "Name for the service" -label "Service Name"
        New-OctopusScriptActionTemplate -Name test3 -Description "Another test" -StepParameters $p1, $p2 -Package PowerShellScripts -ScriptPath "PowerShellScripts\Psscript1.ps1" -ScriptArguments  "-Name #{SeviceName} -Path #{TCPPort}"

        New-OctopusScriptActionTemplate -Name test44 -Description "Another test"  -ScriptBody @'
         $psversionTable
         Get-Module
        '@
    #>
    [cmdletbinding(SupportsShouldProcess=$true)]
    param   (
        [Parameter(ValueFromPipelineByPropertyName=$true,Position=0,Mandatory=$True)]
        $Name,

        $Description,
        [ArgumentCompleter([OctopusPackageNamesCompleter])]
        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package',Mandatory=$true)]
        $Package,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package',Mandatory=$true)]
        [alias('ScriptFileName')]
        $ScriptPath,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package')]
        [alias('ScriptParameters')]
        $ScriptArguments,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='InLine',Mandatory=$true)]
        $ScriptBody,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='InLine')]
        [ValidateSet('Bash', 'CSharp', 'FSharp', 'PowerShell', 'Python')]
        $Syntax = 'PowerShell',

        [hashtable[]]$StepParameters,

        [switch]$Force
    )
    if ($Package -is [string]) {$Package = $package -split '\s*,\s*|\s*;\s*'}
    $package = @() + $(foreach ($p in $Package) {if ($p.PackageId -and $p.FeedId) {$p} else {Get-OctopusPackage $p}  })

    if ($ScriptPath -and $Package) {
        $stepDefintion  = @{
            ActionType  = 'Octopus.Script'
            Name        = $Name
            Description = $Description
            Properties  = @{
                'Octopus.Action.Script.ScriptSource'     = 'Package'
                'Octopus.Action.Script.Syntax'           = $null
                'Octopus.Action.Script.ScriptBody'       = $null
                'Octopus.Action.Script.ScriptFileName'   = $ScriptPath
                'Octopus.Action.Script.ScriptParameters' = $ScriptArguments
                'Octopus.Action.Package.PackageId'       = $Package[0].PackageId
                'Octopus.Action.Package.FeedId'          = $Package[0].FeedId

            }
            Packages    = @()
            Parameters  = @()
        }
    }
    elseif  ($ScriptBody)  {
      $stepDefintion  = @{
            ActionType  = 'Octopus.Script'
            Name        = $Name
            Description = $Description
            Properties  = @{
                'Octopus.Action.Script.ScriptSource'     = 'Inline'
                'Octopus.Action.Script.Syntax'           = $Syntax
                'Octopus.Action.Script.ScriptBody'       = $ScriptBody
                'Octopus.Action.Script.ScriptFileName'   = $null
            }
            Packages    = @()
            Parameters  = @()
        }
    }
    foreach ($s in $StepParameters.Where({$null -ne $_})) {$stepDefintion.Parameters += $s }
    foreach ($p in $Package) {
        $stepDefintion['Packages'] += @{
            Id                  = $null
            PackageId           = $p.PackageId
            FeedId              = $p.FeedId
            AcquisitionLocation = "Server"
            Properties          = @{SelectionMode = "immediate"}
        }
    }
    if ($Force -or $PSCmdlet.ShouldProcess($Name,'Add New script-action template.')) {
        Invoke-OctopusMethod -PSType OctopusActionTemplate  -Method Post -EndPoint actiontemplates -Item $stepDefintion
    }
}

function Set-OctopusScriptActionTemplate    {
    [cmdletbinding(DefaultParameterSetName='None',SupportsShouldProcess=$true)]
    param (
        [Parameter(Mandatory=$true,Position=0)]
        [Alias('Name','Id')]
        [ArgumentCompleter([OctopusGenericNamesCompleter])]
        $ActionTemplate,
        $Description,

        [ArgumentCompleter([OctopusPackageNamesCompleter])]
        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package',Mandatory=$true)]
        $Package,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package',Mandatory=$true)]
        [alias('ScriptFileName')]
        $ScriptPath,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='Package')]
        [Alias('ScriptParameters')]
        $ScriptArguments,

        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='InLine',Mandatory=$true)]
        $ScriptBody,
        [Parameter(ValueFromPipelineByPropertyName=$true,ParameterSetName='InLine')]
        [ValidateSet('Bash', 'CSharp', 'FSharp', 'PowerShell', 'Python')]
        $Syntax = 'PowerShell',

        [hashtable[]]$StepParameters,

        $Force
    )
    if     ($ActionTemplate.id)   {$ActionTemplate = $ActionTemplate.id}
    elseif ($ActionTemplate.Name) {$ActionTemplate = $ActionTemplate.Name}
    $existing = Invoke-OctopusMethod "actiontemplates/all" |
                    Where-Object {$_.name -like $ActionTemplate -or $_Id -like $ActionTemplate  }
    if (-not $existing) {
        Write-Verbose "$ActionTemplate Did not match an existing template - creating as new... "
        New-OctopusScriptActionTemplate @PSBoundParameters
        return
    }
    elseif  ($existing.count -gt 1) {
        throw "'$ActionTemplate' matches more than one template."
    }
    elseif  ($existing.ActionType -ne 'Octopus.script') {
         throw "'$ActionTemplate' exists, but it is not a script action template."
    }
    else {
        $changed = $false # we will only write back if we have changed something

        #Expand pacakage from strings or a , or ; seperated list into Octopus package objects.
        if ($Package -is [string]) {$Package = $package -split '\s*,\s*|\s*;\s*'}
        $package = @() + $(foreach ($p in $Package) {
            if ($p.PackageId -and $p.FeedId) {$p}
            else {Get-OctopusPackage $p}
        })
        Write-Verbose "Package IDs are '$($package.packageID -join "', '")'."

        #region sort out script body & Syntax, or Script feed/package/Filename and parameters
        if (($scriptbody -and -not $existing.Properties.'Octopus.Action.Script.ScriptBody') -or
            ($ScriptPath -and -not $existing.Properties.'Octopus.Action.Script.ScriptFileName')) {
            Write-Warning "Changing from an inline script to a packaged script is not supported."
            return
        }
        #if inline script has changed update it and its syntax
        if  ($ScriptBody -and $ScriptBody -ne $existing.Properties.'Octopus.Action.Script.ScriptBody') {
             Write-Verbose "Inline-script body changed."
             $changed = $true
             # don't over-ride the syntax with the default If nothing was specified leave it alone.
             if ($PSBoundParameters.ContainsKey('Syntax')) {
                 $existing.Properties.'Octopus.Action.Script.Syntax'   = $Syntax
             }
             $existing.Properties.'Octopus.Action.Script.ScriptBody'   = $ScriptBody
             $existing.Properties.'Octopus.Action.Script.ScriptSource' = 'Inline'
        }
        elseif ($PSBoundParameters.ContainsKey('Syntax')) {
            Write-Warning "Syntax is NOT updated unless the script body is changed at the same time"
        }
        #Parameter definitons ensure we have  a package if setting the script filename / params, and if the path has changed
        if  ($ScriptPath -and  $scriptPath -ne  $existing.Properties.'Octopus.Action.Script.ScriptFileName') {
             $changed = $true
             $existing.Properties.'Octopus.Action.Script.ScriptFileName' = $ScriptPath
             $existing.Properties.'Octopus.Action.Script.ScriptSource'   = 'Package'
             Write-Verbose "Path to package script file changed."
        }
        #Parameter definitons ensure we have  a package if setting the script parameters
        if ($ScriptArguments -and $ScriptArguments -ne $existing.Properties.'Octopus.Action.Script.ScriptParameters') {
            $changed = $true
            $existing.Properties.'Octopus.Action.Script.ScriptParameters' = $scriptArguments
            $existing.Properties.'Octopus.Action.Script.ScriptSource'     = 'Package'
            Write-Verbose "Script Agruments changed."
        }
        #If the [first] package doesnt match the package used for the script, update that too
        if ($package -and $existing.Properties.'Octopus.Action.Package.PackageId'-and (
            $Package[0].FeedId    -ne $existing.Properties.'Octopus.Action.Package.FeedId' -or
            $Package[0].PackageId -ne $existing.Properties.'Octopus.Action.Package.PackageId'
        )){
            $changed = $true
            $existing.Properties.'Octopus.Action.Package.PackageId' = $Package[0].PackageId
            $existing.Properties.'Octopus.Action.Package.FeedId'    = $Package[0].FeedId
            Write-Verbose "Package for inline script changed."
        }
        #endregion
        #region if packages were specified, remove in the definition which aren't included, and add any missing from the definition
        if ($package) {
            #for each exiting package either keep it in .packages if it is $package or drop it and update $changed
            $existing.Packages = @() + $(foreach ($p in $existing.Packages) {
                $q = $Package | Where-Object {$_.PackageId -eq $p.PackageId -and $_.FeedId -eq $p.FeedId}
                if ($q) {$p}
                else {
                    $changed = $true
                    Write-Verbose "Dropping package '$($p.PackageId)'"
                }
            })
            #for any package(s) passed as a parameter, if it isn't in $existing.packages add it and updated changed
            foreach ($p in $Package) {
                $q = $existing.Packages | Where-Object {$_.PackageId -eq $p.PackageId -and $_.FeedId -eq $p.FeedId}
                if (-not $q) {
                    $changed = $true
                    Write-Verbose "Adding package '$($p.PackageId)'"
                    $existing.Packages += @{
                        Id                  = $null
                        PackageId           = $p.PackageId
                        FeedId              = $p.FeedId
                        AcquisitionLocation = "Server"
                        Properties          = @{SelectionMode = "immediate"}
                    }
                }
            }
        }
        #endregion

        if ($Description -and  $Description -ne $existing.Description ) {
            $Changed = $true
            $existing.Description = $Description
            Write-Verbose "Updating Description"
        }

        #region sort out parameters. IF they are new add them, if they have changed update them.
        foreach ($s in $StepParameters.Where({$null -ne $_})) {
            $t =  $existing.Parameters | Where-Object {$_.name -eq $s.name}
            if (-not $t) {
                $existing.Parameters += $s
                $changed = $true
                Write-Verbose "Adding Step Parameter '$($s.Name)'"
            }
            elseif (($s.DisplaySettings.'Octopus.ControlType' -eq 'Select' -and
                     $t.DisplaySettings.'Octopus.ControlType' -ne 'Select')  -or
                    ($s.DisplaySettings.'Octopus.ControlType' -ne 'Select' -and
                     $t.DisplaySettings.'Octopus.ControlType' -eq 'Select'))   {
                    Write-Warning "Can't change turn selection list" ; return
            }
            else {
                if ($s.label -and $s.label -ne $t.Label) {
                    $existing.Parameters.Where({$_.id -eq $t.id}).foreach({$_.label =  $s.Label})
                    $changed = $true
                    Write-Verbose "Updated label on Step Parameter '$($s.Name)'"
                }
                if ($s.HelpText -and $s.HelpText -ne $t.HelpText) {
                    $existing.Parameters.Where({$_.id -eq $t.id}).foreach({$_.HelpText =  $s.HelpText})
                    $changed = $true
                    Write-Verbose "Updated HelpText on Step Parameter '$($s.Name)'"
                }
                if ($s.DefaultValue -and $s.DefaultValue -ne $t.DefaultValue) {
                    $existing.Parameters.Where({$_.id -eq $t.id}).foreach({$_.DefaultValue =  $s.DefaultValue})
                    $changed = $true
                    Write-Verbose "Updated default value on Step Parameter '$($s.Name)'"
                }
                if ($s.DisplaySettings.'Octopus.ControlType' -and $s.DisplaySettings.'Octopus.ControlType' -ne $t.DisplaySettings.'Octopus.ControlType') {
                    $existing.Parameters.Where({$_.id -eq $t.id}).foreach({$_.DisplaySettings.'Octopus.ControlType' =  $s.DisplaySettings.'Octopus.ControlType'})
                    $changed = $true
                    Write-Verbose "Updated Control Type on Step Parameter '$($s.Name)'"
                }
                if ($s.DisplaySettings.'Octopus.SelectOptions' -and $s.DisplaySettings.'Octopus.SelectOptions' -ne $t.DisplaySettings.'Octopus.SelectOptions') {
                    $existing.Parameters.Where({$_.id -eq $t.id}).foreach({$_.DisplaySettings.'Octopus.SelectOptions' =  $s.DisplaySettings.'Octopus.SelectOptions'})
                    $changed = $true
                    Write-Verbose "Updated Selection options on Step Parameter '$($s.Name)'"
                }
            }
        }

        if ($changed -and ($Force -or $PSCmdlet.ShouldProcess($existing.Name,'Update Script Action template.') )) {
            Invoke-OctopusMethod -PSType OctopusActionTemplate -Method put -EndPoint $existing.Links.Self -Item $existing
        }
        else {Write-Verbose "No Changes found"}
    }
}
