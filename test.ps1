param(
	[switch]$Extensions,
	[switch]$Test,
	[switch]$New,
	$ev
)

.\Setup-AutoRest.ps1
Import-Module .\PSSwagger\PSSwagger.psd1 -verbose -force

$suffix = ""
if ($New) { $suffix = "New" }
if ($Extensions) {
Write-Host "Test: .\Tests\data\AzureExtensions\AzureExtensionsSpec.json"
New-PSSwaggerModule -SwaggerSpecPath .\Tests\data\AzureExtensions\AzureExtensionsSpec.json -Path .\Tests\Generated -Name NewModelTest2$suffix -UseAzureCsharpGenerator -IncludeCoreFxAssembly -Verbose -ErrorVariable $ev -New:$New
} elseif ($Test) {
Write-Host "Test: .\Tests\ParserTest.json"
New-PSSwaggerModule -SwaggerSpecPath .\Tests\ParserTest.json -Path .\Tests\Generated -Name NewModelTest3$suffix -UseAzureCsharpGenerator -IncludeCoreFxAssembly -Verbose -ErrorVariable $ev -New:$New
} else {
Write-Host "Test: .\Tests\AzResources.json"
New-PSSwaggerModule -SwaggerSpecPath .\Tests\AzResources.json -Path .\Tests\Generated -Name NewModelTest$suffix -UseAzureCsharpGenerator -IncludeCoreFxAssembly -Verbose -ErrorVariable $ev -New:$New
}