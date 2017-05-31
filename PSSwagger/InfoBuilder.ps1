
class TestInfoBuilder : OpenAPI.NET.Modeler.SpecificationObjectVisitor
{
    [hashtable]$PathFunctionDetails
    [hashtable]$SwaggerDict
    [hashtable]$SwaggerMetaDict
    [hashtable]$DefinitionFunctionsDetails
    [hashtable]$ParameterGroupCache
    [hashtable]$MetadataDictionary
    [object]$CSharpCodeNamer
    TestInfoBuilder($PathFunctionDetails, $SwaggerDict, $SwaggerMetaDict, $DefinitionFunctionsDetails, $ParameterGroupCache, $metadataDictionary, $cSharpCodeNamer)
    {
        $this.PathFunctionDetails = $PathFunctionDetails
        $this.SwaggerDict = $SwaggerDict
        $this.SwaggerMetaDict = $SwaggerMetaDict
        $this.DefinitionFunctionsDetails = $DefinitionFunctionsDetails
        $this.ParameterGroupCache = $ParameterGroupCache
        $this.MetadataDictionary = $metadataDictionary # This stuff should come from our new metadata extensions
        $this.CSharpCodeNamer = $cSharpCodeNamer

        $this.Dispatches([OpenAPI.NET.Parser.v2.DocumentRoot])
        $this.Dispatches([OpenAPI.NET.Parser.v2.InfoObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.ContactObject])
        $this.Dispatches([OpenAPI.NET.Parser.v2.LicenseObject])
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Visit([OpenAPI.NET.Parser.SpecificationObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Visit: $($spec.GetType().Name)" -BackgroundColor DarkGreen
        return $this.Accept($spec, $phase)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.DocumentRoot]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Accept: $($spec.GetType().Name)" -BackgroundColor DarkGreen
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.InfoObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Accept: $($spec.GetType().Name)" -BackgroundColor DarkGreen
        $this.SwaggerDict['Info'] = @{
            DefaultCommandPrefix = $this.MetadataDictionary['DefaultCommandPrefix']
            ModuleName = $this.MetadataDictionary['ModuleName']
            Models = "Models"
            Version = $this.MetadataDictionary['ModuleVersion']
            CodeOutputDirectory = ''
            # For when these child objects don't exist
            ContactName = $null
            ProjectUri = $null
            ContactEmail = $null
            LicenseUri = $null
            LicenseName = $null
        }

        if ($spec.Version) {
            $this.SwaggerDict['Info']['InfoVersion'] = $spec.Version
        } else {
            $this.SwaggerDict['Info']['InfoVersion'] = '1-0-0'
        }
        $this.SwaggerDict['Info']['InfoTitle'] = $spec.Title
        $this.SwaggerDict['Info']['NameSpace'] = "Microsoft.PowerShell.$($this.MetadataDictionary['ModuleName']).v$(($this.MetadataDictionary['ModuleVersion']) -replace '\.','')"

        if (-not $this.SwaggerDict['Info']['InfoName'])  {
            $this.SwaggerDict['Info']['InfoName'] = ($spec.Title -replace '[^a-zA-Z0-9_]','')
        }

        if ($this.SwaggerDict['Info']['NameSpace'].Split('.', [System.StringSplitOptions]::RemoveEmptyEntries) -contains $this.SwaggerDict['Info']['InfoName']) {
            $this.SwaggerDict['Info']['InfoName'] = $this.SwaggerDict['Info']['InfoName'] + 'Client'
        }

        $this.SwaggerDict['Info']['Description'] = $spec.Description
        $this.SwaggerDict['Info']['Models'] = "Models"
        #return [OpenAPI.NET.Modeler.ModelBuildResult]::Skip()
        #$model = New-InfoContext -InfoDict $this.SwaggerDict['Info']
        $model = New-Object -TypeName InfoContext -ArgumentList $this.SwaggerDict['Info']
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($model)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.ContactObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Accept: $($spec.GetType().Name)" -BackgroundColor DarkGreen
        <#$this.SwaggerDict['Info']['ContactName'] = $spec.Name
        $this.SwaggerDict['Info']['ProjectUri'] = $spec.Url
        $this.SwaggerDict['Info']['ContactEmail']= $spec.Email
        
        return [OpenAPI.NET.Parser.ModelBuildResult]::Skip()#>
        $dict = @{
            ContactName = $spec.Name
            ProjectUri = $spec.Url
            ContactEmail = $spec.Email
        }

        #$model = New-DictionaryContext -Dictionary $dict
        $model = New-Object -TypeName DictionaryContext -ArgumentList $dict
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($model)
    }
    [OpenAPI.NET.Modeler.ModelBuildResult] Accept([OpenAPI.NET.Parser.v2.LicenseObject]$spec, [OpenAPI.NET.Modeler.ModelBuildPhase]$phase)
    {
        #Write-Host "Accept: $($spec.GetType().Name)" -BackgroundColor DarkGreen
        <#$this.SwaggerDict['Info']['LicenseUri'] = $spec.Url
        $this.SwaggerDict['Info']['LicenseName'] = $spec.Name
        
        return [OpenAPI.NET.Parser.ModelBuildResult]::Skip()#>
        $dict = @{
            LicenseUri = $spec.Url
            LicenseName = $spec.Name
        }

        #$model = New-DictionaryContext -Dictionary $dict
        $model = New-Object -TypeName DictionaryContext -ArgumentList $dict
        return [OpenAPI.NET.Modeler.ModelBuildResult]::Continue($model)
    }
}