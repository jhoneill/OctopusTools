Introduction
============

These are tools I have been working on to **manage Octopus** in a PowerShell module. So far: 

*   Only a few functions have meaningful help. My plan is to move the  help out to markdown files for *Platypus* to work with. 
*   As yet there are no *Pester* tests.
*   Some of the functions use the `ImportExcel` module. If it is not present that functionality is designed to fail gracefully.
*   A PSD1 file loads type and format information, utility classes and the .PSM1.    
    In turn the PSM1 loads all the functions from PS1 files in Public and/or Private directories and at
    the moment these are not fully organized. I'm moving towards one file per function, sharing the same name, 
    at least as the  "source" (possibly merged into a single PSM1 for delivery). 

*   All the Octopus API calls go through a function named `Invoke-OctopusMethod`
    (alias IOM) which handles 
    -  Building the URIs for REST calls, 
    -  Adding the header with the API key to calls, 
    -  Converting non-JSON items to JSON for `POST` calls, setting the content type header, 
    -  Extracting items when a response has an `items` array property
    -  Filtering items client-side when a search term doesn't work for server-side searches
    -  Adding a type to results for PowerShell's benefit

*   **Authenticating.** `Invoke-OctopusMethod` takes parameters `OctopusUrl`, 
    `APIKey` and `SpaceId` and gets default values for them from
    `$env:OctopusUrl`, `$env:OctopusApiKey` and `$env:OctopusSpaceID`.    
    Another function, `Connect-Octopus`, sets these variables for the sesssion (I may move away from environment variables), it will take either a credential with the url 
    as the name and the API key as the password or take each in its own parameter as plain text. 
    If it is talking to a version of Octopus that supports spaces, connecting will convert a Space-name (or "default") to its ID and store for the Invoke command to us; if spaces aren't supported it will set the space to use to null.    
    If the PSM sees the environment variables (when the module is being reloaded) it 
    uses them in a call to `Connect-Octopus`, if not, if it can see an **Octopus.xml** file in 
    the current PowerShell Profile directory, it assumes it has been exported with     
    `Get-Credential -Message "URI as username, API Key as password" | Export-Clixml (Join-path (split-path $profile) "Octopus.xml`    
    and imports it and passes it to `connect-Octopus` as a credential. **This is the recommended method** just copy and run the command above, 
    the password in the exported file is only readable by the current user. You can use the command line but that means messing about with the key every time, and for testing you can put setting in environment variables. 

*   The Octopus API is pretty is pretty consistent: things usually have an ID in
    the form _thingS-1234_ (so IDs for a given *thing* are recognisable) and their name is usually in a `Name` property; the URIs are:
    -  `/things/ID` to get one thing from its ID
    -  `/things?partialName=bob` to find them name by or
    -  `/things` to get all of them
        (and for wildcard search we might get _all_ and do `| Where-Object` to filter locally).    
* This means that two different kinds of thing, for example _Machines_ and _Environments_ are fetched with API calls which are identical apart from the type of thing they fetching, and then have PowerShell type name is added typically `OctopusThing`. This common functionality has been moved into a `Get-Octopus` function. The commands    
    `Get-Octopus  environment build*` or `Get-Octopus -Kind Environment -Key build` in full, and    
    `Get-OctopusEnvironment build*` or  `Get-OctopusEnvironment -Environment build*`in full  do the same thing - the latter calls the former. Replacing `environment` with `machine` produces a working command for machines and so on. 

*   There is a `format.ps1xml` which uses the added type names to format Octopus
    objects helpfully. **This is still a work in progress**.
    Some other formatting comes from setting the types'
    `DefaultDisplayPropertySet` set in the *types* file.

*   The `types.ps1xml` file adds *script-methods* to objects to make additional
    API calls (*properties*, might be expanded when we didn't want the data:
    and could end up looing - environments get their machines, which get their environments, etc.) so script *properties* are only used to transform existing properties 
    without getting more data).    
    For example the types file adds `.Variables()` 
    and `.Machines()` to objects tagged `OctopusEnvironment`. Knowing this the  `Get-OctopusEnvironment` command can be enhanced with a `-machines` switch, so it calls `Get-Octopus -Kind Environment` to get the objects and for one returned, calls its`.Machines()` method.

*   This consistency made it easy to do argument completers. One,
    `OptopusGenericNamesCompleter` will assume the parameter name is the object type, so `Get-OctopusEnvironment` has an `Environment` parameter (aliases Name,ID),
    `Get-OctopusMachine` has a `Machine` parameter (aliases name,ID), and the completer works for both of them and populates the picklist with their `name` property.   
    I've made a few more completers for cases that don't follow this pattern.