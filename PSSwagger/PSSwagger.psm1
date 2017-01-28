﻿#########################################################################################
#
# Copyright (c) Microsoft Corporation. All rights reserved.
#
# PSSwagger Module
#
#########################################################################################

Microsoft.PowerShell.Core\Set-StrictMode -Version Latest
. "$PSScriptRoot\PSSwagger.Constants.ps1"
Microsoft.PowerShell.Utility\Import-LocalizedData  LocalizedData -filename PSSwagger.Resources.psd1

<#
.DESCRIPTION
  Decodes the swagger spec and generates PowerShell cmdlets.

.PARAMETER  SwaggerSpecPath
  Full Path to a Swagger based JSON spec.

.PARAMETER  Path
  Full Path to a file where the commands are exported to.
#>
function Export-CommandFromSwagger
{
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, ParameterSetName = 'SwaggerPath')]
        [String] 
        $SwaggerSpecPath,

        [Parameter(Mandatory = $true, ParameterSetName = 'SwaggerURI')]
        [Uri]
        $SwaggerSpecUri,

        [Parameter(Mandatory = $true)]
        [String]
        $Path,

        [Parameter(Mandatory = $true)]
        [String]
        $ModuleName,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'AzureStack')]
        [String]
        $Authentication = 'Azure',

        [ValidateSet('net45', 'netstandard1.7')]
        [String[]]
        $Frameworks,

        [ValidateSet('win10-x64')]
        [String[]]
        $Runtimes,
        
        [String]
        $BuildProject = "$PSScriptRoot\tools\project.json",

        [String]
        $BuildConfig = "$PSScriptRoot\tools\nuget.config",

        [Parameter()]
        [switch]
        $UseAzureCsharpGenerator,

        [switch]
        $AutomaticBootstrap
    )

    if ($PSCmdlet.ParameterSetName -eq 'SwaggerURI')
    {
        # Ensure that if the URI is coming from github, it is getting the raw content
        if($SwaggerSpecUri.Host -eq 'github.com'){
            $SwaggerSpecUri = "https://raw.githubusercontent.com$($SwaggerSpecUri.AbsolutePath)"
            $message = $LocalizedData.ConvertingSwaggerSpecToGithubContent -f ($SwaggerSpecUri)
            Write-Verbose -Message $message -Verbose
        }

        $SwaggerSpecPath = [io.path]::GetTempFileName() + ".json"
        $message = $LocalizedData.SwaggerSpecDownloadedTo -f ($SwaggerSpecURI, $SwaggerSpecPath)
        Write-Verbose -Message $message
        
        $ev = $null
        Invoke-WebRequest -Uri $SwaggerSpecUri -OutFile $SwaggerSpecPath -ErrorVariable ev
        if($ev) {
            return 
        }
    }

    if (-not (Test-path $SwaggerSpecPath))
    {
        throw $LocalizedData.SwaggerSpecPathNotExist
    }

    if ($null -eq $Frameworks) {
        if ('Desktop' -eq $PSEdition) {
            $Frameworks = @('net45')
        } else {
            $Frameworks = @('netstandard1.7')
        }

        $message = $LocalizedData.DiscoveredFrameworks -f ($SwaggerSpecUri)
        Write-Verbose -Message $message -Verbose
    }

    if ($null -eq $Runtimes) {
        # If Get-WmiObject works, we know we're on Windows at least
        # But for now, since Ubuntu 16.04 seems fine with win10 runtime, let's keep using that
        # Also need a way to support x86 on Linux
        # But again, for now, only support x64
        $Runtimes = @('win10-x64')

        $message = $LocalizedData.DiscoveredRuntimes -f ($SwaggerSpecUri)
        Write-Verbose -Message $message -Verbose
    }

    $jsonObject = ConvertFrom-Json ((Get-Content $SwaggerSpecPath) -join [Environment]::NewLine) -ErrorAction Stop

    # Parse the JSON and populate the dictionary
    $swaggerDict = ConvertTo-SwaggerDictionary -SwaggerSpecPath $SwaggerSpecPath -ModuleName $ModuleName

    # Populate the metadata, definitions and parameters from the provided Swagger specification
    $SwaggerSpecDefinitionsAndParameters = Get-SwaggerSpecDefinitionAndParameter -SwaggerSpecJsonObject $jsonObject -ModuleName $ModuleName
    $swaggerMetaDict = @{}
    
    $outputDirectory = $Path.TrimEnd('\').TrimEnd('/')

    if($PSVersionTable.PSVersion -lt '5.0.0') {
        if (-not $outputDirectory.EndsWith($ModuleName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $outputDirectory = Join-Path -Path $outputDirectory -ChildPath $ModuleName
        }
    } else {
        $ModuleVersion = $SwaggerSpecDefinitionsAndParameters['Version']
        $ModuleNameandVersionFolder = Join-Path -Path $ModuleName -ChildPath $ModuleVersion

        if ($outputDirectory.EndsWith($ModuleName, [System.StringComparison]::OrdinalIgnoreCase)) {
            $outputDirectory = Join-Path -Path $outputDirectory -ChildPath $ModuleVersion
        } elseif (-not $outputDirectory.EndsWith($ModuleNameandVersionFolder, [System.StringComparison]::OrdinalIgnoreCase)) {
            $outputDirectory = Join-Path -Path $outputDirectory -ChildPath $ModuleNameandVersionFolder
        }
    }

    $null = New-Item -ItemType Directory $outputDirectory -Force -ErrorAction Stop

    $swaggerMetaDict.Add("outputDirectory", $outputDirectory);
    $swaggerMetaDict.Add("UseAzureCsharpGenerator", $UseAzureCsharpGenerator)
    $swaggerMetaDict.Add("Authentication", $Authentication);
    $swaggerMetaDict.Add("SwaggerSpecPath", $SwaggerSpecPath);

    $Namespace = $SwaggerSpecDefinitionsAndParameters['Namespace']
    $generatedCSharpPath = ConvertTo-CsharpCode -SwaggerDict $swaggerDict `
                                    -SwaggerMetaDict $swaggerMetaDict
    
    Compile-Type -GeneratedCSharpPath $generatedCSharpPath -Frameworks $Frameworks -Runtimes $Runtimes -BuildProject $BuildProject -BuildConfig $BuildConfig -AutomaticBootstrap $AutomaticBootstrap -SwaggerMetaDict $SwaggerMetaDict -SwaggerDict $swaggerDict
    $FunctionsToExport = @()    
    $FunctionsToExport+= New-SwaggerPathCommands -CommandsObject $swaggerDict['paths'] `
                                                    -SwaggerMetaDict $swaggerMetaDict `
                                                    -DefinitionList $swaggerDict['definitions'] `
                                                    -Info $swaggerDict['info']

    $SwaggerDefinitionCommandsPath = Join-Path -Path (Join-Path -Path $outputDirectory -ChildPath $GeneratedCommandsName) -ChildPath 'SwaggerDefinitionCommands'

    # Handle the Definitions
    $DefinitionFunctionsDetails = @{}
    $jsonObject.Definitions.PSObject.Properties | ForEach-Object {
        Get-SwaggerSpecDefinitionInfo -JsonDefinitionItemObject $_ -Namespace $Namespace -DefinitionFunctionsDetails $DefinitionFunctionsDetails
    }

    # Expand the definition parameters from 'AllOf' definitions and x_ms_client-flatten declarations.
    $ExpandedAllDefinitions = $false

    while(-not $ExpandedAllDefinitions)
    {
        $ExpandedAllDefinitions = $true

        $DefinitionFunctionsDetails.Keys | ForEach-Object {
            
            $FunctionDetails = $DefinitionFunctionsDetails[$_]

            if(-not $FunctionDetails.ExpandedParameters)
            {
                $message = $LocalizedData.ExpandDefinition -f ($($FunctionDetails.Name))
                Write-Verbose -Message $message

                $Unexpanded_AllOf_DefinitionNames = $FunctionDetails.Unexpanded_AllOf_DefinitionNames | ForEach-Object {
                                                        $ReferencedDefinitionName = $_
                                                        if($DefinitionFunctionsDetails.ContainsKey($ReferencedDefinitionName) -and
                                                           $DefinitionFunctionsDetails[$ReferencedDefinitionName].ExpandedParameters)
                                                        {
                                                            $RefFunctionDetails = $DefinitionFunctionsDetails[$ReferencedDefinitionName]
                                                
                                                            $RefFunctionDetails.ParametersTable.Keys | ForEach-Object {
                                                                $RefParameterName = $_
                                                                if($FunctionDetails.ParametersTable.ContainsKey($RefParameterName))
                                                                {
                                                                    Throw $LocalizedData.SamePropertyName
                                                                }
                                                                else
                                                                {
                                                                    $FunctionDetails.ParametersTable[$RefParameterName] = $RefFunctionDetails.ParametersTable[$RefParameterName]
                                                                }
                                                            }
                                                        }
                                                        else
                                                        {
                                                            $_
                                                        }
                                                    }

                $Unexpanded_x_ms_client_flatten_DefinitionNames = $FunctionDetails.Unexpanded_x_ms_client_flatten_DefinitionNames | ForEach-Object {
                                                                        $ReferencedDefinitionName = $_
                                                                        if($DefinitionFunctionsDetails.ContainsKey($ReferencedDefinitionName) -and
                                                                           $DefinitionFunctionsDetails[$ReferencedDefinitionName].ExpandedParameters)
                                                                        {
                                                                            $RefFunctionDetails = $DefinitionFunctionsDetails[$ReferencedDefinitionName]
                                                
                                                                            $RefFunctionDetails.ParametersTable.Keys | ForEach-Object {
                                                                                $RefParameterName = $_
                                                                                if($FunctionDetails.ParametersTable.ContainsKey($RefParameterName))
                                                                                {
                                                                                    $ParameterName = $FunctionDetails.Name + $RefParameterName

                                                                                    $FunctionDetails.ParametersTable[$ParameterName] = $RefFunctionDetails.ParametersTable[$RefParameterName]
                                                                                    $FunctionDetails.ParametersTable[$ParameterName].Name = $ParameterName
                                                                                }
                                                                                else
                                                                                {
                                                                                    $FunctionDetails.ParametersTable[$RefParameterName] = $RefFunctionDetails.ParametersTable[$RefParameterName]
                                                                                }
                                                                            }
                                                                        }
                                                                        else
                                                                        {
                                                                            $_
                                                                        }
                                                                    }


                $FunctionDetails.ExpandedParameters = (-not $Unexpanded_AllOf_DefinitionNames -and -not $Unexpanded_x_ms_client_flatten_DefinitionNames)
                $FunctionDetails.Unexpanded_AllOf_DefinitionNames = $Unexpanded_AllOf_DefinitionNames
                $FunctionDetails.Unexpanded_x_ms_client_flatten_DefinitionNames = $Unexpanded_x_ms_client_flatten_DefinitionNames

                if(-not $FunctionDetails.ExpandedParameters)
                {
                    $message = $LocalizedData.UnableToExpandDefinition -f ($($FunctionDetails.Name))
                    Write-Verbose -Message $message
                    $ExpandedAllDefinitions = $false
                }
            } # ExpandedParameters
        } # Foeach-Object
    } # while()

    $DefinitionFunctionsDetails.Keys | ForEach-Object {
        
        $FunctionDetails = $DefinitionFunctionsDetails[$_]

        # Denifitions defined as x_ms_client_flatten are not used as an object anywhere. 
        # Also AutoRest doesn't generate a Model class for the definitions declared as x_ms_client_flatten for other definitions.
        if(-not $FunctionDetails.IsUsedAs_x_ms_client_flatten) {
            $FunctionsToExport += New-SwaggerSpecDefinitionCommand -FunctionDetails $FunctionDetails `
                                                                   -GeneratedCommandsPath $SwaggerDefinitionCommandsPath `
                                                                   -Namespace $Namespace
        }
    }

    $RootModuleFilePath = Join-Path $outputDirectory "$ModuleName.psm1"
    Out-File -FilePath $RootModuleFilePath `
             -InputObject $ExecutionContext.InvokeCommand.ExpandString($RootModuleContents)`
             -Encoding ascii `
             -Force

    New-ModuleManifestUtility -Path $outputDirectory `
                              -FunctionsToExport $FunctionsToExport `
                              -SwaggerSpecDefinitionsAndParameters $SwaggerSpecDefinitionsAndParameters

    Copy-HelperModuleToGeneratedModule -ModuleDirectory $outputDirectory -HelperDirectory "$PSScriptRoot\Generated.Azure.Common.Helpers" -HelperModuleName "Generated.Azure.Common.Helpers"
}

#region Cmdlet Generation Helpers

function New-SwaggerPathCommands
{
    param(
        [Parameter(Mandatory = $true)]
        [PSObject]
        $CommandsObject,

        [Parameter(Mandatory=$true)]
        [hashtable]
        $SwaggerMetaDict,

        [Parameter(Mandatory = $true)]
        [hashTable]
        $DefinitionList,

        [Parameter(Mandatory = $true)]
        [hashTable]
        $Info
    )

    $functionsToExport = @()
    $CommandsObject.Keys | ForEach-Object {
        $CommandsObject[$_].value.PSObject.Properties | ForEach-Object {
            $functionsToExport += New-SwaggerPathCommand -SwaggerMetaDict $SwaggerMetaDict `
                                                            -PathObject $_.Value `
                                                            -DefinitionList $DefinitionList `
                                                            -Info $Info
        }
    }

    return $functionsToExport
}

function New-SwaggerPathCommand
{
    param
    (
        [Parameter(Mandatory = $true)]
        [hashtable]
        $SwaggerMetaDict,

        [Parameter(Mandatory = $true)]
        [PSObject]
        $PathObject,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $DefinitionList,

        [Parameter(Mandatory = $true)]
        [hashTable]
        $Info
    )

    $commandHelp = Get-CommandHelp -PathObject $PathObject
    
    $commandName = Get-SwaggerPathCommandName -JsonPathItemObject $PathObject

    $paramObject = Get-ParamInfo -PathObject $PathObject 

    $paramHelp = $paramObject['ParamHelp']
    $paramblock = $paramObject['ParamBlock']
    $requiredParamList = $paramObject['RequiredParamList']
    $optionalParamList = $paramObject['OptionalParamList']

    $bodyObject = Get-FunctionBody -PathObject $PathObject `
                                        -SwaggerMetaDict $SwaggerMetaDict `
                                        -DefinitionList $DefinitionList `
                                        -RequiredParamList $requiredParamList `
                                        -OptionalParamList $optionalParamList `
                                        -Info $Info

    $outputTypeBlock = $bodyObject['outputTypeBlock']
    $body = $bodyObject['body']

    $CommandString = $executionContext.InvokeCommand.ExpandString($advFnSignature)

    $GeneratedCommandsPath = Join-Path -Path (Join-Path -Path $SwaggerMetaDict['outputDirectory'] -ChildPath $GeneratedCommandsName) -ChildPath 'SwaggerPathCommands'

    if(-not (Test-Path -Path $GeneratedCommandsPath -PathType Container)) {
        $null = New-Item -Path $GeneratedCommandsPath -ItemType Directory
    }

    $CommandFilePath = Join-Path -Path $GeneratedCommandsPath -ChildPath "$CommandName.ps1"
    Out-File -InputObject $CommandString -FilePath $CommandFilePath -Encoding ascii -Force -Confirm:$false -WhatIf:$false

    return $CommandName
}

<#
.DESCRIPTION
  Generates a cmdlet given a JSON custom object (from paths)
#>
function New-SwaggerSpecPathCommand
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSObject]
        $JsonPathItemObject,

        [Parameter(Mandatory=$true)]
        [string] 
        $GeneratedCommandsPath,

        [Parameter(Mandatory = $false)]
        [ValidateSet('Azure', 'AzureStack')]
        [String]
        $Authentication = 'Azure',

        [Parameter(Mandatory=$false)]
        [switch]
        $UseAzureCsharpGenerator,
        
        [Parameter(Mandatory=$true)]
        [PSCustomObject] 
        $SwaggerSpecDefinitionsAndParameters 
    )

    # TODO: remove as part of issue 21: Unify Functions
    $parameterDefString = @'
    
    [Parameter(Mandatory = $isParamMandatory)]
    [$paramType]
    $paramName,

'@

    $commandName = Get-SwaggerPathCommandName $JsonPathItemObject
    $description = ""
    if((Get-Member -InputObject $JsonPathItemObject -Name 'Description') -and $JsonPathItemObject.Description) {
        $description = $JsonPathItemObject.Description
    }
    $commandHelp = $executionContext.InvokeCommand.ExpandString($helpDescStr)

    [string]$paramHelp = ""
    $paramblock = ""
    $requiredParamList = @()
    $optionalParamList = @()
    $body = ""
    $Namespace = $SwaggerSpecDefinitionsAndParameters['namespace']

    # Handle the function parameters
    #region Function Parameters

    $JsonPathItemObject.parameters | ForEach-Object {
        if((Get-Member -InputObject $_ -Name 'Name') -and $_.Name)
        {
            $isParamMandatory = '$false'
            $parameterName = Get-PascalCasedString -Name $_.Name
            $paramName = "`$$parameterName" 
            $paramType = if ( (Get-Member -InputObject $_ -Name 'Type') -and $_.Type)
                         {
                            # Use the format as parameter type if that is available as a type in PowerShell
                            if ( (Get-Member -InputObject $_ -Name 'Format') -and $_.Format -and ($null -ne ($_.Format -as [Type])) ) 
                            {
                                $_.Format
                            }
                            else {
                                $_.Type
                            }
                         } elseif ( (Get-Member -InputObject $_ -Name 'Schema') -and ($_.Schema) -and
                             (Get-Member -InputObject $_.Schema -Name '$ref') -and ($_.Schema.'$ref') )
                         {
                            $ReferenceParameterValue = $_.Schema.'$ref'
                            $Namespace + '.Models.' + $ReferenceParameterValue.Substring( $( $ReferenceParameterValue.LastIndexOf('/') ) + 1 )
                         }
                         else {
                             'object'
                         }
            if ($_.Required)
            { 
                $isParamMandatory = '$true'
                $requiredParamList += $paramName
            }
            else
            {
                $optionalParamList += $paramName
            }

            $paramblock += $executionContext.InvokeCommand.ExpandString($parameterDefString)

            if ((Get-Member -InputObject $_ -Name 'Description') -and $_.Description)
            {
                $pDescription = $_.Description
                $paramHelp += $executionContext.InvokeCommand.ExpandString($helpParamStr)
            }
        }
        elseif((Get-Member -InputObject $_ -Name '$ref') -and ($_.'$ref'))
        {
        }
    }# $parametersSpec

    $paramblock = $paramBlock.TrimEnd().TrimEnd(",")
    $requiredParamList = $requiredParamList -join ', '
    $optionalParamList = $optionalParamList -join ', '

    #endregion Function Parameters

    # Handle the function body
    #region Function Body
    $infoVersion = $SwaggerSpecDefinitionsAndParameters['infoVersion']
    $modulePostfix = $SwaggerSpecDefinitionsAndParameters['infoName']
    $fullModuleName = $Namespace + '.' + $modulePostfix
    $clientName = '$' + $modulePostfix
    $apiVersion = $null
    $SubscriptionId = $null
    $BaseUri = $null

    if($Authentication -eq 'AzureStack')
    {
        $BaseUri = $AzureStackBaseUriStr -f ($clientName)
    }
    else
    {
        $SubscriptionId = $SubscriptionIdStr -f ($clientName)
        if (-not $UseAzureCsharpGenerator)
        {
            $apiVersion = $ApiVersionStr -f ($clientName, $infoVersion)
        }
    }

    $operationId = $JsonPathItemObject.operationId
    $opIdValues = $operationId -split '_',2 
    if(-not $opIdValues -or ($opIdValues.count -ne 2)) {
        $methodName = $operationId + 'WithHttpMessagesAsync'
        $operations = ''
    } else {            
        $operationName = $JsonPathItemObject.operationId.Split('_')[0]
        $operationType = $JsonPathItemObject.operationId.Split('_')[1]
        $operations = ".$operationName"
        if ((-not $UseAzureCsharpGenerator) -and 
            (Test-OperationNameInDefinitionList -Name $operationName -SwaggerSpecDefinitionsAndParameters $SwaggerSpecDefinitionsAndParameters))
        { 
            $operations = $operations + 'Operations'
        }
        $methodName = $operationType + 'WithHttpMessagesAsync'
    }

    $responseBodyParams = @{
                                responses = $jsonPathItemObject.responses.PSObject.Properties
                                namespace = $Namespace
                                definitionList = $SwaggerSpecDefinitionsAndParameters['definitionList']
    
    }

    $responseBody, $outputTypeBlock = Get-Response @responseBodyParams
    if ($Authentication -eq 'AzureStack') {
        $GetServiceCredentialStr = 'Get-AzSServiceCredential'
        $AdvancedFunctionEndCodeBlock = $AzSAdvancedFunctionEndCodeBlockStr
    }
    else {
        $GetServiceCredentialStr = 'Get-AzServiceCredential'
        $AdvancedFunctionEndCodeBlock = ''
    }    
    
    $body = $executionContext.InvokeCommand.ExpandString($functionBodyStr)

    #endregion Function Body

    $CommandString = $executionContext.InvokeCommand.ExpandString($advFnSignature)
    Write-Verbose -Message $CommandString

    if(-not (Test-Path -Path $GeneratedCommandsPath -PathType Container)) {
        $null = New-Item -Path $GeneratedCommandsPath -ItemType Directory
    }

    $CommandFilePath = Join-Path -Path $GeneratedCommandsPath -ChildPath "$CommandName.ps1"
    Out-File -InputObject $CommandString -FilePath $CommandFilePath -Encoding ascii -Force -Confirm:$false -WhatIf:$false

    return $CommandName
}

<#
.DESCRIPTION
  Gets Definition function details.
#>
function Get-SwaggerSpecDefinitionInfo
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSObject]
        $JsonDefinitionItemObject,

        [Parameter(Mandatory=$true)]
        [PSCustomObject] 
        $DefinitionFunctionsDetails,

        [Parameter(Mandatory=$true)]
        [string] 
        $Namespace 
    )

    $Name = $JsonDefinitionItemObject.Name.Replace('[','').Replace(']','')
    
    $FunctionDescription = ""
    if((Get-Member -InputObject $JsonDefinitionItemObject.Value -Name 'Description') -and 
       $JsonDefinitionItemObject.Value.Description)
    {
        $FunctionDescription = $JsonDefinitionItemObject.Value.Description
    }

    $DefinitionTypeNamePrefix = "$Namespace.Models."

    $x_ms_Client_flatten_DefinitionNames = @()
    $AllOf_DefinitionNames = @()

    $ParametersTable = @{}

    if((Get-Member -InputObject $JsonDefinitionItemObject.Value -Name 'AllOf') -and 
       $JsonDefinitionItemObject.Value.'AllOf')
    {
       $JsonDefinitionItemObject.Value.'AllOf' | ForEach-Object {
           $AllOfRefFullName = $_.'$ref'
           $AllOfRefName = $AllOfRefFullName.Substring( $( $AllOfRefFullName.LastIndexOf('/') ) + 1 )
           $AllOf_DefinitionNames += $AllOfRefName
                      
           $ReferencedFunctionDetails = @{}
           if($DefinitionFunctionsDetails.ContainsKey($AllOfRefName))
           {
               $ReferencedFunctionDetails = $DefinitionFunctionsDetails[$AllOfRefName]
           }

           $ReferencedFunctionDetails['Name'] = $AllOfRefName
           $ReferencedFunctionDetails['IsUsedAs_AllOf'] = $true
           $DefinitionFunctionsDetails[$AllOfRefName] = $ReferencedFunctionDetails
       }
    }

    $JsonDefinitionItemObject.Value.properties.PSObject.Properties | ForEach-Object {

        if((Get-Member -InputObject $_ -Name 'Name') -and $_.Name)
        {
            $ParameterJsonObject = $_.Value

            $ParameterDetails = @{}

            $IsParamMandatory = '$false'
            $ValidateSetString = $null
            $ParameterDescription = ''
            $parameterName = Get-PascalCasedString -Name $_.Name
            
            $paramType = if ( (Get-Member -InputObject $ParameterJsonObject -Name 'Type') -and $ParameterJsonObject.Type)
                         {
                            # Use the format as parameter type if that is available as a type in PowerShell
                            if ( (Get-Member -InputObject $ParameterJsonObject -Name 'Format') -and 
                                 $ParameterJsonObject.Format -and 
                                 ($null -ne ($ParameterJsonObject.Format -as [Type])) ) 
                            {
                                $ParameterJsonObject.Format
                            }
                            elseif ( ($ParameterJsonObject.Type -eq 'array') -and
                                     (Get-Member -InputObject $ParameterJsonObject -Name 'Items') -and 
                                     $ParameterJsonObject.Items)
                            {
                                if((Get-Member -InputObject $ParameterJsonObject.Items -Name '$ref') -and 
                                   $ParameterJsonObject.Items.'$ref')
                                {
                                    $ReferenceTypeValue = $ParameterJsonObject.Items.'$ref'
                                    $ReferenceTypeName = $ReferenceTypeValue.Substring( $( $ReferenceTypeValue.LastIndexOf('/') ) + 1 )
                                    $DefinitionTypeNamePrefix + "$ReferenceTypeName[]"
                                }
                                elseif((Get-Member -InputObject $ParameterJsonObject.Items -Name 'Type') -and $ParameterJsonObject.Items.Type)
                                {
                                    "$($ParameterJsonObject.Items.Type)[]"
                                }
                                else
                                {
                                    $ParameterJsonObject.Type
                                }                             
                            }
                            elseif ( ($ParameterJsonObject.Type -eq 'object') -and
                                     (Get-Member -InputObject $ParameterJsonObject -Name 'AdditionalProperties') -and 
                                     $ParameterJsonObject.AdditionalProperties)
                            {
                                $AdditionalPropertiesType = $ParameterJsonObject.AdditionalProperties.Type
                                "System.Collections.Generic.Dictionary[[$AdditionalPropertiesType],[$AdditionalPropertiesType]]"
                            }
                            else
                            {
                                $ParameterJsonObject.Type
                            }
                         }
                         elseif ( $parameterName -eq 'Properties' -and
                                  (Get-Member -InputObject $ParameterJsonObject -Name 'x-ms-client-flatten') -and 
                                  ($ParameterJsonObject.'x-ms-client-flatten') )
                         {                         
                             # 'x-ms-client-flatten' extension allows to flatten deeply nested properties into the current definition.
                             # Users often provide feedback that they don't want to create multiple levels of properties to be able to use an operation. 
                             # By applying the x-ms-client-flatten extension, you move the inner properties to the top level of your definition.

                             $ReferenceParameterValue = $ParameterJsonObject.'$ref'
                             $ReferenceDefinitionName = $ReferenceParameterValue.Substring( $( $ReferenceParameterValue.LastIndexOf('/') ) + 1 )

                             $x_ms_Client_flatten_DefinitionNames += $ReferenceDefinitionName

                             $ReferencedFunctionDetails = @{}
                             if($DefinitionFunctionsDetails.ContainsKey($ReferenceDefinitionName))
                             {
                                 $ReferencedFunctionDetails = $DefinitionFunctionsDetails[$ReferenceDefinitionName]
                             }

                             $ReferencedFunctionDetails['Name'] = $ReferenceDefinitionName
                             $ReferencedFunctionDetails['IsUsedAs_x_ms_client_flatten'] = $true
                             $DefinitionFunctionsDetails[$ReferenceDefinitionName] = $ReferencedFunctionDetails
                         }
                         elseif ( (Get-Member -InputObject $ParameterJsonObject -Name '$ref') -and ($ParameterJsonObject.'$ref') )
                         {
                            $ReferenceParameterValue = $ParameterJsonObject.'$ref'
                            $DefinitionTypeNamePrefix + $ReferenceParameterValue.Substring( $( $ReferenceParameterValue.LastIndexOf('/') ) + 1 )
                         }
                         else 
                         {
                             'object'
                         }

            if($paramType -eq 'Boolean')
            {
                $paramType = 'switch'
            }

            if ((Get-Member -InputObject $JsonDefinitionItemObject.Value -Name 'Required') -and 
                $JsonDefinitionItemObject.Value.Required -and
                ($JsonDefinitionItemObject.Value.Required -contains $parameterName) )
            {
                $IsParamMandatory = '$true'
            }

            if ((Get-Member -InputObject $ParameterJsonObject -Name 'Enum') -and $ParameterJsonObject.Enum)
            {
                if((Get-Member -InputObject $ParameterJsonObject -Name 'x-ms-enum') -and 
                   $ParameterJsonObject.'x-ms-enum' -and 
                   ($ParameterJsonObject.'x-ms-enum'.modelAsString -eq $false))
                {
                    $paramType = $DefinitionTypeNamePrefix + $ParameterJsonObject.'x-ms-enum'.Name
                }
                else
                {
                    $ValidateSet = $ParameterJsonObject.Enum
                    $ValidateSetString = "'$($ValidateSet -join "', '")'"
                }
            }

            if ((Get-Member -InputObject $ParameterJsonObject -Name 'Description') -and $ParameterJsonObject.Description)
            {
                $ParameterDescription = $ParameterJsonObject.Description
            }

            $ParameterDetails['Name'] = $parameterName
            $ParameterDetails['Type'] = $paramType
            $ParameterDetails['ValidateSet'] = $ValidateSetString
            $ParameterDetails['Mandatory'] = $IsParamMandatory
            $ParameterDetails['Description'] = $ParameterDescription

            if($paramType)
            {
                $ParametersTable[$parameterName] = $ParameterDetails
            }
        }
    }# $parametersSpec

    $Unexpanded_AllOf_DefinitionNames = $AllOf_DefinitionNames
    $Unexpanded_x_ms_client_flatten_DefinitionNames = $x_ms_Client_flatten_DefinitionNames
    $ExpandedParameters = (-not $Unexpanded_AllOf_DefinitionNames -and -not $Unexpanded_x_ms_client_flatten_DefinitionNames)

    $FunctionDetails = @{}
    if($DefinitionFunctionsDetails.ContainsKey($Name))
    {
        $FunctionDetails = $DefinitionFunctionsDetails[$Name]
    }

    $FunctionDetails['Name'] = $Name
    $FunctionDetails['Description'] = $FunctionDescription
    $FunctionDetails['ParametersTable'] = $ParametersTable
    $FunctionDetails['x_ms_Client_flatten_DefinitionNames'] = $x_ms_Client_flatten_DefinitionNames
    $FunctionDetails['AllOf_DefinitionNames'] = $AllOf_DefinitionNames
    $FunctionDetails['Unexpanded_x_ms_client_flatten_DefinitionNames'] = $Unexpanded_x_ms_client_flatten_DefinitionNames
    $FunctionDetails['Unexpanded_AllOf_DefinitionNames'] = $Unexpanded_AllOf_DefinitionNames
    $FunctionDetails['ExpandedParameters'] = $ExpandedParameters

    if(-not $FunctionDetails.ContainsKey('IsUsedAs_x_ms_client_flatten'))
    {
        $FunctionDetails['IsUsedAs_x_ms_client_flatten'] = $false
    }

    if(-not $FunctionDetails.ContainsKey('IsUsedAs_AllOf'))
    {
        $FunctionDetails['IsUsedAs_AllOf'] = $false
    }

    $DefinitionFunctionsDetails[$Name] = $FunctionDetails
}

<#
.DESCRIPTION
  Generates a cmdlet for the definition
#>
function New-SwaggerSpecDefinitionCommand
{
    [CmdletBinding()]
    param (
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $FunctionDetails,

        [Parameter(Mandatory=$true)]
        [string] 
        $GeneratedCommandsPath,

        [Parameter(Mandatory=$true)]
        [string] 
        $Namespace 
    )
    
    # TODO: remove as part of issue 21: Unify Functions
    $advFnSignature = @'
<#
$commandHelp
$paramHelp
#>
function $commandName
{
   param($paramblock
   )
   $body
}
'@

    $commandName = "New-$($FunctionDetails.Name)Object"

    $description = $FunctionDetails.description
    $commandHelp = $executionContext.InvokeCommand.ExpandString($helpDescStr)

    [string]$paramHelp = ""
    $paramblock = ""
    $body = ""
    $DefinitionTypeNamePrefix = "$Namespace.Models."

    $FunctionDetails.ParametersTable.Keys | ForEach-Object {
        $ParameterDetails = $FunctionDetails.ParametersTable[$_]

        $isParamMandatory = $ParameterDetails.Mandatory
        $parameterName = $ParameterDetails.Name
        $paramName = "`$$parameterName" 
        $paramType = $ParameterDetails.Type

        $ValidateSetDefinition = $null
        if ($ParameterDetails.ValidateSet)
        {
            $ValidateSetString = $ParameterDetails.ValidateSet
            $ValidateSetDefinition = $executionContext.InvokeCommand.ExpandString($ValidateSetDefinitionString)
        }
        $paramblock += $executionContext.InvokeCommand.ExpandString($parameterDefString)

        $pDescription = $ParameterDetails.Description
        $paramHelp += $executionContext.InvokeCommand.ExpandString($helpParamStr)
    }

    $paramblock = $paramBlock.TrimEnd().TrimEnd(",")

    $DefinitionTypeName = $DefinitionTypeNamePrefix + $FunctionDetails.Name
    $body = $executionContext.InvokeCommand.ExpandString($createObjectStr)

    $CommandString = $executionContext.InvokeCommand.ExpandString($advFnSignature)
    Write-Verbose -Message $CommandString

    if(-not (Test-Path -Path $GeneratedCommandsPath -PathType Container)) {
        $null = New-Item -Path $GeneratedCommandsPath -ItemType Directory
    }

    $CommandFilePath = Join-Path -Path $GeneratedCommandsPath -ChildPath "$CommandName.ps1"
    Out-File -InputObject $CommandString -FilePath $CommandFilePath -Encoding ascii -Force -Confirm:$false -WhatIf:$false

    return $CommandName
}

<#
.DESCRIPTION
  Converts an operation id to a reasonably good cmdlet name
#>
function Get-SwaggerPathCommandName
{
    param
    (
        [Parameter(Mandatory=$true)]
        [PSObject]
        $JsonPathItemObject    
    )

    if((Get-Member -InputObject $JsonPathItemObject -Name 'x-ms-cmdlet-name') -and $JsonPathItemObject.'x-ms-cmdlet-name') { 
        return $JsonPathItemObject.'x-ms-cmdlet-name'
    }

    $opId = $JsonPathItemObject.OperationId
    $cmdNounMap = @{
                    Create = 'New'
                    Activate = 'Enable'
                    Delete = 'Remove'
                    List   = 'GetAll'
                }
    $opIdValues = $opId  -split "_",2
    
    # OperationId can be specified without '_' (Underscore), return the OperationId as command name
    if(-not $opIdValues -or ($opIdValues.Count -ne 2)) {
        return $opId
    }

    $cmdNoun = $opIdValues[0]
    $cmdVerb = $opIdValues[1]
    if (-not (get-verb $cmdVerb))
    {
        $message = $LocalizedData.UnapprovedVerb -f ($cmdVerb)
        Write-Verbose "Verb $cmdVerb not an approved verb."
        if ($cmdNounMap.ContainsKey($cmdVerb))
        {
            $message = $LocalizedData.ReplacedVerb -f ($($cmdNounMap[$cmdVerb]), $cmdVerb)
            Write-Verbose -Message $message
            $cmdVerb = $cmdNounMap[$cmdVerb]
        }
        else
        {
            $idx=1
            for(; $idx -lt $opIdValues[1].Length; $idx++)
            { 
                if (([int]$opIdValues[1][$idx] -ge 65) -and ([int]$opIdValues[1][$idx] -le 90)) {
                    break
                }
            }
            
            $cmdNounSuffix = $opIdValues[1].Substring($idx)
            # Add command noun suffix only when the current noun is not ending with the same suffix. 
            if(-not $cmdNoun.EndsWith($cmdNounSuffix, [System.StringComparison]::OrdinalIgnoreCase)) {
                $cmdNoun = $cmdNoun + $opIdValues[1].Substring($idx)
            }
            
            $cmdVerb = $opIdValues[1].Substring(0,$idx)            
            if ($cmdNounMap.ContainsKey($cmdVerb)) { 
                $cmdVerb = $cmdNounMap[$cmdVerb]
            }          

            $message = $LocalizedData.UsingNounVerb -f ($cmdNoun, $cmdVerb)
            Write-Verbose -Message $message
        }
    }

    return "$cmdVerb-$cmdNoun"
}

function Get-SwaggerSpecDefinitionAndParameter
{
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $SwaggerSpecJsonObject,

        [Parameter(Mandatory=$true)]
        [string]
        $ModuleName
    )

    if(-not (Get-Member -InputObject $jsonObject -Name 'info')) {
        Throw $LocalizedData.InvalidSwaggerSpecification
    }

    $SwaggerSpecificationDetails = @{}    

    # Get info entries
    $info = $SwaggerSpecJsonObject.info 
    
    $infoVersion = '1-0-0'
    if((Get-Member -InputObject $info -Name 'Version') -and $info.Version) { 
        $infoVersion = $info.Version
    }

    $infoTitle = $info.title
    $infoName = ''
    if((Get-Member -InputObject $info -Name 'x-ms-code-generation-settings') -and $info.'x-ms-code-generation-settings'.Name) { 
        $infoName = $info.'x-ms-code-generation-settings'.Name
    }

    if (-not $infoName) {
         $infoName = $infoTitle
    }

    $SwaggerSpecificationDetails['infoVersion'] = $infoVersion
    $SwaggerSpecificationDetails['infoTitle'] = $infoTitle
    $SwaggerSpecificationDetails['infoName'] = $infoName
    $SwaggerSpecificationDetails['Version'] = [Version](($infoVersion -split "-",4) -join '.')
    $NamespaceVersionSuffix = "v$(($infoVersion -split '-',4) -join '')"
    $SwaggerSpecificationDetails['Namespace'] = "Microsoft.PowerShell.$ModuleName.$NamespaceVersionSuffix"
    $SwaggerSpecificationDetails['ModuleName'] = $ModuleName

    if(Get-Member -InputObject $jsonObject -Name 'parameters') {    
        # Get global parameters
        $globalParams = $SwaggerSpecJsonObject.parameters
        $globalParams.PSObject.Properties | ForEach-Object {
            $name = Get-PascalCasedString -Name $_.name
            $SwaggerSpecificationDetails[$name] = $globalParams.$name
        }
    }

    $definitionList = @{}
    if(Get-Member -InputObject $jsonObject -Name 'definitions') {
        # Get definitions list
        $definitions = $SwaggerSpecJsonObject.definitions
        $definitions.PSObject.Properties | ForEach-Object {
            $name = $_.name
            $definitionList.Add($name, $_)
        }
    }
    $SwaggerSpecificationDetails['definitionList'] = $definitionList

    return $SwaggerSpecificationDetails
}

function Get-PascalCasedString
{
    param([string] $Name)

    if($Name) {
        $Name = Remove-SpecialCharacter -Name $Name
        $startIndex = 0
        $subStringLength = 1

        # Convert the two letter abbreviations to upper case.
        # Example: vmName --> VMName
        if($Name.Length -gt 2) {
            $thirdCharString = $Name.substring(2, 1)
            if($thirdCharString.ToUpper() -ceq $thirdCharString) {
                $subStringLength = 2
            }
        }

        return $($Name.substring($startIndex, $subStringLength)).ToUpper() + $Name.substring($subStringLength)
    }

}

function Remove-SpecialCharacter
{
    param([string] $Name)

    $pattern = '[^a-zA-Z]'
    return ($Name -replace $pattern, '')
}

function Test-OperationNameInDefinitionList
{
    param(
        [string]
        $Name,

        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $SwaggerSpecDefinitionsAndParameters
    )

    $definitionList = $SwaggerSpecDefinitionsAndParameters['definitionList']
    if ($definitionList.ContainsKey($Name))
    {
        return $true
    }
    return $false
}

function Get-Response
{
    param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $responses,
        
        [Parameter(Mandatory=$true)]
        [String] $NameSpace, 

        [Parameter(Mandatory=$true)]        
        [hashtable] $definitionList
    )

    $outputTypeFlag = $false
    $responseBody = ""
    $outputType = ""
    $failWithDesc = ""

    $failWithDesc = ""
    $responses | ForEach-Object {
        $responseStatusValue = "'" + $_.Name + "'"
        $value = $_.Value

        switch($_.Name) {
            # Handle Success
            {200..299 -contains $_} {
                if(-not $outputTypeFlag -and (Get-member -inputobject $value -name "schema"))
                {
                    # Add the [OutputType] for the function
                    $OutputTypeParams = @{
                        "schema"  = $value.schema
                        "namespace" = $NameSpace 
                        "definitionList" = $definitionList
                    }

                    $outputType = Get-OutputType @OutputTypeParams
                    $outputTypeFlag = $true
                }
            }
            # Handle Client Error
            {400..499 -contains $_} {
                if($Value.description)
                {
                    $failureDescription = "Write-Error 'CLIENT ERROR: " + $value.description + "'"
                    $failWithDesc += $executionContext.InvokeCommand.ExpandString($failCase)
                }
            }
            # Handle Server Error
            {500..599 -contains $_} {
                if($Value.description)
                {
                    $failureDescription = "Write-Error 'SERVER ERROR: " + $value.description + "'"
                    $failWithDesc += $executionContext.InvokeCommand.ExpandString($failCase)
                }
            }
        }
    }

    $responseBody += $executionContext.InvokeCommand.ExpandString($responseBodySwitchCase)
    
    return $responseBody, $outputType
}

function Get-OutputType
{
    param
    (
        [Parameter(Mandatory=$true)]
        [PSCustomObject] $schema,

        [Parameter(Mandatory=$true)]
        [String] $NameSpace, 

        [Parameter(Mandatory=$true)]
        [hashtable] $definitionList
    )

    $outputType = ""
    if(Get-member -inputobject $schema -name '$ref')
    {
        $ref = $schema.'$ref'
        if($ref.StartsWith("#/definitions"))
        {
            $key = $ref.split("/")[-1]
            if ($definitionList.ContainsKey($key))
            {
                $definition = ($definitionList[$key]).Value
                if(Get-Member -InputObject $definition -name 'properties')
                {
                    $defProperties = $definition.properties
                    $fullPathDataType = ""

                    # If this data type is actually a collection of another $ref 
                    if(Get-member -InputObject $defProperties -Name 'value')
                    {
                        $defValue = $defProperties.value
                        $outputValueType = ""
                        
                        # Iff the value has items with $ref nested properties,
                        # this is a collection and hence we need to find the type of collection

                        if((Get-Member -InputObject $defValue -Name 'items') -and 
                            (Get-Member -InputObject $defValue.items -Name '$ref'))
                        {
                            $defRef = $defValue.items.'$ref'
                            if($ref.StartsWith("#/definitions")) 
                            {
                                $defKey = $defRef.split("/")[-1]
                                $fullPathDataType = $NameSpace + ".Models.$defKey"
                            }

                            if(Get-member -InputObject $defValue -Name 'type') 
                            {
                                $defType = $defValue.type
                                switch ($defType) 
                                {
                                    "array" { $outputValueType = '[]' }
                                    Default {
                                        $exception = $LocalizedData.DataTypeNotImplemented -f ($defType, $ref)
                                        throw [System.NotImplementedException] "Please get an implementation of $defType for $ref"
                                    }
                                }
                            }

                            if($outputValueType -and $fullPathDataType) {$fullPathDataType = $fullPathDataType + " " + $outputValueType}
                        }
                        else
                        { # if this datatype has value, but no $ref and items
                            $fullPathDataType = $NameSpace + ".Models.$key"
                        }
                    }
                    else
                    { # if this datatype is not a collection of another $ref
                        $fullPathDataType = $NameSpace + ".Models.$key"
                    }

                    $fullPathDataType = $fullPathDataType.Replace('[','').Replace(']','')
                    $outputType += $executionContext.InvokeCommand.ExpandString($outputTypeStr)
                }
            }
        }
    }

    return $outputType
}

function Get-CommandHelp
{
    param
    (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $PathObject
    )

    if((Get-Member -InputObject $PathObject -Name 'Description') -and $PathObject.Description) {
        $description = $PathObject.Description
    }

    $commandHelp = $executionContext.InvokeCommand.ExpandString($helpDescStr)

    return $commandHelp
}

function Get-ParamInfo
{
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $PathObject
    )

    $paramblock = ""
    $paramHelp = ""
    $requiredParamList = @()
    $optionalParamList = @()

    $PathObject.parameters | ForEach-Object {
        if((Get-Member -InputObject $_ -Name 'Name') -and $_.Name) 
        {
            $isParamMandatory = '$false'
            $parameterName = Get-PascalCasedString -Name $_.Name
            $paramName = "`$$parameterName"
            $paramType = if ( (Get-Member -InputObject $_ -Name 'Type') -and $_.Type)
                         {
                            # Use the format as parameter type if that is available as a type in PowerShell
                            if ( (Get-Member -InputObject $_ -Name 'Format') -and $_.Format -and ($null -ne ($_.Format -as [Type])) ) 
                            {
                                $_.Format
                            }
                            else {
                                $_.Type
                            }
                         } elseif ( (Get-Member -InputObject $_ -Name 'Schema') -and ($_.Schema) -and
                             (Get-Member -InputObject $_.Schema -Name '$ref') -and ($_.Schema.'$ref') )
                         {
                            $ReferenceParameterValue = $_.Schema.'$ref'
                            $Namespace + '.Models.' + $ReferenceParameterValue.Substring( $( $ReferenceParameterValue.LastIndexOf('/') ) + 1 )
                         }
                         else {
                             'object'
                         }
            if ($_.Required)
            { 
                $isParamMandatory = '$true'
                $requiredParamList += $paramName
            }
            else
            {
                $optionalParamList += $paramName
            }

            $ValidateSetDefinition = $null
            if ((Get-Member -InputObject $_ -Name 'ValidateSet') -and $_.ValidateSet)
            {
                $ValidateSetString = $_.ValidateSet
                $ValidateSetDefinition = $executionContext.InvokeCommand.ExpandString($ValidateSetDefinitionString)
            }

            $paramblock += $executionContext.InvokeCommand.ExpandString($parameterDefString)

            if ((Get-Member -InputObject $_ -Name 'Description') -and $_.Description)
            {
                $pDescription = $_.Description
                $paramHelp += $executionContext.InvokeCommand.ExpandString($helpParamStr)
            }            
        }
    }

    $paramblock = $paramBlock.TrimEnd().TrimEnd(",")
    $requiredParamList = $requiredParamList -join ', '
    $optionalParamList = $optionalParamList -join ', '

    $paramObject = @{ ParamHelp = $paramhelp;
                      ParamBlock = $paramBlock;
                      RequiredParamList = $requiredParamList;
                      OptionalParamList = $optionalParamList;
                    }

    return $paramObject
}

function Get-FunctionBody
{
    [OutputType([hashtable])]
    param
    (
        [Parameter(Mandatory = $true)]
        [PSObject]
        $PathObject,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $SwaggerMetaDict,

        [Parameter(Mandatory = $true)]
        [hashtable]
        $DefinitionList,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $RequiredParamList,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]
        $OptionalParamList,

        [Parameter(Mandatory = $true)]
        [hashTable]
        $Info
    )

    $infoVersion = $Info['infoVersion']
    $modulePostfix = $Info['infoName']
    $fullModuleName = $Namespace + '.' + $modulePostfix
    $clientName = '$' + $modulePostfix
    $apiVersion = $null
    $SubscriptionId = $null
    $BaseUri = $null

    if($Authentication -eq 'AzureStack')
    {
        $BaseUri = $AzureStackBaseUriStr -f ($clientName)
    }
    else
    {
        $SubscriptionId = $SubscriptionIdStr -f ($clientName)
        if (-not $UseAzureCsharpGenerator)
        {
            $apiVersion = $ApiVersionStr -f ($clientName, $infoVersion)
        }
    }

    $operationId = $PathObject.operationId
    $opIdValues = $operationId -split '_',2

    if(-not $opIdValues -or ($opIdValues.count -ne 2)) {
        $methodName = $operationId + 'WithHttpMessagesAsync'
        $operations = ''
    } else {            
        $operationName = $PathObject.operationId.Split('_')[0]
        $operationType = $PathObject.operationId.Split('_')[1]
        $operations = ".$operationName"
        if ((-not $SwaggerMetaDict['UseAzureCsharpGenerator']) -and 
                ($DefinitionList.containsKey($operationName)))
        { 
            $operations = $operations + 'Operations'
        }
        $methodName = $operationType + 'WithHttpMessagesAsync'
    }

    $responseBodyParams = @{
                            responses = $PathObject.responses.PSObject.Properties
                            namespace = $Namespace
                            definitionList = $DefinitionList
                        }

    $responseBody, $outputTypeBlock = Get-Response @responseBodyParams
    
    if ($SwaggerMetaDict['Authentication'] -eq 'AzureStack') {
        $GetServiceCredentialStr = 'Get-AzSServiceCredential'
        $AdvancedFunctionEndCodeBlock = $AzSAdvancedFunctionEndCodeBlockStr
    }
    else {
        $GetServiceCredentialStr = 'Get-AzServiceCredential'
        $AdvancedFunctionEndCodeBlock = ''
    }

    $body = $executionContext.InvokeCommand.ExpandString($functionBodyStr)

    $bodyObject = @{ OutputTypeBlock = $outputTypeBlock;
                     Body = $body;
                    }

    return $bodyObject
}

#endregion

#region Module Generation Helpers

function ConvertTo-CsharpCode
{
    param
    (
        [Parameter(Mandatory=$true)]
        [hashtable]
        $SwaggerDict,
        
        [Parameter(Mandatory = $true)]
        [hashtable]
        $SwaggerMetaDict
    )

    $message = $LocalizedData.GenerateCodeUsingAutoRest
    Write-Verbose -Message $message

    $autoRestExePath = get-command autorest.exe | ForEach-Object source
    if (-not $autoRestExePath)
    {
        throw $LocalizedData.AutoRestNotInPath
    }

    $outputDirectory = $SwaggerMetaDict['outputDirectory']
    $nameSpace = $SwaggerDict['info'].NameSpace
    $outAssembly = Join-Path $outputDirectory "$NameSpace.dll"
    $net45Dir = Join-Path $outputDirectory "Net45"
    $generatedCSharpPath = Join-Path $outputDirectory "Generated.Csharp"

    if (Test-Path $outAssembly)
    {
        $null = Remove-Item -Path $outAssembly -Force
    }

    if (Test-Path $net45Dir)
    {
        $null = Remove-Item -Path $net45Dir -Force -Recurse
    }

    $codeGenerator = "CSharp"
    
    $refassemlbiles = @("System.dll",
                        "System.Core.dll",
                        "System.Net.Http.dll",
                        "System.Net.Http.WebRequest",
                        "System.Runtime.Serialization.dll",
                        "System.Xml.dll",
                        "$PSScriptRoot\Generated.Azure.Common.Helpers\Net45\Microsoft.Rest.ClientRuntime.dll",
                        "$PSScriptRoot\Generated.Azure.Common.Helpers\Net45\Newtonsoft.Json.dll")

    if ($SwaggerMetaDict['UseAzureCsharpGenerator'])
    { 
        $codeGenerator = "Azure.CSharp"
        $refassemlbiles += "$PSScriptRoot\Generated.Azure.Common.Helpers\Net45\Microsoft.Rest.ClientRuntime.Azure.dll"
    }

    $null = & $autoRestExePath -AddCredentials -input $swaggerMetaDict['SwaggerSpecPath'] -CodeGenerator $codeGenerator -OutputDirectory $generatedCSharpPath -NameSpace $Namespace
    if ($LastExitCode)
    {
        throw $LocalizedData.AutoRestError
    }

    return $generatedCSharpPath
}

function Compile-Type {
    param(
        [string]$GeneratedCSharpPath,
        [string[]]$Frameworks,
        [string[]]$Runtimes,
        [string]$BuildProject,
        [string]$BuildConfig,
        [bool]$AutomaticBootstrap,
        [hashtable]$SwaggerMetaDict,
        [hashtable]$SwaggerDict
    )

    $outputDirectory = $SwaggerMetaDict['outputDirectory']
    $nameSpace = $SwaggerDict['info'].NameSpace

    $message = $LocalizedData.GenerateAssemblyFromCode
    Write-Verbose -Message $message

    $allCompileSuccess = $true
    $fullClrCompiled = $false
    $Frameworks | %{
        $framework = $_
        $Runtimes | %{
            $compileSuccess = $false
            $message = $LocalizedData.CompileForFrameworkAndRuntime -f ($framework, $_)
            Write-Verbose -Message $message
            $outAssembly = $null
            if ($framework -eq 'net45' -and (-not $fullClrCompiled)) {
                $outAssembly = Join-Path $outputDirectory "ref\net45\$nameSpace.dll"
                $compileSuccess = Compile-FullClr -GeneratedCSharpPath $GeneratedCSharpPath -OutputAssembly $outAssembly -SwaggerMetaDict $SwaggerMetaDict -Namespace $nameSpace
                # Even if this fails, don't try full CLR again!
                $fullClrCompiled = $true
            } else {
                $outAssembly = Join-Path $outputDirectory "ref\$framework\$_\$nameSpace.dll"
                $outDir = Join-Path $outputDirectory "ref\$framework\$_"
                $compileSuccess = Compile-CoreClr -GeneratedCSharpPath $GeneratedCSharpPath -Framework $framework -Runtime $_ -BuildProject $BuildProject -BuildConfig $BuildConfig -AutomaticBootstrap $AutomaticBootstrap -OutputDirectory $outDir -AssemblyName "$nameSpace.dll"
            }

            if ($compileSuccess) {
                $message = $LocalizedData.GeneratedAssembly -f ($outAssembly)
                Write-Verbose -Message $message
            } else {
                $message = $LocalizedData.UnableToGenerateAssembly -f ($outAssembly)
                Write-Error -Message $message
            }

            $allCompileSuccess = $allCompileSuccess -and $compileSuccess
        }
    }

    if (-not $allCompileSuccess) {
        throw $LocalizedData.CompileFailed
    }
}

function Compile-FullClr {
    param(
        [string]$GeneratedCSharpPath,
        [string]$OutputAssembly,
        [hashtable]$SwaggerMetaDict,
        [string]$Namespace
    )

    if (-not (Test-Path (Split-Path $OutputAssembly -Parent))) {
        New-Item (Split-Path $OutputAssembly -Parent) -ItemType Directory
    }

    $refassemblies = @("System.dll",
                        "System.Core.dll",
                        "System.Net.Http.dll",
                        "System.Net.Http.WebRequest",
                        "System.Runtime.Serialization.dll",
                        "System.Xml.dll",
                        "$PSScriptRoot\ref\Net45\Microsoft.Rest.ClientRuntime.dll",
                        "$PSScriptRoot\ref\Net45\Newtonsoft.Json.dll")

    if ($SwaggerMetaDict['UseAzureCsharpGenerator'])
    { 
        $refassemblies += "$PSScriptRoot\ref\Net45\Microsoft.Rest.ClientRuntime.Azure.dll"
    }

    $srcContent = Get-ChildItem -Path $GeneratedCSharpPath -Filter *.cs -Recurse -Exclude Program.cs,TemporaryGeneratedFile* | Where-Object DirectoryName -notlike '*Azure.Csharp.Generated*' | ForEach-Object { "// File $($_.FullName)"; get-content $_.FullName }
    $oneSrc = $srcContent -join "`n"

    Add-Type -TypeDefinition $oneSrc -ReferencedAssemblies $refassemblies -OutputAssembly $OutputAssembly

    # Copy net45 ref assemblies to common ref folder
    $commonRefFolder = Split-Path $OutputAssembly -Parent
    Copy-Item "$PSScriptRoot\ref\net45\*" "$commonRefFolder"

    return Test-Path -Path $OutputAssembly -PathType Leaf
}

function Compile-CoreClr {
    param(
        [string]$GeneratedCSharpPath,
        [string]$Framework,
        [string]$Runtime,
        [string]$BuildProject,
        [string]$BuildConfig,
        [bool]$AutomaticBootstrap,
        [string]$OutputDirectory,
        [string]$AssemblyName
    )

    # Setup dotnet CLI
    $ext = Setup-DotNetCli -AutomaticBootstrap $AutomaticBootstrap
    if ('' -eq $ext) {
        # dotnet CLI failed setup, which means we can't compile!
        return $false
    }

    # Validate build project type
    if (-not $BuildProject.EndsWith($ext)) {
        $message = $LocalizedData.CoreClrWrongBuildType -f ($BuildProject, $ext)
        Write-Error -Message $message
        return $false
    }

    # TODO: Remove when we support dotnet preview4+
    if (-not ($ext -eq 'json')) {
        $message = $LocalizedData.PsSwaggerSupportedDotNetCliVersion
        Write-Error -Message $message
        return $false
    }

    # Copy specified BuildProject and BuildConfig to C# path
    if ($null -ne $BuildConfig) {
        $buildConfigFileName = Split-Path $BuildConfig -Leaf
        Copy-Item $BuildConfig "$GeneratedCSharpPath\$buildConfigFileName" -Force
    }

    $buildProjectFileName = Split-Path $BuildProject -Leaf
    Copy-Item $BuildProject "$GeneratedCSharpPath\$buildProjectFileName" -Force

    # Compile with dotnet
    Push-Location $GeneratedCSharpPath
    & dotnet restore
    if (-not $?) {
        $message = $LocalizedData.DotNetFailedToRestorePackages
        Write-Error -Message $message
        return $false
    }

    & dotnet publish --framework $Framework --runtime $Runtime
    if (-not $?) {
        $message = $LocalizedData.DotNetFailedToBuild
        Write-Error -Message $message
        return $false
    }

    Pop-Location

    # Copy everything in publish directory as-is to ref folder
    if (-not (Test-Path $OutputDirectory)) {
        New-Item $OutputDirectory -ItemType Directory
    }

    Copy-Item "$GeneratedCSharpPath\bin\Debug\$Framework\$Runtime\publish\*" $OutputDirectory

    # Rename the generated dll to the expected dll
    # TODO: This only works for project.json based building
    $projectJsonObject = ConvertFrom-Json ((Get-Content (Join-Path $GeneratedCSharpPath "project.json")) -join [Environment]::NewLine) -ErrorAction Stop
    $dllName = $projectJsonObject.name
    Rename-Item -Path "$OutputDirectory\$dllName.dll" -NewName "$AssemblyName"
    if (-not $?) {
        return $false
    }

    return $true
}

function Setup-DotNetCli {
    param(
        [bool]$AutomaticBootstrap
    )

    $extension = ''
    if ($null -eq (Get-Command dotnet -ErrorAction SilentlyContinue)) {
        if (-not $AutomaticBootstrap) {
            $message = $LocalizedData.DotNetExeNotFound
            Write-Error -Message $message
            # Returns empty string indicating issue
            return $extension
        }

        # Run bootstrap.ps1 from tooling directory to download dotnet to tooling directory
        & "$PSScriptRoot\bootstrap.ps1"

        # bootstrap.ps1 is currently hardcoded to the json version of dotnet
        $extension = 'json'
    } else {
        # Run dotnet --version, assume preview versioning format
        $dotnetVersionOutput = & "dotnet" "--version"
        $message = $LocalizedData.DotNetExeNotFound -f ($dotnetVersionOutput)
        Write-Verbose -Message $message
        $regex = [regex]::Match($dotnetVersionOutput, '(.*?)preview([0-9]+)(.*)')
        $previewVersion = [int]$regex.captures.groups[2].value
        if ($previewVersion -ge 4) {
            $extension = 'csproj'
        } else {
            $extension = 'json'
        }
    }

    return $extension
}

function Copy-HelperModuleToGeneratedModule {
    param(
        [string]$ModuleDirectory,
        [string]$HelperDirectory,
        [string]$HelperModuleName
    )

    $message = $LocalizedData.DotNetExeNotFound -f ($HelperDirectory, $ModuleDirectory)
    Write-Verbose -Message $message
    if (-not (Test-Path "$ModuleDirectory\$HelperModuleName")) {
        New-Item "$ModuleDirectory\$HelperModuleName" -ItemType Directory
    }

    $null = Copy-Item "$HelperDirectory\*" "$ModuleDirectory\$HelperModuleName" -Recurse -Force
}

function New-ModuleManifestUtility
{
    param(
        [Parameter(Mandatory = $true)]
        [string]
        $Path,

        [Parameter(Mandatory = $true)]
        [string[]]
        $FunctionsToExport,

        [Parameter(Mandatory = $true)]        
        [PSCustomObject]
        $SwaggerSpecDefinitionsAndParameters
    )

    New-ModuleManifest -Path "$(Join-Path -Path $Path -ChildPath $SwaggerSpecDefinitionsAndParameters['ModuleName']).psd1" `
                       -ModuleVersion $SwaggerSpecDefinitionsAndParameters['Version'] `
                       -RootModule "$($SwaggerSpecDefinitionsAndParameters['ModuleName']).psm1" `
                       -FunctionsToExport $FunctionsToExport
}

# Utility to throw an errorrecord
function Write-TerminatingError
{
    param
    (        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.Management.Automation.PSCmdlet]
        $CallerPSCmdlet,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]        
        $ExceptionName,

        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ExceptionMessage,
        
        [System.Object]
        $ExceptionObject,
        
        [parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [System.String]
        $ErrorId,

        [parameter(Mandatory = $true)]
        [ValidateNotNull()]
        [System.Management.Automation.ErrorCategory]
        $ErrorCategory
    )
        
    $exception = New-Object $ExceptionName $ExceptionMessage;
    $errorRecord = New-Object System.Management.Automation.ErrorRecord $exception, $ErrorId, $ErrorCategory, $ExceptionObject    
    $CallerPSCmdlet.ThrowTerminatingError($errorRecord)
}

#endregion

#region Parse Swagger File

function ConvertTo-SwaggerDictionary
{
    param(
        [Parameter(Mandatory=$true)]
        [String]
        $SwaggerSpecPath,

        [Parameter(Mandatory=$true)]
        [string]
        $ModuleName
    )

    $swaggerObject = ConvertFrom-Json ((Get-Content $SwaggerSpecPath) -join [Environment]::NewLine) -ErrorAction Stop
    $swaggerDict = @{}

    if(-not (Get-Member -InputObject $swaggerObject -Name 'info')) {
        Throw $LocalizedData.InvalidSwaggerSpecification
    }

    $swaggerInfo = Get-SwaggerInfo -Info $swaggerObject.info
    $swaggerDict.Add("info", $swaggerInfo)

    if(-not (Get-Member -InputObject $swaggerObject -Name 'parameters')) {
        $message = $LocalizedData.SwaggerParamsMissing
        Throw $message
    }

    $swaggerParameters = Get-SwaggerParameters -Parameters $swaggerObject.parameters
    $swaggerDict.Add("parameters", $swaggerParameters)

    if(-not (Get-Member -InputObject $swaggerObject -Name 'definitions')) {
        $message = $LocalizedData.SwaggerDefinitionsMissing
        Throw  $message
    }

    $swaggerDefinitions = Get-SwaggerMultiItemObject -Object $swaggerObject.definitions
    $swaggerDict.Add("definitions", $swaggerDefinitions)

    if(-not (Get-Member -InputObject $swaggerObject -Name 'paths')) {
        $message = $LocalizedData.SwaggerPathsMissing
        Throw $message
    }

    $swaggerPaths = Get-SwaggerMultiItemObject -Object $swaggerObject.paths
    $swaggerDict.Add("paths", $swaggerPaths)

    return $swaggerDict
}

function Get-SwaggerInfo
{
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $Info
    )

    $infoVersion = '1-0-0'
    if((Get-Member -InputObject $Info -Name 'Version') -and $Info.Version) { 
        $infoVersion = $Info.Version
    }

    $infoTitle = $Info.title
    $infoName = ''
    if((Get-Member -InputObject $Info -Name 'x-ms-code-generation-settings') -and $Info.'x-ms-code-generation-settings'.Name) { 
        $infoName = $Info.'x-ms-code-generation-settings'.Name
    }

    if (-not $infoName) {
         $infoName = $infoTitle
    }

    $version = [Version](($infoVersion -split "-",4) -join '.')

    $NamespaceVersionSuffix = "v$(($infoVersion -split '-',4) -join '')"
    $Namespace = "Microsoft.PowerShell.$ModuleName.$NamespaceVersionSuffix"
    $ModuleName = $ModuleName

    $swaggerInfo = @{}
    $swaggerInfo.Add('InfoVersion',$infoVersion);
    $swaggerInfo.Add('InfoTitle',$infoTitle);
    $swaggerInfo.Add('InfoName',$infoName);
    $swaggerInfo.Add('Version',$version);
    $swaggerInfo.Add('NameSpace', $Namespace);
    $swaggerInfo.Add('ModuleName', $ModuleName);

    return $swaggerInfo
}

function Get-SwaggerParameters
{
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $Parameters
    )

    $swaggerParameters = @{}

    $Parameters.PSObject.Properties | ForEach-Object {
        $name = Get-PascalCasedString -Name $_.name
        $swaggerParameters[$name] = $Parameters.$name
    }

    return $swaggerParameters
}

function Get-SwaggerMultiItemObject
{
    param(
        [Parameter(Mandatory=$true)]
        [PSCustomObject]
        $Object
    )

    $swaggerMultiItemObject = @{}

    $Object.PSObject.Properties | ForEach-Object {
        $swaggerMultiItemObject[$_.name] = $_
    }

    return $swaggerMultiItemObject
}

#endregion Parse Swagger File

Export-ModuleMember -Function Export-CommandFromSwagger