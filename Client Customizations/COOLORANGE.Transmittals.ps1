#==============================================================================#
# (c) 2025 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

if ($processName -notin @('Connectivity.VaultPro')) {
	return
}

#region Class Definitions
class ReferenceSettings {
    [bool] $IncludeChildren
    [bool] $IncludeParents
    [bool] $IncludeRelated
    
    ReferenceSettings() {
        $this.IncludeChildren = $true
        $this.IncludeParents = $false
        $this.IncludeRelated = $false
    }
}

class Transmittal {
    [string] $Name
    [int] $Iteration
    [string] $Email
    [string] $Project
    [string] $Description
    [string] $State
    [System.Collections.ObjectModel.ObservableCollection[object]] $Links
    [ReferenceSettings] $ReferenceSettings

    Transmittal() {
        $this.Links = New-Object System.Collections.ObjectModel.ObservableCollection[object]
        $this.ReferenceSettings = [ReferenceSettings]::new()
    }
}

class MetaLink {
    [long] $CustEntId
    [long] $LatestId
    [long] $FileId
    [long] $FileMasterId
    [bool] $AddNative
    [bool] $AddPdf
    [bool] $AddDxf

    MetaLink() {}

    MetaLink([FileLink]$fileLink) {
        $this.CustEntId = $fileLink.CustEntId
        $this.LatestId = $fileLink.LatestId
        $this.FileId = $fileLink.FileId
        $this.FileMasterId = $fileLink.FileMasterId
        $this.AddNative = $fileLink.AddNative
        $this.AddPdf = $fileLink.AddPdf
        $this.AddDxf = $fileLink.AddDxf
    }
}

class FileLink : MetaLink {
    [string] $FileName
    [string] $FileRevision
    [string] $FileVersion
    [string] $Folder     
    [bool] $IsUpToDate

    FileLink() {}
}

class InternalLink {
    [long] $FileId
    [long] $Iteration
    [string] $LinkType
}
#endregion

#region Vault Events
Register-VaultEvent -EventName UpdateCustomEntityStates_Restrictions -Action {
    param($customObjects)

	foreach($customObject in $customObjects) {
        if ($customObject._CustomEntityName -eq "Transmittal" -and $customObject._NewState -eq "Publish") {
            $metaLinks = GetMetaLinks $customObject.Id
            if ($metaLinks.Count -le 0) {
                Add-VaultRestriction -EntityName $customObject.Name -Message "The Transmittal does not have Files included"
            }
            $outdatedMetaLink = $metaLinks | Where-Object { $_.LatestId -ne $_.FileId }
            if ($outdatedMetaLink) {
                $message = "The Transmittal includes files that are not in the latest version.`n`nDo you really want to publish?"
                $title = "COOLORANGE - Transmittal publishing"
                $answer = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowMessage($message, $title, [Autodesk.DataManagement.Client.Framework.Forms.Currency.ButtonConfiguration]::YesNo)
                if ($answer -ne "Yes") {
                    Add-VaultRestriction -EntityName $customObject.Name -Message "Transmittal publishing canceled"
                }
            }
        }
    }
}

Register-VaultEvent -EventName UpdateCustomEntityStates_Post -Action {
    param($customObjects, $successful)

    $notify = $false
	foreach($customObject in $customObjects) {
        if ($customObject._CustomEntityName -eq "Transmittal" -and $customObject._State -eq "Publish") {
            Add-VaultJob -Name "COOLORANGE.Transmittals" -Description "Creates a package and a report for Transmittal '$($customObject._Name)'" -Parameters @{
                "EntityId" = $customObject.Id
                "EntityClassId" = "CUSTENT"
            }
            $notify = $true
        }
    }

    if ($notify) {
        $message = "COOLORANGE powerJobs is now translating the included files and compiling a Transmittal package and a report.`n`nOnce finished, the Transmittal lifecycle changes to 'Ready to send'"
        $title = "COOLORANGE - Transmittal publishing"
        [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowMessage($message, $title, [Autodesk.DataManagement.Client.Framework.Forms.Currency.ButtonConfiguration]::Ok)
    }
}
#endregion

#region Context Menus
Add-VaultMenuItem -Location 'TransmittalContextMenu' -Name 'New...' -Submenu "<b>Transmittals</b>" -Action {
    param($entities)

    $schemes = $vault.NumberingService.GetNumberingSchemes("FILE", [Autodesk.Connectivity.WebServices.NumSchmType]::Activated)
    $scheme = $schemes | Where-Object { $_.Name -eq "Transmittal Scheme" }

    $transmittal = ShowTransmittalDialog -scheme $scheme
    if (-not $transmittal) {
        return
    }

    $custEnt = CreateNewTransmittal $scheme
    UpdateLinks $custEnt.Id $transmittal.Links
    UpdateTransmittalProperties $custEnt.Id $transmittal
    [System.Windows.Forms.SendKeys]::SendWait('{F5}')
}

Add-VaultMenuItem -Location 'TransmittalContextMenu' -Name 'Edit...' -Submenu "<b>Transmittals</b>" -Action {
    param($entities)

    $customObject = $entities[0]
    if ($customObject._State -ne "Open") {
        $message = "The Transmittal is in state '$($customObject._State)' and cannot be edited."
        $title = "COOLORANGE - Transmittal"
        $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowError($message, $title)
        return
    }

    $transmittal = ShowTransmittalDialog -customObject $customObject
    if (-not $transmittal) {
        return
    }

    UpdateLinks $customObject.Id $transmittal.Links
    UpdateTransmittalProperties $customObject.Id $transmittal
    [System.Windows.Forms.SendKeys]::SendWait('{F5}')
}

Add-VaultMenuItem -Location 'TransmittalContextMenu' -Name 'Duplicate...' -Submenu "<b>Transmittals</b>" -Action {
    param($entities)

    $schemes = $vault.NumberingService.GetNumberingSchemes("FILE", [Autodesk.Connectivity.WebServices.NumSchmType]::Activated)
    $scheme = $schemes | Where-Object { $_.Name -eq "Transmittal Scheme" }

    $transmittal = ShowTransmittalDialog -customObject $entities[0] -scheme $scheme
    if (-not $transmittal) {
        return
    }

    $custEnt = CreateNewTransmittal $scheme
    UpdateLinks $custEnt.Id $transmittal.Links
    UpdateTransmittalProperties $custEnt.Id $transmittal
    [System.Windows.Forms.SendKeys]::SendWait('{F5}')
}

Add-VaultMenuItem -Location 'TransmittalContextMenu' -Name 'Send...' -Submenu "<b>Transmittals</b>" -Action {
    param($entities)

    $customObject = $entities[0]
    if ($customObject._State -ne "Ready to send" -and $customObject._State -ne "Sent") {
        $message = "The Transmittal cannot be sent.`n`nChange the Transmittal state to 'Publish' and wait for COOLORANGE powerJobs to create the deliverables. Try again once the Transmittal state is 'Ready to send'."
        $title = "COOLORANGE - Transmittal"
        $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowError($message, $title)
        return
    }

    $message = "A new 'Transmittal History' entry gets created and an email message opened in Microsoft Outlook.`n`nDo you want to continue?"
    $title = "COOLORANGE - Transmittal"
    $answer = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowMessage($message, $title, [Autodesk.DataManagement.Client.Framework.Forms.Currency.ButtonConfiguration]::YesNo)
    if ($answer -ne "Yes") {
        return
    }

    $filesToAttach = @()
    $fileIdsToAttach = @()
    
    $internalLinks = GetInternalLinks $customObject.Id
    foreach($linkType in @("PDF", "ZIP")) {
        $iL = $internalLinks | Where-Object { $_.LinkType -eq $linkType }
        if (-not $iL) { return }

        $fileId = $iL | Sort-Object { $_.Name } | Select-Object -ExpandProperty FileId -Last 1
        $file = Get-VaultFile -FileId $fileId
        $file = (Save-VaultFile -File $file._FullPath -DownloadDirectory $env:TEMP)[0]
        $filesToAttach += $file.LocalPath
        $fileIdsToAttach += $file.Id
    }

    $templates = $vault.BehaviorService.GetAllEmailTemplates()
    $template = $templates | Where-Object { $_.Name -eq "Transmittal Template" }

    Add-Type -Path "C:\ProgramData\coolOrange\Client Customizations\Modules\DevExpress.RichEdit.v22.2.Core.dll"
    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId($null)
    
    $server = New-Object DevExpress.XtraRichEdit.RichEditDocumentServer
    $server.add_CalculateDocumentVariable({
        param($s, $e)

        $entityClassId = $e.VariableName.Split('.')[0]
        $sysName = $e.VariableName.Split('.')[1]

        $propDefIds = @()
        $propDef = $propDefs | Where-Object { $_.SysName -eq $sysName -and $_.EntClassAssocArray.EntClassId -contains $entityClassId }
        $propDefIds += $propDef.Id
        $propInsts = $vault.PropertyService.GetProperties($entityClassId, @($customObject.Id), $propDefIds)

        $e.Value = $propInsts[0].Val
        $e.Handled = $true
    })

    $byteArray = $template.Template
    $memoryStream = New-Object System.IO.MemoryStream
    $memoryStream.Write($byteArray, 0, $byteArray.Length)
    $memoryStream.Position = 0
    $loaded = $server.LoadDocument($memoryStream)
    if (-not $loaded) {
        throw "Document cannot be loaded!"
    }

    $subject = "$($template.Subject) ($($customObject.Name) - $($customObject.Project))"
    $email = $customObject.'Recipient (Email)'
    OpenOutlookEmail $email $subject $server.Document.HtmlText $server.Document.Text $filesToAttach
    
    if ($customObject._State -ne "Sent") {
        $definitions = $vault.LifeCycleService.GetAllLifeCycleDefinitions()
        $definition = $definitions  | Where-Object { $_.DispName -eq "Transmittal Process" }
        $state = $definition.StateArray | Where-Object { $_.DispName -eq "Sent" }
        $vault.CustomEntityService.UpdateCustomEntityLifeCycleStates(@($customObject.Id), @($state.Id), "Transmittal iteration $($customObject.Iteration) sent to $email")
    }

    CreateNewTransmittalHistory $customObject $fileIdsToAttach
}

Add-VaultMenuItem -Location ToolsMenu -Name "New..." -Submenu "<b>Transmittals</b>" -Action {
    $schemes = $vault.NumberingService.GetNumberingSchemes("FILE", [Autodesk.Connectivity.WebServices.NumSchmType]::Activated)
    $scheme = $schemes | Where-Object { $_.Name -eq "Transmittal Scheme" }

    $transmittal = ShowTransmittalDialog -scheme $scheme
    if (-not $transmittal) {
        return
    }

    $custEnt = CreateNewTransmittal $scheme
    UpdateLinks $custEnt.Id $transmittal.Links
    UpdateTransmittalProperties $custEnt.Id $transmittal
    [System.Windows.Forms.SendKeys]::SendWait('{F5}')
}

Add-VaultMenuItem -Location FileContextMenu -Name "Add to Transmittal..." -Submenu "<b>Transmittals</b>" -Action {
    param($entities)

    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
    $propDef = $propDefs | Where-Object { $_.DispName -eq "Custom Object Name" }
    $srchConds = New-Object System.Collections.Generic.List[Autodesk.Connectivity.WebServices.SrchCond]
    $srchCond = New-Object Autodesk.Connectivity.WebServices.SrchCond
    $srchCond.PropDefId = $propDef.Id
    $srchCond.SrchOper = 3
    $srchCond.SrchTxt = "Transmittal"
    $srchCond.PropTyp = [Autodesk.Connectivity.WebServices.PropertySearchType]::SingleProperty
    $srchCond.SrchRule = "Must"
    $srchConds.Add($srchCond)
    $propDef = $propDefs | Where-Object { $_.DispName -eq "State" }
    $srchConds = New-Object System.Collections.Generic.List[Autodesk.Connectivity.WebServices.SrchCond]
    $srchCond = New-Object Autodesk.Connectivity.WebServices.SrchCond
    $srchCond.PropDefId = $propDef.Id
    $srchCond.SrchOper = 3
    $srchCond.SrchTxt = "Open"
    $srchCond.PropTyp = [Autodesk.Connectivity.WebServices.PropertySearchType]::SingleProperty
    $srchCond.SrchRule = "Must"
    $srchConds.Add($srchCond)

    $bookmark = ""
    $status = $null
    $totalResults = @()
    while ($null -eq $status -or $totalResults.Count -lt $status.TotalHits) {
        $results = $vault.CustomEntityService.FindCustomEntitiesBySearchConditions($srchConds, $null, [ref]$bookmark, [ref]$status)
        if ($null -ne $results) {
            $totalResults += $results
        }
        else {
            break
        }
    }

    $custEnts = $totalResults

    if ($custEnts.Count -eq 0) {
        #TODO: future improvements: allow the user to create a new transmittal from a file
        $message = "No Transmittals found that are in state 'Open'. Please create a new 'Transmittals' first!`n`nThe operation will be terminated!"
        $title = "COOLORANGE - Transmittals"
        $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowWarning($message, $title, [Autodesk.DataManagement.Client.Framework.Forms.Currency.ButtonConfiguration]::Ok)
        return
    }

    #TODO: future improvements: allow the users to include children, parents or related documentation for the selected files
    $custEnt = ShowTransmittalSelectionDialog $custEnts
    if (-not $custEnt) {
        return
    }

    $metaLinks = @(GetMetaLinks $custEnt.Id)
    foreach($file in $entities) {
        $metaLink = GetMetaLink $file $custEnt.Id
        $metaLinks += $metaLink
    }

    $fileLinks = GetFileLinks $metaLinks
    UpdateLinks $custEnt.Id $fileLinks
}
#endregion

#region Tab
function GoToFile($fileId) {
    $file = $vault.DocumentService.GetFileById($fileId)
    $folder = $vault.DocumentService.GetFolderById($file.FolderId)
    $docFolder = New-Object Connectivity.Services.Document.Folder($folder)
    $docDocFolder = New-Object Connectivity.Explorer.Document.DocFolder($docFolder)
    $docFile = New-Object Connectivity.Services.Document.File($file)
    $feo = New-Object Connectivity.Explorer.Document.FileExplorerObject($docFile)
    $navCtx = New-Object Connectivity.Explorer.Framework.LocationContext($docDocFolder)
    $vwCtx = New-Object Connectivity.Explorer.Framework.LocationContext($feo, $docDocFolder)
    $sc = New-Object Connectivity.Explorer.Framework.ShortcutMgr+Shortcut 
    $sc.NavigationContext = $navCtx
    $sc.ViewContext = $vwCtx
    $sc.Select($null)    
}

function UpdateTabControlHeaderCheckbox() {
    UpdateHeaderCheckbox $tab_control
}

Add-VaultTab -Name "Transmittal" -EntityType Transmittal -Action {
	param($customObject)
    if (-not $customObject) { return }

    $transmittal = [Transmittal]::new()
    $transmittal.Name = $customObject.Name
    $transmittal.Iteration = $customObject.Iteration
    $transmittal.Email = $customObject.'Recipient (Email)'
    $transmittal.Project = $customObject.Project
    $transmittal.Description = $customObject.Description
    $transmittal.State = $customObject._State

    $metaLinks = @(GetMetaLinks $customObject.Id)
    $fileLinks = @(GetFileLinks $metaLinks)

    try {
        foreach($fileLink in $fileLinks) {
            if ($fileLink) {
                $transmittal.Links.Add($fileLink)
            }
        }
    } catch { }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Autodesk.DataManagement.Client.Framework.Forms
    $xamlFile = [xml](Get-Content "C:\ProgramData\coolOrange\Client Customizations\COOLORANGE.Transmittals.Tab.xaml")
    $tab_control = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlFile))
    ApplyVaultTheme $tab_control

    $dataGrid = $tab_control.FindName("FilesTable")
    $dataGrid.Items.SortDescriptions.Clear()
    $sortProperty = "FileName"
    $sortDirection = [System.ComponentModel.ListSortDirection]::Ascending
    $sortDescription = New-Object System.ComponentModel.SortDescription($sortProperty, $sortDirection)
    $dataGrid.Items.SortDescriptions.Add($sortDescription)
    foreach ($column in $dataGrid.Columns) {
        $column.SortDirection = $null
    }
    $targetColumn = $dataGrid.Columns | Where-Object { $_.SortMemberPath -eq $sortProperty }
    if ($targetColumn) {
        $targetColumn.SortDirection = $sortDirection
    }

    $tab_control.FindName("GoToZip").add_Click({
        $internalLinks = GetInternalLinks $customObject.Id
        $internalLinks = $internalLinks | Where-Object { $_.LinkType -eq "ZIP" }
        if (-not $internalLinks) { return }
        $fileId = $internalLinks | Sort-Object { $_.Name } | Select-Object -ExpandProperty FileId -Last 1
        GoToFile $fileId
    }.GetNewClosure())

    $tab_control.FindName("GoToPdf").add_Click({
        $internalLinks = GetInternalLinks $customObject.Id
        $internalLinks = $internalLinks | Where-Object { $_.LinkType -eq "PDF" }
        if (-not $internalLinks) { return }
        $fileId = $internalLinks | Sort-Object { $_.Name } | Select-Object -ExpandProperty FileId -Last 1
        GoToFile $fileId
    }.GetNewClosure())

    $tab_control.DataContext = $transmittal
    UpdateTabControlHeaderCheckbox
    return $tab_control
}
#endregion

#region Dialog Functions
function ShowTransmittalSelectionDialog([array]$custEnts, $selectedObjectName = $null) {
    $itemsSource = [System.Collections.ObjectModel.ObservableCollection[[System.Object]]]::new($custEnts)

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Autodesk.DataManagement.Client.Framework.Forms
    $xamlFile = [xml](Get-Content "C:\ProgramData\coolOrange\Client Customizations\COOLORANGE.Transmittals.Select.xaml")
    $window = [Windows.Markup.XamlReader]::Load( (New-Object System.Xml.XmlNodeReader $xamlFile) )
    ApplyVaultTheme $window

    $window.FindName("Object").ItemsSource = $itemsSource | Sort-Object { $_.Name } -Descending
    $window.FindName("Object").SelectedValue = $selectedObjectName
            
    $window.FindName('Ok').add_Click({
        $window.DialogResult = $true
        $window.Close()
    }.GetNewClosure())

    if ($window.ShowDialog()) {
        return $window.FindName("Object").SelectedItem
    }

    return $null
}

function SelectFiles($window, $includeChildren, $includeParents, $includeRelated) {
    $settings = New-Object Autodesk.DataManagement.Client.Framework.Vault.Forms.Settings.SelectEntitySettings
    $settings.OptionsWindow.SetParent("UseCurrentlyActiveWindow")
    $settings.ActionableEntityClassIds.Add("FILE") | Out-Null
    $settings.MultipleSelect = $true
    $settings.DialogCaption = "Select files to be added to the Transmittal '$($custEnt._Name)'"
    $settings.ConfigureActionButtons("Add to Transmittal", $null, $null, $null) | Out-Null

    $result = [Autodesk.DataManagement.Client.Framework.Vault.Forms.Library]::SelectEntity($vaultConnection, $settings)
    if (-not $result.SelectedEntities) { return $null }

    #[System.Windows.Input.Mouse]::OverrideCursor = [System.Windows.Input.Cursors]::Wait
    $window.Cursor = [System.Windows.Input.Cursors]::Wait
    $window.IsEnabled = $false

    $files = New-Object System.Collections.Generic.List[Autodesk.Connectivity.WebServices.File]
    $fileIds = @()
    $fileMasterIds = @()
    $result.SelectedEntities | ForEach-Object {
        $fileIds += $_.EntityIterationId
        $fileMasterIds += $_.EntityMasterId
    }

    $selectedFiles = $vault.DocumentService.GetFilesByIds($fileIds)
    $selectedFiles | ForEach-Object { $files.Add($_) }

    $cldAssocType = [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::None
    if ($includeChildren) {
        $cldAssocType = [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::Dependency
    }

    $parAssocType = [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::None
    if ($includeParents) {
        $parAssocType = [Autodesk.Connectivity.WebServices.FileAssociationTypeEnum]::Dependency
    }

    $assocArray = $vault.DocumentService.GetLatestFileAssociationsByMasterIds(
        $fileMasterIds,
        $parAssocType,
        $true, 
        $cldAssocType,
        $true, 
        $includeRelated,
        $false,
        $false)

    if ($assocArray.FileAssocs) {
        $assocArray.FileAssocs | ForEach-Object { 
            if ($_ -ne $null -and -not $files.Contains($_.CldFile)) {
                $files.Add($_.CldFile)
            }
            if ($_ -ne $null -and -not $files.Contains($_.ParFile)) {
                $files.Add($_.ParFile)
            }
        }
    }

    $window.IsEnabled = $true
    $window.Cursor = $null

    return $files
}

function UpdateWindowHeaderCheckbox() {
    UpdateHeaderCheckbox $window
}

function UpdateHeaderCheckbox($control) {
    $columns = New-Object 'System.Collections.Generic.Dictionary[[string],[string]]'
    $columns.Add('addNative', "CheckAllAddNative")
    $columns.Add('addPdf', "CheckAllAddPdf")
    $columns.Add('addDxf', "CheckAllAddDxf")
    foreach ($keyValue in $columns.GetEnumerator()) {
        $fieldName = $keyValue.Key
        $cbName = $keyValue.Value

        $transmittal  = $control.DataContext
        $allChecked = $transmittal.Links | Where-Object { $_.$fieldName } | Measure-Object | Select-Object -ExpandProperty Count
        $allUnchecked = $transmittal.Links | Where-Object { -not $_.$fieldName } | Measure-Object | Select-Object -ExpandProperty Count
        $total = $transmittal.Links.Count

        $checkBox = $control.FindName($cbName)
        if ($allChecked -eq $total) {
            $checkBox.IsChecked = $true
        } elseif ($allUnchecked -eq $total) {
            $checkBox.IsChecked = $false
        } else {
            $checkBox.IsChecked = $null
        }
    }
}

function ShowTransmittalDialog($customObject = $null, $scheme = $null) {
    $iteration = 0
    $email = ""
    $project = ""
    $description = ""
    $state = "Open"
    $metaLinks = @()
    $fileLinks = @()
    
    if ($customObject) {
        $name = $customObject.Name
        $iteration = $customObject.Iteration
        $email = $customObject.'Recipient (Email)'
        $project = $customObject.Project
        $description = $customObject.Description
        $state = $customObject._State
        $metaLinks = @(GetMetaLinks $customObject.Id)
        $fileLinks = GetFileLinks $metaLinks
    }

    if ($scheme) {
        $title = "Create Transmittal"
        $name = ""
        foreach($field in $scheme.FieldArray) {
            if ($field.FieldTyp -eq "Autogenerated") {
                $name += "#" * $field.Len
            }
            if ($field.FieldTyp -eq "Complex") {
                $name += "X" * $field.Len
                throw "'Complex' fields are not supported. Please configure a different Numbering Scheme!"
            }
            if ($field.FieldTyp -eq "Delimiter") {
                $name += $field.DelimVal
            }            
            if ($field.FieldTyp -eq "FixedText") {
                $name += $field.FixedTxtVal
            }
            if ($field.FieldTyp -eq "FreeText") {
                $name += "?"
                throw "'Free text' fields are not supported. Please configure a different Numbering Scheme!"
            }
            if ($field.FieldTyp -eq "PredefinedList") {
                $name += "???"
                throw "'Pre-defined list' fields are not supported. Please configure a different Numbering Scheme!"
            }
            if ($field.FieldTyp -eq "WorkgroupLabel") {
                $name += $field.Val
            }
        }
    } else {
        $title = "Edit Transmittal"
    }

    $transmittal = [Transmittal]::new()
    $transmittal.Name = $name
    $transmittal.Iteration = $iteration
    $transmittal.Email = $email
    $transmittal.Project = $project
    $transmittal.Description = $description
    $transmittal.State = $state
    $fileLinks | ForEach-Object { $transmittal.Links.Add($_) }

    Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, Autodesk.DataManagement.Client.Framework.Forms
    $xamlFile = [xml](Get-Content "C:\ProgramData\coolOrange\Client Customizations\COOLORANGE.Transmittals.xaml")
    $window = [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xamlFile))

    $currentTheme = [Autodesk.DataManagement.Client.Framework.Forms.SkinUtils.WinFormsTheme]::Instance.CurrentTheme
    if ($currentTheme -eq "Dark") {
        $window.FindName("Logo").Source = "C:\ProgramData\coolOrange\Client Customizations\Modules\Transmittals\Logo_Dark.png"
    } else {
        $window.FindName("Logo").Source = "C:\ProgramData\coolOrange\Client Customizations\Modules\Transmittals\Logo_Light.png"
    }
    
    $dataGrid = $window.FindName("FilesTable")
    $dataGrid.Items.SortDescriptions.Clear()
    $sortProperty = "FileName"
    $sortDirection = [System.ComponentModel.ListSortDirection]::Ascending
    $sortDescription = New-Object System.ComponentModel.SortDescription($sortProperty, $sortDirection)
    $dataGrid.Items.SortDescriptions.Add($sortDescription)
    foreach ($column in $dataGrid.Columns) {
        $column.SortDirection = $null
    }
    $targetColumn = $dataGrid.Columns | Where-Object { $_.SortMemberPath -eq $sortProperty }
    if ($targetColumn) {
        $targetColumn.SortDirection = $sortDirection
    }

    $dataGrid.add_LoadingRow({
        param($s, $e)
        $e.Row.Dispatcher.InvokeAsync({
            $cbs = FindVisualChildren -Parent $e.Row -Type ([System.Windows.Controls.CheckBox])
            foreach ($cb in $cbs) {
                $cb.add_Checked({ 
                    UpdateWindowHeaderCheckbox
                })
                $cb.add_Unchecked({
                    UpdateWindowHeaderCheckbox
                })
            }
        }.GetNewClosure())
    }.GetNewClosure())

    $checkAllNative = $window.FindName("CheckAllAddNative")
    $checkAllNative.Add_Click({
        $isChecked = $checkAllNative.IsChecked
        if ($null -eq $isChecked) {
            $checkAllNative.IsChecked = $isChecked = $false
        }
        foreach ($link in $transmittal.Links) {
            $link.AddNative = if ($isChecked -eq $true) { $true } elseif ($isChecked -eq $false) { $false } else { $link.AddNative }
        }
        $dataGrid.Items.Refresh()
    }.GetNewClosure())

    $checkAllPdf = $window.FindName("CheckAllAddPdf")
    $checkAllPdf.Add_Click({
        $isChecked = $checkAllPdf.IsChecked
        if ($null -eq $isChecked) {
            $checkAllPdf.IsChecked = $isChecked = $false
        }
        foreach ($link in $transmittal.Links) {
            $link.AddPdf = if ($isChecked -eq $true) { $true } elseif ($isChecked -eq $false) { $false } else { $link.AddPdf }
        }
        $dataGrid.Items.Refresh()
    }.GetNewClosure())

    $checkAllDxf = $window.FindName("CheckAllAddDxf")
    $checkAllDxf.Add_Click({
        $isChecked = $checkAllDxf.IsChecked
        if ($null -eq $isChecked) {
            $checkAllDxf.IsChecked = $isChecked = $false
        }
        foreach ($link in $transmittal.Links) {
            $link.AddDxf = if ($isChecked -eq $true) { $true } elseif ($isChecked -eq $false) { $false } else { $link.AddDxf }
        }
        $dataGrid.Items.Refresh()
    }.GetNewClosure())

    $window.FindName('Add').add_Click({
        try {
            $includeChildren = $transmittal.ReferenceSettings.IncludeChildren
            $includeParents = $transmittal.ReferenceSettings.IncludeParents
            $includeRelated = $transmittal.ReferenceSettings.IncludeRelated
            $files = SelectFiles $window $includeChildren $includeParents $includeRelated
            if (-not $files -or $files.Count -le 0) {
                return
            }

            $window.Cursor = [System.Windows.Input.Cursors]::Wait
            $window.IsEnabled = $false
            
            $newMetaLinks = @()        
            foreach($file in $files) {
                try {
                    $metaLink = GetMetaLink $file $customObject.Id
                    $newMetaLinks += $metaLink
                } catch {
                }
            }

            $fileLinks = GetFileLinks $newMetaLinks
            foreach($fileLink in $fileLinks) {
                $existingFileLinks = $transmittal.Links | Where-Object { $_.FileMasterId -eq $fileLink.FileMasterId }
                if (-not $existingFileLinks) {
                    $transmittal.Links.Add($fileLink)
                } else {
                    foreach($existingFileLink in $existingFileLinks) {
                        $transmittal.Links.Remove($existingFileLink)
                    }

                    $fileLink.AddNative = $existingFileLinks[0].AddNative
                    $fileLink.AddPdf = $existingFileLinks[0].AddPdf
                    $fileLink.AddDxf = $existingFileLinks[0].AddDxf
                    
                    $transmittal.Links.Add($fileLink)
                }
            }

            UpdateWindowHeaderCheckbox
        } catch {
            Write-Error $_
        } finally {
            $window.IsEnabled = $true
            $window.Cursor = $null
        }
    }.GetNewClosure())

    $window.FindName('Remove').add_Click({
        $grid = $window.FindName('FilesTable')

        while ($grid.SelectedItems.Count -gt 0) {
            $selectedItem = $grid.SelectedItem
            $l = $transmittal.Links | Where-Object { $_.LatestId -eq $selectedItem.LatestId -and $_.FileName -eq $selectedItem.FileName } | Select-Object -First 1
            $transmittal.Links.Remove($l)
        }
        UpdateWindowHeaderCheckbox
    }.GetNewClosure())

    $window.FindName('Update').add_Click({
        $updatedLinks = GetFileLinks $transmittal.Links $true
        $transmittal.Links.Clear()
        $updatedLinks | ForEach-Object { $transmittal.Links.Add($_) }
        #UpdateHeaderCheckbox $window
    }.GetNewClosure())    

    $window.FindName('Ok').add_Click({
        $isEmailValid = IsValidEmail $transmittal.Email
        if (-not $transmittal.Project -or -not $isEmailValid) {
            $message = "A valid 'Recipient (Email)' address and a 'Project' must to be specified before the Transmittal can be saved!"
            $title = "COOLORANGE - Transmittal"
            $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowError($message, $title)
            return
        }

        $window.DialogResult = $true
        $window.Close()
    }.GetNewClosure())

    $window.FindName("Title").Content = $title
    $window.DataContext = $transmittal
    UpdateWindowHeaderCheckbox
    
    ApplyVaultTheme $window
    if ($window.ShowDialog()) {
        return $transmittal
    }
    
    return $null
}
#endregion

#region Transmittal Functions
function CreateNewTransmittal($scheme) {
    $custEntDefs = $vault.CustomEntityService.GetAllCustomEntityDefinitions()
	$custEntDef = $custEntDefs | Where-Object { $_.DispName -eq "Transmittal" }
	$number = $vault.DocumentService.GenerateFileNumber($scheme.SchmID, $null)
	$custEnt = $vault.CustomEntityService.AddCustomEntity($custEntDef.Id, $number)

    return $custEnt
}

function CreateNewTransmittalHistory($customObject, [array]$fileIds) {
    $custEntDefs = $vault.CustomEntityService.GetAllCustomEntityDefinitions()
	$custEntDef = $custEntDefs | Where-Object { $_.DispName -eq "Transmittal (History)" }

    $schemes = $vault.NumberingService.GetNumberingSchemes("FILE", [Autodesk.Connectivity.WebServices.NumSchmType]::Activated)
    $scheme = $schemes | Where-Object { $_.Name -eq "Transmittal History Scheme" }
    $prefix = "$($customObject.Name)-$($customObject.Iteration)"
	$number = $vault.DocumentService.GenerateFileNumber($scheme.SchmID, $prefix)
	$custEnt = $vault.CustomEntityService.AddCustomEntity($custEntDef.Id, $number)

    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
    $propInstParams = @()

    $propDef = $propDefs | Where-Object { $_.DispName -eq "Recipient (Email)" }
    $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
    $propInstParam.PropDefId = $propDef.Id
    $propInstParam.Val = $customObject.'Recipient (Email)'
    $propInstParams += $propInstParam

    $propInstParamArray = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray
    $propInstParamArray.Items = $propInstParams
    $vault.CustomEntityService.UpdateCustomEntityProperties(@($custEnt.Id), @($propInstParamArray))    

    foreach($fileId in $fileIds) {
        $vault.DocumentService.AddLink($custEnt.Id, "FILE", $fileId, $null) | Out-Null
    }

    $vault.DocumentService.AddLink($customObject.Id, "CUSTENT", $custEnt.Id, $null) | Out-Null
    return $custEnt
}

function UpdateTransmittalProperties($custEntId, $transmittal) {
    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
    $propInstParams = @()

    $propDef = $propDefs | Where-Object { $_.DispName -eq "Iteration" }
    $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
    $propInstParam.PropDefId = $propDef.Id
    $propInstParam.Val = $transmittal.Iteration
    $propInstParams += $propInstParam

    $propDef = $propDefs | Where-Object { $_.DispName -eq "Recipient (Email)" }
    $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
    $propInstParam.PropDefId = $propDef.Id
    $propInstParam.Val = $transmittal.Email
    $propInstParams += $propInstParam

    $propDef = $propDefs | Where-Object { $_.DispName -eq "Project" }
    $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
    $propInstParam.PropDefId = $propDef.Id
    $propInstParam.Val = $transmittal.Project
    $propInstParams += $propInstParam

    $propDef = $propDefs | Where-Object { $_.DispName -eq "Description" }
    $propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
    $propInstParam.PropDefId = $propDef.Id
    $propInstParam.Val = $transmittal.Description
    $propInstParams += $propInstParam

    $propInstParamArray = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray
    $propInstParamArray.Items = $propInstParams
    $vault.CustomEntityService.UpdateCustomEntityProperties(@($custEntId), @($propInstParamArray))
}
#endregion

#region Link Functions
function GetMetaLink($file, $custEntId = $null) {
    if (-not $file) { 
        throw "Invalid parameters!" 
    }

    $addNative = $true
    $addPdf = $false
    $addDxf = $false
    $ext = [System.IO.Path]::GetExtension($file.Name).ToLower()
    if ($ext -in @(".ipt")) { 
        $addNative = $false
        $addDxf = $true
    }
    if ($ext -in @(".idw", ".dwg")) {
        $addNative = $false
        $addPdf = $true
    }

    $metaLink = [MetaLink]::new()
    $metaLink.CustEntId = $custEntId
    $metaLink.LatestId = $latest.Id
    $metaLink.FileId = $file.Id
    $metaLink.FileMasterId = $file.MasterId
    $metaLink.AddNative = $addNative
    $metaLink.AddPdf = $addPdf
    $metaLink.AddDxf = $addDxf

    return $metaLink
}

function GetMetaLinks($custEntId) {
    $metaLinks = @()
    $linkIds = @()
    $links = $vault.DocumentService.GetLinksByParentIds(@($custEntId), @("FILE"))
    if (-not $links) { return }
    $links | ForEach-Object { $linkIds += $_.Id }

    $metas = @($vault.DocumentService.GetMetaOnLinks($linkIds))
    for($i=0; $i -lt $linkIds.Count; $i++) {
        $meta = $metas[$i]
        try {
            $metaLink = ConvertFrom-Json $meta
            $metaLink = [MetaLink]$metaLink
            $metaLinks += $metaLink
        } catch {}
    }

    return $metaLinks
}

function GetInternalLinks($custEntId) {
    $internalLinks = @()

    $linkIds = @()
    $fileIds = @()
    $links = $vault.DocumentService.GetLinksByParentIds(@($custEntId), @("FILE"))
    if (-not $links) { return }

    $links | ForEach-Object { $linkIds += $_.Id }
    $links | ForEach-Object { $fileIds += $_.ToEntId }

    $metas = @($vault.DocumentService.GetMetaOnLinks($linkIds))
    for($i=0; $i -lt $fileIds.Count; $i++) {
        $meta = $metas[$i]
        $fileId = $fileIds[$i]
        try {
            $internalLink = ConvertFrom-Json $meta
            $internalLink = [InternalLink]$internalLink
            $internalLink.FileId = $fileId
            $internalLinks += $internalLink
        } catch {}
    }

    return $internalLinks
}

function GetFileLinks($metaLinks, $useLatest=$false) {
    $fileLinks = @()
    if (-not $metaLinks) { return $fileLinks }

    $fileIds = @()
    $metaLinks | ForEach-Object { $fileIds += $_.FileId }
    $latestFiles = $vault.DocumentService.GetLatestFilesByIds($fileIds)
    $currentFiles = $vault.DocumentService.GetFilesByIds($fileIds)
    $folderArrays = $vault.DocumentService.GetFoldersByFileMasterIds($latestFiles.MasterId)
    
    for($i=0; $i -lt $metaLinks.Count; $i++) {
        $metaLink = $metaLinks[$i]
        $latestFile = $latestFiles[$i]
        $currentFile = $currentFiles[$i]

        if ($useLatest) {
            $currentFile = $latestFile
        }

        $folder = $folderArrays[$i].Folders[0]

        $fileLink = [FileLink]::new()
        $fileLink.CustEntId = $metaLink.CustEntId
        $fileLink.LatestId = $latestFile.Id
        $fileLink.FileId = $metaLink.FileId
        $fileLink.FileMasterId = $metaLink.FileMasterId
        $fileLink.AddPdf = $metaLink.AddPdf
        $fileLink.AddNative = $metaLink.AddNative
        $fileLink.AddDxf = $metaLink.AddDxf
        
        $fileLink.FileName = $currentFile.Name
        $fileLink.FileRevision = "$($currentFile.FileRev.Label)/$($latestFile.FileRev.Label)"
        $fileLink.FileVersion = "$($currentFile.VerNum)/$($latestFile.VerNum)"
        $fileLink.Folder = $folder.FullName
        $fileLink.IsUpToDate = $currentFile.Id -eq $latestFile.Id

        if ($fileLink.FileRevision -eq "/") { $fileLink.FileRevision = "-/-" }

        $fileLinks += $fileLink
    }

    return $fileLinks
}

function UpdateLinks($custEntId, $fileLinks) {
    $linkIdsToDelete = @()
    $links = $vault.DocumentService.GetLinksByParentIds(@($custEntId), @("FILE"))
    if ($links) { 
        $linkIds = @()
        $links | ForEach-Object { $linkIds += $_.Id }
        $metas = @($vault.DocumentService.GetMetaOnLinks($linkIds))

        for($i=0; $i -lt $linkIds.Count; $i++) {
            $meta = $metas[$i]
            try {
                $metaLink = ConvertFrom-Json $meta
                $metaLink = [MetaLink]$metaLink
                $linkIdsToDelete += $linkIds[$i]
            } catch {}
        }
        $vault.DocumentService.DeleteLinks($linkIdsToDelete)        
    }

    $linksToAdd = New-Object 'System.Collections.Generic.Dictionary[[long],[string]]'
    foreach($fileLink in $fileLinks) {
        $metaLink = [MetaLink]::new($fileLink)
        $json = ConvertTo-Json -InputObject $metaLink -Compress
        try {
            $linksToAdd.Add($fileLink.FileId, $json)
        }
        catch {}
    }

    foreach ($keyValue in $linksToAdd.GetEnumerator()) {
        $vault.DocumentService.AddLink($custEntId, "FILE", $keyValue.Key, $keyValue.Value) | Out-Null
    }
}
#endregion

#region Dialog Helper
function FindVisualChildren([System.Windows.DependencyObject] $parent, [Type] $type) {
    $results = @()
    for ($i = 0; $i -lt [System.Windows.Media.VisualTreeHelper]::GetChildrenCount($Parent); $i++) {
        $child = [System.Windows.Media.VisualTreeHelper]::GetChild($Parent, $i)
        if ($child -is $Type) {
            $results += $child
        }
        $results += FindVisualChildren -Parent $child -Type $Type
    }
    return $results
}

function FindLogicalChildren([System.Windows.DependencyObject] $parent, [Type] $type) {
    $results = @()
    foreach ($child in [System.Windows.LogicalTreeHelper]::GetChildren($Parent)) {
        if ($child -is [System.Windows.DependencyObject]) {
            if ($child -is $Type) {
                $results += $child
            }
            $results += FindLogicalChildren -Parent $child -Type $Type
        }
    }
    return $results
}

function ApplyVaultTheme($control) {
    $currentTheme = [Autodesk.DataManagement.Client.Framework.Forms.SkinUtils.WinFormsTheme]::Instance.CurrentTheme
    $md = $control.Resources.MergedDictionaries[0]
    if (-not $md) { return }

    # Add the current theme to the resource dictionary
    $td = [System.Management.Automation.PSSerializer]::Deserialize([System.Management.Automation.PSSerializer]::Serialize($md, 20))
    $td.Source = New-Object Uri("pack://application:,,,/Autodesk.DataManagement.Client.Framework.Forms;component/SkinUtils/WPF/Themes/$($currentTheme)Theme.xaml", [System.UriKind]::Absolute)
    $control.Resources.MergedDictionaries.Clear()
    $control.Resources.MergedDictionaries.Add($td);
    $control.Resources.MergedDictionaries.Add($md);

    if ($control -is [Autodesk.DataManagement.Client.Framework.Forms.Controls.WPF.ThemedWPFWindow]) {
        # Set Vault to be the owner of the window
        $interopHelper = New-Object System.Windows.Interop.WindowInteropHelper($control)
        $interopHelper.Owner = (Get-Process -Id $PID).MainWindowHandle

        # Set the window style, depending on the current theme
        $styleKey = if ($currentTheme -eq "Default") { "DefaultThemedWindowStyle" } else { "DarkLightThemedWindowStyle" }
        $control.Style = $control.Resources.MergedDictionaries[0][$styleKey]    
    }
    elseif ($control -is [System.Windows.Controls.ContentControl]) {
        # powerEvents to reload the tab?!
    }
    else {
        return
    }

    # Workaround to fix the DataGrid colors in light theme
    if ($currentTheme -eq "Light") {
        $dataGrids = FindLogicalChildren -Parent $control -Type ([System.Windows.Controls.DataGrid])
        foreach ($dataGrid in $dataGrids) {
            $cellStyle = $dataGrid.CellStyle
            $trigger = New-Object Windows.Trigger
            $trigger.Property = [Windows.Controls.DataGridCell]::IsSelectedProperty
            $trigger.Value = $true
            $color = [System.Windows.Media.ColorConverter]::ConvertFromString("#e1f2fa")
            $brush = New-Object System.Windows.Media.SolidColorBrush $color
            $brush.Freeze()
            $trigger.Setters.Add((New-Object Windows.Setter([Windows.Controls.Control]::BackgroundProperty, $brush)))
            $trigger.Setters.Add((New-Object Windows.Setter([Windows.Controls.Control]::ForegroundProperty, [Windows.Media.Brushes]::Black)))
            $cellStyle.Triggers.Add($trigger)
            $dataGrid.CellStyle = $cellStyle            
        }
    }
}
#endregion

#region Email Helper
function IsValidEmail([string]$email) {
    try {
        $null = [System.Net.Mail.MailAddress]::new($email)
        $pattern = '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$'
        return $email -match $pattern
    } catch {
        return $false
    }
}

function OpenOutlookEmail([string]$email, [string] $subject, [string]$htmlBody, [string]$textBody, [array]$attachments) {
    $outlook = $null
    $mailItem = $null

    try {
        $outlook = New-Object -ComObject Outlook.Application
        $mailItem = $outlook.CreateItem(0)  # 0 = mail item

        $mailItem.Subject = $subject
        $mailItem.HTMLBody = $htmlBody
        foreach ($attachment in $attachments) {
            try {
                $mailItem.Attachments.Add($attachment) | Out-Null
            } catch {
                $message = $_
                $title = "COOLORANGE - Transmittal"
                $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowError($message, $title)
            }     
        }
        $mailItem.Recipients.Add($email) | Out-Null
        $mailItem.Display()
    }
    catch {
        $message = "Microsoft Outlook cannot be opened on this machine. Please contact your administrator!"
        $title = "COOLORANGE - Transmittal"
        $null = [Autodesk.DataManagement.Client.Framework.Forms.Library]::ShowError($message, $title)
        
<#
        $subject = [System.Uri]::EscapeDataString("$name - $project")
        $body = [System.Uri]::EscapeDataString($textBody)
        $body += [Environment]::NewLine
        $body += [Environment]::NewLine
        foreach ($fileToAttach in $filesToAttach) {
            $body += [Environment]::NewLine + $fileToAttach
        }
        Start-Process "mailto:$($email)?subject=$($subject)&body=$($body)"
#>
    } finally {
        if ($null -ne $mailItem) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($mailItem) | Out-Null }
        if ($null -ne $outlook) { [System.Runtime.Interopservices.Marshal]::ReleaseComObject($outlook) | Out-Null }
        [GC]::Collect()
        [GC]::WaitForPendingFinalizers()
    }
}
#endregion