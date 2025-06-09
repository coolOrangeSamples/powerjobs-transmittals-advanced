Set-Location "C:\ProgramData\coolOrange\Transmittals"
Import-Module powerVault

Write-Host "Welcome to the Transmittal Setup!" -ForegroundColor Green
Write-Host "Press the 'return' key to start the setup process"
Read-Host
Clear-Host

Write-Host "Please enter your Autodesk Vault administrator credentials" -ForegroundColor Gray
$user = Read-Host -Prompt "User Name"
$password = Read-Host -Prompt "Password" -AsSecureString
$server = Read-Host -Prompt "Server"
$vaultName = Read-Host -Prompt "Vault"

$ptr = [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($password)
$params = @{ User = $user; Server = $server; Vault = $vaultName }
Open-VaultConnection @params -Password ([System.Runtime.InteropServices.Marshal]::PtrToStringUni($ptr))
[System.Runtime.InteropServices.Marshal]::ZeroFreeCoTaskMemUnicode($ptr)

if (-not $vault) {
	Clear-Host
	Write-Host "Cannot connect to Vault! Pleaes check the credentials and try again" -ForegroundColor Red
	Write-Host "Press the 'return' key to exit the setup"
	Read-Host
	return
} else {
	Clear-Host
}

Write-Host "Starting Transmittal setup..." -ForegroundColor Green

#region Settings
$transmittalDispName = "Transmittal"
$transmittalDispNamePlural = "Transmittals"

$numberingPrefix = "TRN"
$numberingLength = 5

$historyDispName = "Transmittal (History)"
$historyDispNamePlural = "Transmittals (History)"

$iconFile = "CustomObject.ico"
$rtfFile = "EmailTemplate.rtf"
#endregion

#region Functions
function CreateCustomEntityDefinition($dispName, $dispNamePlural, $iconFileLocation) {
	Write-Host "Creating Custom Object '$($dispName)'..." -ForegroundColor Green

	$image = New-Object Autodesk.Connectivity.WebServices.ByteArray
	$image.Bytes = [System.IO.File]::ReadAllBytes($iconFileLocation)

	$custEntDef = $vault.CustomEntityService.AddCustomEntityDefinition(
		[Guid]::NewGuid(),
		$dispName,
		$dispNamePlural,
		$image,
		@())

	return $custEntDef
}

function CreateCategoryAndRule($custEntDef) {
	Write-Host "Creating Category and Rules for '$($custEntDef.DispName)'..." -ForegroundColor Green

	$category = $vault.CategoryService.AddCategory(
		"CUSTENT", 
		[Guid]::NewGuid(), 
		$custEntDef.DispName, 
		-551354, #color=orange
		"Category for $($custEntDef.DispName)",
		[Autodesk.Connectivity.WebServices.BehaviorAssignmentType]::Assignable)

	$existingRuleSetCfg = $vault.CategoryService.GetCategoryRuleSetConfiguration("CUSTENT")
	$propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
	$namePropDef = $propDefs | Where-Object { $_.DispName -eq "Custom Object Name" }

	$condition = New-Object Autodesk.Connectivity.WebServices.PropDefCond
	$condition.PropDefId = $namePropDef.Id
	$condition.Oper = [Autodesk.Connectivity.WebServices.CondOpers]::EqualTo
	$condition.Val = $custEntDef.DispName
	
	$ruleSet = New-Object Autodesk.Connectivity.WebServices.RuleSet
	$ruleSet.Id = -1
	$ruleSet.DispName = $custEntDef.DispName
	$ruleSet.Desc = ""
	$ruleSet.CondArray = @($condition)
	
	$catRuleSet = New-Object Autodesk.Connectivity.WebServices.CatRuleSet
	$catRuleSet.CatId = $category.Id
	$catRuleSet.RuleSet = $ruleSet
	$catRuleSet.IsAct = $true
	
	$existingRuleSetCfg.RuleSetArray += $catRuleSet
	$null = $vault.CategoryService.UpdateCategoryRuleSetConfiguration(
		"CUSTENT",
		$existingRuleSetCfg)

	return $category
}

function CreatePropertyAndAssignToCategory($category, $propertyName, $propertyType) {
	Write-Host "Creating Property '$($propertyName)' for '$($category.Name)'..." -ForegroundColor Green

	$propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId($null)
	$propDef = $propDefs | Where-Object { $_.DispName -eq $propertyName }

	if ($propDef) {
		if ("CUSTENT" -notin $propDef.EntClassAssocArray.EntClassId) {
			$propDefInfo = $vault.PropertyService.GetPropertyDefinitionInfosByEntityClassId($null, @($propDef.Id))[0]
			$propDef = $propDefInfo.PropDef
			
			$assocs = @()
			$propDef.EntClassAssocArray | ForEach-Object { $assocs += $_ }

			$assoc = New-Object Autodesk.Connectivity.WebServices.EntClassAssoc
			$assoc.EntClassId = "CUSTENT"
			$assoc.MapDirection = [Autodesk.Connectivity.WebServices.AllowedMappingDirection]::ReadAndWrite
			$assocs += $assoc
			$propDef.EntClassAssocArray = $assocs

			$propDefInfo = $vault.PropertyService.UpdatePropertyDefinitionInfo(
				$propDef,
				$propDefInfo.EntClassCtntSrcPropCfgArray,
				$propDefInfo.PropConstrArray,
				$propDefInfo.ListValArray)
			
			$propDef = $propDefInfo.PropDef
		}
	} else {
		$propDefInfo = $vault.PropertyService.AddPropertyDefinition(
			[Guid]::NewGuid(),
			$propertyName,
			$propertyType,
			$true,
			$true,
			$null,
			@("CUSTENT"),
			@(),
			@(),
			$null)
		
		$propDef = $propDefInfo.PropDef
	}

	$null = $vault.CategoryService.UpdateCategoriesPropertyDefinitionAssignmentTypes(
		$propDef.Id,
		@($category.Id),
		@([Autodesk.Connectivity.WebServices.BehaviorAssignmentType]::Default),
		$null)
}

function CreateTransmittalNumberingScheme($prefix, $length, $name) {
	Write-Host "Creating Numbering Scheme '$($name)'..." -ForegroundColor Green
	$fields = @()

	$fixedTextField = New-Object Autodesk.Connectivity.WebServices.FixedTxtField
	$fixedTextField.Name = "Prefix"
	$fixedTextField.FixedTxtVal = $prefix
	$fields += $fixedTextField

	$delimiterField = New-Object Autodesk.Connectivity.WebServices.DelimField
	$delimiterField.DelimVal = '-'
	$fields += $delimiterField

	$autogenField = New-Object Autodesk.Connectivity.WebServices.AutogenField
	$autogenField.Name = "Number"
	$autogenField.Len = $length
	$autogenField.From = 1
	$autogenField.To = [System.Convert]::ToInt32("9" * $length)
	$autogenField.StepSize = 1
	$autogenField.ZeroPadding = $true
	$fields += $autogenField

	$defaultProvider = $vault.NumberingService.GetNumberingProviders()[0];
	$scheme = $vault.NumberingService.AddNumberingScheme(
		"FILE", 
		$name, 
		$defaultProvider.SysName, 
		$fields, 
		$false, 
		$false)

	$scheme = $vault.NumberingService.EnableNumberingSchemes($scheme.SchmID, $true)	
}

function CreateHistoryNumberingScheme($name) {
	Write-Host "Creating Numbering Scheme '$($name)'..." -ForegroundColor Green
	$fields = @()

	$freeTextField = New-Object Autodesk.Connectivity.WebServices.FreeTxtField
	$freeTextField.Name = "Transmittal"
	$freeTextField.DfltVal = "Unknown"
	$freeTextField.MinLen = 1
	$freeTextField.MaxLen = 10
	$freeTextField.FieldTyp = [Autodesk.Connectivity.WebServices.FieldType]::FixedText
	$fields += $freeTextField

	$delimiterField = New-Object Autodesk.Connectivity.WebServices.DelimField
	$delimiterField.DelimVal = '-'
	$fields += $delimiterField

	$autogenField = New-Object Autodesk.Connectivity.WebServices.AutogenField
	$autogenField.Name = "Index"
	$autogenField.Len = 4
	$autogenField.From = 1
	$autogenField.To = [System.Convert]::ToInt32("9" * 4)
	$autogenField.StepSize = 1
	$autogenField.ZeroPadding = $false
	$fields += $autogenField

	$defaultProvider = $vault.NumberingService.GetNumberingProviders()[0];
	$scheme = $vault.NumberingService.AddNumberingScheme(
		"FILE", 
		$name, 
		$defaultProvider.SysName, 
		$fields, 
		$false, 
		$false)

	$scheme = $vault.NumberingService.EnableNumberingSchemes($scheme.SchmID, $true)	
}

function CreateLifecycleDefinition($category, $name, $description) {
	Write-Host "Creating Lifecycle Definition '$($name)'..." -ForegroundColor Green

	$lcDefinition = $vault.LifeCycleService.AddLifeCycleDefinition(
		[Guid]::NewGuid(), 
		$name, 
		$description,
		[Autodesk.Connectivity.WebServices.SysAclBeh]::Combined)

	return $lcDefinition
}

function CreateLifecycleState($category, $lcDefinition, $name, $description, $color, $isDefault, $isReleasedState, $displayOrder) {
	Write-Host "Creating Lifecycle State '$($name)'..." -ForegroundColor Green

	$state = $vault.LifeCycleService.AddLifeCycleState(
		$lcDefinition.Id, 
		[Guid]::NewGuid(), 
		$name, 
		$description, 
		$color, 
		$isDefault, 
		$false, 
		@(),
		@(),
		$isReleasedState, 
		$false, 
		$displayOrder, 
		[Autodesk.Connectivity.WebServices.RestrictPurgeOption]::FirstAndLast,
		[Autodesk.Connectivity.WebServices.ItemToFileSecurityModeEnum]::None,
		@(),
		[Autodesk.Connectivity.WebServices.FolderFileSecurityModeEnum]::None,
		@())

	$vault.CategoryService.UpdateCategoriesBehaviorAssignmentTypes(
		"LifeCycle",
		$lcDefinition.Id,
		@($category.Id),
		@([Autodesk.Connectivity.WebServices.BehaviorAssignmentType]::Assignable)) | Out-Null

	$vault.CategoryService.UpdateCategoryBehaviorAssignmentTypes(
		$category.Id,
		"LifeCycle",
		[Autodesk.Connectivity.WebServices.AllowNoBehavior]::Yes,
		@($lcDefinition.Id), 
		@([Autodesk.Connectivity.WebServices.BehaviorAssignmentType]::Default), 
		$true) | Out-Null

	return $state
}

function CreateLifecycleTransition($fromState, $toState) {
	Write-Host "Creating Lifecycle Transition '$($fromState.DispName)' -> '$($toState.DispName)'..." -ForegroundColor Green

	$null = $vault.LifeCycleService.AddLifeCycleStateTransition(
		$fromState.Id,
		$toState.Id,
		[Autodesk.Connectivity.WebServices.EnforceChildStateEnum]::None, 
		[Autodesk.Connectivity.WebServices.EnforceContentStateEnum]::None,
		[Autodesk.Connectivity.WebServices.BumpRevisionEnum]::None,
		[Autodesk.Connectivity.WebServices.JobSyncPropEnum]::None,
		[Autodesk.Connectivity.WebServices.FileLinkTypeEnum]::None, 
		[Autodesk.Connectivity.WebServices.FileLinkTypeEnum]::None,
		$false, 
		$false,
		@(),
		@(),
		@(),
		@(),
		$false,
		$false)
}

function CreateEmailTempate($name, $description, $subject, $rtfFile) {
	Write-Host "Creating Email Template '$name'..." -ForegroundColor Green
	$templateFile = [System.IO.Path]::Combine((Get-Location).Path, $rtfFile)
	$template = Get-Content $templateFile -Encoding Byte

	$vault.BehaviorService.AddEmailTemplate($name, $description, $subject, $template)
}
#endregion

try {
	$iconFileLocation = [System.IO.Path]::Combine((Get-Location).Path, $iconFile)
	
	$transmittalCustEntDef = CreateCustomEntityDefinition $transmittalDispName $transmittalDispNamePlural $iconFileLocation
	$transmittalCategory = CreateCategoryAndRule $transmittalCustEntDef

	CreatePropertyAndAssignToCategory $transmittalCategory "Iteration" ([Autodesk.Connectivity.WebServices.DataType]::Numeric)
	CreatePropertyAndAssignToCategory $transmittalCategory "Recipient (Email)" ([Autodesk.Connectivity.WebServices.DataType]::String)
	CreatePropertyAndAssignToCategory $transmittalCategory "Project" ([Autodesk.Connectivity.WebServices.DataType]::String)
	CreatePropertyAndAssignToCategory $transmittalCategory "Description" ([Autodesk.Connectivity.WebServices.DataType]::String)

	$transmittalLcDef = CreateLifecycleDefinition $transmittalCategory "Transmittal Process" "Lifecycle for the Transmittal workflow"
	$stateOpen = CreateLifecycleState $transmittalCategory $transmittalLcDef "Open" "The Transmittal can be edited and files can be included" -16384 $true $false 0
	$statePublish = CreateLifecycleState $transmittalCategory $transmittalLcDef "Publish" "The Transmittal gets compiled by the Job Processor. Files get collected, translated, compressed and published and a reports is generated. Once ready, the Job Processor changes the state to 'Ready to send'" -1048576 $false $false 1
	$stateReady = CreateLifecycleState $transmittalCategory $transmittalLcDef "Ready to send" "The Transmittal is ready and can be sent" -16732080 $false $false 2
	$stateSent = CreateLifecycleState $transmittalCategory $transmittalLcDef "Sent" "The transmittal is ready and has been sent at least once" -16731920 $false $false 3
	
	CreateLifecycleTransition $stateOpen $statePublish
	CreateLifecycleTransition $stateOpen $stateReady
	CreateLifecycleTransition $stateOpen $stateSent
	CreateLifecycleTransition $statePublish $stateOpen
	CreateLifecycleTransition $statePublish $stateReady
	CreateLifecycleTransition $statePublish $stateSent
	CreateLifecycleTransition $stateReady $stateOpen
	CreateLifecycleTransition $stateReady $statePublish
	CreateLifecycleTransition $stateReady $stateSent
	CreateLifecycleTransition $stateSent $stateOpen
	CreateLifecycleTransition $stateSent $statePublish
	CreateLifecycleTransition $stateSent $stateReady

	CreateTransmittalNumberingScheme $numberingPrefix $numberingLength "Transmittal Scheme"
	CreateEmailTempate "Transmittal Template" "Email template used for the COOLORANGE Transmittals workflow" "Transmittal" $rtfFile

	$historyCustEntDef = CreateCustomEntityDefinition $historyDispName $historyDispNamePlural $iconFileLocation
	$historyCategory = CreateCategoryAndRule $historyCustEntDef

	CreatePropertyAndAssignToCategory $historyCategory "Recipient (Email)" ([Autodesk.Connectivity.WebServices.DataType]::String)
	CreateHistoryNumberingScheme "Transmittal History Scheme"

	Write-Host "The setup finished successfully" -ForegroundColor Green
	Write-Host "Restart Autodesk Vault to apply the changes, than adjust the Lifecycle state Security to your individual needs" -ForegroundColor Green
}
catch {
	Write-Host "An error occured while trying to setup the Transmittal worflow! Please contact COOLORANGE" -ForegroundColor Red
	Write-Host $_ -ForegroundColor Red

} finally {
	Write-Host "Press the 'return' key to exit the setup"
	Read-Host
}
