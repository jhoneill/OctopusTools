using namespace 'System.Management.Automation'
using namespace 'System.Management.Automation.Language'
using namespace 'System.Collections'
using namespace 'System.Collections.Generic'

# support for tab-completion of arguments.
function octoArgList {
<#
.description
   the classes are SO similar that I pulled most of their logic out into a helper function
    We usually want the name property, and usually want the current space
    The give us the endpoint and word to complete and we'll hand back the array the completers return
    If I could be bothered to put a where parameter in I could get the library variable sets and script modules to use this too.
#>
        Param (
            $wordToComplete,
            $EndPoint,
            $PropertyName = 'Name',
            $spaceID = $env:OctopusSpaceID
        )
        #Completers want a list of completion results
        $results        = [List[CompletionResult]]::new()
        #strip any quotes
        $wordToComplete = $wordToComplete -replace "^`"|^'|'$|`"$", ''
        #get the objects, filter to matching ones, return a completion result with value in quotes where needed
        Invoke-OctopusMethod -SpaceId $spaceID -EndPoint $EndPoint -ExpandItems  -verbose:$false | Select-object -ExpandProperty $PropertyName |
            Where-Object {$_ -like "$wordToComplete*"} | Sort-Object | ForEach-Object {
                if ($_ -Notmatch '\W') {$results.Add([CompletionResult]::new(    $_    , $_, ([CompletionResultType]::ParameterValue) , $_)) }
                else                   {$results.Add([CompletionResult]::new("'$($_)'" , $_, ([CompletionResultType]::ParameterValue) , $_)) } }
        #PowerShell likes to unpack arrays when they're output, so NEST the array we want to return so when THAT unpacks we still have an array.
        return ,$results
}

class OptopusGenericNamesCompleter     : IArgumentCompleter { # get the type that matches the parameter name for this space
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint "$parameterName`s"
    }
}
class OptopusNullSpaceNamesCompleter   : IArgumentCompleter { # get the type that matches the parameter name when the type is an all-spaces one
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName,    [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint "$parameterName`s" -spaceID $null
    }
}

class OptopusCustomActionsCompleter    : IArgumentCompleter {
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint  environments
    }
}
class OptopusEnvironmentNamesCompleter : IArgumentCompleter { # get environments when the paramter name isn't environment
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint  environments
    }
}
class OptopusPackageNamesCompleter     : IArgumentCompleter { # get packages, matching on packageID not name.
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint packages -PropertyName PackageId
    }
}
class OptopusUserNamesCompleter        : IArgumentCompleter { # get user names, matching on userName. not name.
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        return octoArgList $WordToComplete -EndPoint users -PropertyName userName -spaceID $null
    }
}

class OptopusLibVariableSetsCompleter  : IArgumentCompleter { # get library variable sets - we need to filter out scripts
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        $results        = [List[CompletionResult]]::new()
        $wordToComplete = $wordToComplete -replace "^`"|^'|'$|`"$", ''
        (Invoke-OctopusMethod -EndPoint libraryvariablesets -ExpandItems).
            where({$_.contenttype -eq 'variables' -and $_.Name -like "$wordToComplete*"}).
                foreach({
                    if ($_.Name -Notmatch '\W'){$results.Add([CompletionResult]::new(    $_.Name    , $_.Name, ([CompletionResultType]::ParameterValue) , $_.Name)) }
                    else                       {$results.Add([CompletionResult]::new("'$($_.Name)'" , $_.Name, ([CompletionResultType]::ParameterValue) , $_.Name)) }
                })
        return $results
    }
}
class OptopusLibScriptModulesCompleter : IArgumentCompleter { # get libray scripts using variable set type and filter to ONLY scripts
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        $results        = [List[CompletionResult]]::new()
        $wordToComplete = $wordToComplete -replace "^`"|^'|'$|`"$", ''
        (Invoke-OctopusMethod -EndPoint libraryvariablesets -ExpandItems ).
            where({$_.contenttype -eq 'ScriptModule' -and $_.Name -like "$wordToComplete*"}).
                foreach({
                    if ($_.Name -Notmatch '\W'){$results.Add([CompletionResult]::new(    $_.Name    , $_.Name, ([CompletionResultType]::ParameterValue) , $_.Name)) }
                    else                       {$results.Add([CompletionResult]::new("'$($_.Name)'" , $_.Name, ([CompletionResultType]::ParameterValue) , $_.Name)) }
                })
        return $results
    }
}
class OptopusMachineRolesCompleter     : IArgumentCompleter { # get machine roles
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        $results        = [List[CompletionResult]]::new()
        $wordToComplete = $wordToComplete -replace "^`"|^'|'$|`"$", ''
        (Invoke-OctopusMethod -EndPoint 'machineroles/all' -verbose:$false).
            where({$_ -like "$wordToComplete*"}).
            foreach({
                if ($_ -Notmatch '\W'){$results.Add([CompletionResult]::new(  $_,   $_, ([CompletionResultType]::ParameterValue) , $_)) }
                else                  {$results.Add([CompletionResult]::new("'$_'", $_, ([CompletionResultType]::ParameterValue) , $_)) }
            })
        return $results
    }
}
class OptopusPermissionsCompleter      : IArgumentCompleter { # get library variable sets - we need to filter out scripts
    [IEnumerable[CompletionResult]] CompleteArgument( [string]$CommandName, [string]$ParameterName, [string]$WordToComplete,
                                                      [CommandAst]$CommandAst, [IDictionary] $FakeBoundParameters) {
        $results        = [List[CompletionResult]]::new()
        $wordToComplete = $wordToComplete -replace "^`"|^'|'$|`"$", ''
        (Invoke-OctopusMethod -EndPoint permissions/all -SpaceId $null).psobject.properties.name.
            where({$_ -like "$wordToComplete*"}).
                foreach({
                    if ($_ -Notmatch '\W'){$results.Add([CompletionResult]::new(    $_    , $_, ([CompletionResultType]::ParameterValue) , $_)) }
                    else                       {$results.Add([CompletionResult]::new("'$($_)'" , $_, ([CompletionResultType]::ParameterValue) , $_)) }
                })
        return $results
    }
}
