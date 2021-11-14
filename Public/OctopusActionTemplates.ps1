function  Get-OctopusActionTemplate         {
<#
    example fodder
    Get-OctopusActionTemplate -Custom  | select -First 10  | foreach {$_.useDetails() | export-excel -path Actiontemplates.xlsx -WorksheetName $_.id }

#>
    [cmdletbinding(DefaultParameterSetName='None')]
    param   (
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Position=0,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        $ActionTemplate = '*',
        [Parameter(ParameterSetName='BuiltIn')]
        [switch]$BuiltIn,
        [Parameter(ParameterSetName='Custom')]
        [switch]$Custom,
        [Parameter(ParameterSetName='Community')]
        [switch]$Community
    )
    begin   {$results = @()}
    process {
    #add -usage
        Write-Progress "Getting Template details"
        if          (-not  $ActionTemplate) {
                     $results = Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint actiontemplates/search
        }
        foreach     ($a in $ActionTemplate) {
            if      ($a.ID  ) {$a = $a.Id}
            elseif  ($a.Name) {$a = $a.Name}
            if      ($a    -match '^ActionTemplates-\d+$') {
                    Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint "ActionTemplates/$a"
            }
            elseif  ($a    -match '^CommunityActionTemplates-\d+$') {
                    Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint "CommunityActionTemplates/$a"  -SpaceId $Null
            }
            elseif  ($a -notmatch '\*|\?' -and $Custom)    {
                    $endpoint = "ActionTemplates?partialName=$([uri]::EscapeDataString($a))"
                    Invoke-OctopusMethod -EndPoint $endpoint -ExpandItems -name $a -PSType "OctopusActionTemplate"
            }
            elseif  ($a -notmatch '\*|\?' -and $Community) {
                    $endpoint = "CommunityActionTemplates?partialName=$([uri]::EscapeDataString($a))"
                    Invoke-OctopusMethod -EndPoint $endpoint -ExpandItems -SpaceId $Null -Name $a -PSType "OctopusActionTemplate"
            }
            else    {
                #search self-expands items but they're no the full item!
                $results += Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint actiontemplates/search | Where-Object -Property Name -Like $a
            }
        }
    }
    end    {
        if      ($Community) {$results = $results | Where-Object {$_.id  -like 'CommunityActionTemplates-*'} }
        elseif  ($Custom)    {$results = $results | Where-Object {$_.id  -like 'ActionTemplates-*'} }
        elseif  ($BuiltIn)   {$results = $results | Where-Object {$null -eq $_.id } }
        $c = 0
        foreach ($r in ($results  | Sort-Object @{e={$_.id -replace '\d+','' }},Name ) ) {
            $c += 100
            if (-not $r.id) {$r}
            else {
                Write-Progress "Getting Template details" -PercentComplete ($c/$results.count)
                Invoke-OctopusMethod -PSType 'OctopusActionTemplate' -EndPoint ($r.links.logo -replace  "/logo" )
            }
        }
        Write-Progress "Getting Template details" -Completed
    }
}

function Export-OctopusActionTemplate       {
<#
.SYNOPSIS
    Exports one or more custom action-templates

 .PARAMETER ActionTemplate
    One or more custom-templates either passed as an object or a name or template ID. Accepts input from the pipeline

.PARAMETER Destination
    The file name or directory to use to create the JSON file. If a directory is given the file name will be "tempaltename.Json". If nothing is specified the files will be output to the current directory.

.PARAMETER PassThru
    If specified the newly created files will be returned.

.PARAMETER Force
    By default the file will not be overwritten if it exists, specifying -Force ensures it will be.

.EXAMPLE
An example

#>
    param (
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        [Parameter(Mandatory=$true,Position=0,ValueFromPipeline=$true)]
        [Alias('Id','Name')]
        $ActionTemplate ,

        [Parameter(Position=1)]
        $Destination = $pwd,

        [Alias('PT')]
        [switch]$PassThru,

        [switch]$Force
    )
    process {
        foreach ($t in $ActionTemplate) {
            $baretemplate = Get-OctopusActionTemplate $t -Custom | Select-Object -Property export #export is a property set
            if ($baretemplate.count -gt 1) {
                Write-Warning "'$t' match more than one template, please try again or use 'Get-OctopusActionTemplate $t | Export-OctopusActionTemplate '."
            }
            $baretemplate.Parameters = $baretemplate.Parameters  | Select-Object -Property * -ExcludeProperty  id
            foreach ($p in $baretemplate.Packages) {$p.id=$null}

            if     (Test-Path $Destination -PathType Container )    {$DestPath = (Join-Path $Destination $baretemplate.Name) + '.json' }
            elseif (Test-Path $Destination -IsValid -PathType Leaf) {$DestPath = $Destination}
            else   {Write-Warning "Invalid destination" ;return}
            ConvertTo-Json $baretemplate -Depth 10 | Out-File $DestPath -NoClobber:(-not $Force)
            if     ($PassThru) {Get-Item $DestPath}
        }
    }
}

function Import-OctopusActionTemplate       {
<#
.SYNOPSIS
    Imports an action template from a file (or a handy block of JSON text you may have)

.DESCRIPTION
    This command does some basic checks that it has been given parsable JSON and that the file at
    least has a name and an action type, and checks that the template does not already exist.

.PARAMETER Path
    The path to a JSON file it can be a wildcard that matches ONE file; multiple files can be piped into the command

.PARAMETER JsonText
    Instead of getting the text from a file accepts it as a string (or array of strings)

.PARAMETER Force
    Normally the command will prompt for confirmation before importing. Force supresses the prompt/

.EXAMPLE
    C:> dir *.json | import-OctopusActionTemplate -force
    Attempts to import all JSON files in the current directory as action templates without prompting for confirmation

#>
[cmdletbinding(SupportsShouldProcess=$true,DefaultParameterSetName='Default',ConfirmImpact='High')]
param (
    [Parameter(Position=0,ValueFromPipeline=$true,Mandatory=$true,ParameterSetName='Default')]
    $Path,
    [Parameter(Mandatory=$true,ParameterSetName='AsText')]
    $JsonText,
    [switch]$Force
)
    process {
        if (-not $JsonText) {
            $r = (Resolve-Path $Path)
            if     ($r)             {Write-Warning "Could not find $Path" ; return}
            elseif ($r.count -gt 1) {Write-Warning   "$Path matches more than one file." ; return}
            else                    {$JsonText = Get-Content -Raw $Path}
        }
        if ($JsonText -is [array]) {
            $JsonText= $JsonText -join [System.Environment]::NewLine
        }
        try   {$j =  ConvertFrom-Json -InputObject $JsonText -Depth 10}
        catch {Write-warning 'That does not appear to be valid JSON ' ;return }
        if (-not ($j.ActionType -and $j.Name )) {
               Write-warning 'The file parses as JSON but does not appeart to be an action template  ' ;return
        }
        elseif (Get-OctopusActionTemplate -custom $j.Name) {
               Write-warning "A custom action template named '$($j.name)' already exists." ;return
        }
        elseif ($Force -or $pscmdlet.ShouldProcess($j.Name,'Import template')) {
                Invoke-OctopusMethod -PSType OctopusActionTemplate  -Method Post -EndPoint actiontemplates -JSONBody $JsonText
        }
    }
}

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
    By default the command will prompt for confirmation before updating, if -Force is used the prompt is supressed.

.EXAMPLE
     C:> Get-OctopusActionTemplate 'Create an IIS Application Host web site' -force
     Updates steps for the named template without prompting.

#>

    [cmdletbinding(SupportsShouldProcess=$true, ConfirmImpact='High')]
    param (
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
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
        [ArgumentCompleter([OptopusPackageNamesCompleter])]
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
        [ArgumentCompleter([OptopusGenericNamesCompleter])]
        $ActionTemplate,
        $Description,

        [ArgumentCompleter([OptopusPackageNamesCompleter])]
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
