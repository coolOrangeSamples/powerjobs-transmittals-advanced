#==============================================================================#
# (c) 2025 coolOrange s.r.l.                                                   #
#                                                                              #
# THIS SCRIPT/CODE IS PROVIDED "AS IS" WITHOUT WARRANTY OF ANY KIND, EITHER    #
# EXPRESSED OR IMPLIED, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES  #
# OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE, OR NON-INFRINGEMENT.   #
#==============================================================================#

# Do not delete the next line. Required for the powerJobs Settings Dialog to determine the entity type for lifecycle state change triggers.
# JobEntityType = Transmittal

#region Settings
# RDLC Report location
$rdlcFileFullName = "C:\ProgramData\coolOrange\powerJobs\Jobs\COOLORANGE.Transmittals.rdlc"
# RDLC DataSet name
$rdlcDataSetName = "AutodeskVault_ReportDataSource"
# Vault folder to store Transmittal PDF and ZIP files
$transmittalFolder = "$/Transmittals"
#endregion

#region Debug
if (-not $IAmRunningInJobProcessor) {
    Import-Module powerJobs
    # https://doc.coolorange.com/projects/coolorange-powervaultdocs/en/stable/code_reference/commandlets/open-vaultconnection.html
    Open-VaultConnection

    $workingDirectory = "C:\TEMP\powerJobs Processor\Debug"
    $transmittalName = "TRN-00001"

    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
    $propDef = $propDefs | Where-Object { $_.DispName -eq "Name" }
    $srchConds = New-Object System.Collections.Generic.List[Autodesk.Connectivity.WebServices.SrchCond]
    $srchCond = New-Object Autodesk.Connectivity.WebServices.SrchCond
    $srchCond.PropDefId = $propDef.Id
    $srchCond.SrchOper = 3
    $srchCond.SrchTxt = $transmittalName
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

    if ($totalResults.Count -eq 0) { return }
    
    $custEnt = $totalResults[0]
    $global:customObject = New-Object Autodesk.DataManagement.Client.Framework.Vault.Currency.Entities.CustomObject($vaultConnection, $custEnt)

    $jobs = $vault.JobService.GetJobsByDate([int]::MaxValue, [DateTime]::MinValue)
    $job = $jobs | Where-Object { $_.Id -eq 69876 }
}
#endregion

Write-Host "Starting job '$($job.Name)'..."

#region Classes
class MetaLink {
    [long] $CustEntId
    [long] $LatestId
    [long] $FileId
    [long] $FileMasterId
    [bool] $AddNative
    [bool] $AddPdf
    [bool] $AddDxf

    MetaLink() {}
}
class InternalLink {
    [long] $FileId
    [long] $Iteration
    [string] $LinkType
}
#endregion

#region Report Functions
function GetReportColumnType([string]$typeName) {
	switch ($typeName) {
        "String" { return [System.String] }
        "Numeric" { return [System.Double] }
        "Bool" { return [System.Byte] }
        "DateTime" { return [System.DateTime] }
        "Image" { return [System.String] }
        Default { throw ("Type '$typeName' cannot be assigned to a .NET type") }
    }
}

function ReplaceInvalidColumnNameChars([string]$columnName) {
    $pattern = "[^A-Za-z0-9]"
    return [System.Text.RegularExpressions.Regex]::Replace($columnName, $pattern, "_")
}

function GetReportDataSet([Autodesk.Connectivity.WebServices.File[]]$files, [System.String]$reportFileLocation, [System.String]$reportDataSet) {
    $sysNames = @()
    [xml]$reportFileXmlDocument = Get-Content -Path $reportFileLocation
    $dataSets = $reportFileXmlDocument.Report.DataSets.ChildNodes | Where-Object {$_.Name -eq $reportDataSet} 
    $dataSets.Fields.ChildNodes | ForEach-Object {
        $sysNames += $_.DataField
    }
    
    $table = New-Object System.Data.DataTable -ArgumentList @($reportDataSet)
    $table.BeginInit()

    $propDefIds = @()
    $propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("FILE")
    $propDefs | ForEach-Object {
		if ($sysNames -icontains $_.SysName) { 
			$propDefIds += $_.Id
	        $type = GetReportColumnType $_.Typ

	        $column = New-Object System.Data.DataColumn -ArgumentList @(($_.SysName), $type)
	        $column.Caption = (ReplaceInvalidColumnNameChars $_.DispName)
	        $column.AllowDBNull = $true
	        $table.Columns.Add($column)
		}
    }

    $colEntityType = New-Object System.Data.DataColumn -ArgumentList @("EntityType", [System.String])
    $colEntityType.Caption = "Entity_Type"
    $colEntityType.DefaultValue = "File"
    $table.Columns.Add($colEntityType)
    
	$colEntityTypeId = New-Object System.Data.DataColumn -ArgumentList @("EntityTypeID", [System.String])
    $colEntityTypeId.Caption = "Entity_Type_ID"
    $colEntityTypeId.DefaultValue = "FILE"
	$table.Columns.Add($colEntityTypeId)

    $fileIds = @($files | Select-Object -ExpandProperty Id)
    $propInsts = $vault.PropertyService.GetProperties("FILE", $fileIds, $propDefIds)
    
    $table.EndInit()	
	$table.BeginLoadData()
    $files | ForEach-Object {
        $file = $_
        $row = $table.NewRow()
        
        $propInsts | Where-Object { $_.EntityId -eq $file.Id } | ForEach-Object {
            if ($_.Val) {
                $propDefId = $_.PropDefId
                $propDef = $propDefs | Where-Object { $_.Id -eq $propDefId }
                if ($propDef) {
                    if ($propDef.Typ -eq "Image") {
                        $val = [System.Convert]::ToBase64String($_.Val)
                    } else {
                        $val = $_.Val
                    }
                    $row."$($propDef.SysName)" = $val
                }
            }
        }
        $table.Rows.Add($row)
    }
	$table.EndLoadData()
	$table.AcceptChanges()
	
    return ,$table
}

function CreateReport($reportFileLocation, $reportDataSet, $files, $reportFileName, $parameters) {
    Write-Host "Creating RDLC report '$($reportFileLocation | Split-Path -Leaf)'..."
    [System.Reflection.Assembly]::LoadWithPartialName("Microsoft.ReportViewer`.WinForms") | Out-Null
        
    $table = GetReportDataSet $files $reportFileLocation $reportDataSet
    
    $xmlDocument = New-Object System.Xml.XmlDocument
    $xmlDocument.Load($reportFileLocation)
    
    $localReport = New-Object Microsoft.Reporting.WinForms.LocalReport
    $stringReader = New-Object System.IO.StringReader -ArgumentList @($xmlDocument.OuterXml)
    
    $localReport.LoadReportDefinition($stringReader)
    $stringReader.Close()
    $stringReader.Dispose()
    
    $paramNames = $localReport.GetParameters() | Select-Object { $_.Name } -ExpandProperty Name    
    $parameterList = New-Object System.Collections.Generic.List[Microsoft.Reporting.WinForms.ReportParameter]
    foreach($parameter in $parameters.GetEnumerator()) {
		if ($paramNames -contains $parameter.Key) {
            $value = $parameter.Value
            if ($null -eq $value) { $value = "" }
	        $param = New-Object Microsoft.Reporting.WinForms.ReportParameter -ArgumentList @($parameter.Key, $value)
	        $parameterList.Add($param)
		}
    }
    $localReport.SetParameters($parameterList)
    
    $reportDataSource = New-Object -TypeName Microsoft.Reporting.WinForms.ReportDataSource -ArgumentList @($table.TableName, [System.Data.DataTable]$table)
    $localReport.DataSources.Add($reportDataSource)
    $bytes = $localReport.Render("PDF");
    
    $localPdfFolder = $reportFileName | Split-Path -Parent
    if (-not [System.IO.Directory]::Exists($localPdfFolder)) {
        [System.IO.Directory]::CreateDirectory($localPdfFolder) | Out-Null
    }
    
    if ([System.IO.File]::Exists($reportFileName)) {
        [System.IO.File]::Delete($reportFileName)
    }
    
    [System.IO.File]::WriteAllBytes($reportFileName, $bytes)
    Write-Host "Report saved as PDF to '$reportFileName'"
}
#endregion

#region Download Functions
function DownloadFiles($files) {
    $results = [System.Collections.Generic.Dictionary[[Autodesk.Connectivity.WebServices.File], [string]]]::new()

    $s = [Autodesk.DataManagement.Client.Framework.Vault.Settings.AcquireFilesSettings]::new($vaultConnection)
    $s.LocalPath = [Autodesk.DataManagement.Client.Framework.Currency.FolderPathAbsolute]::new($workingDirectory)
    $s.OptionsRelationshipGathering.FileRelationshipSettings.IncludeChildren = $true
    $s.OptionsRelationshipGathering.FileRelationshipSettings.RecurseChildren = $true
    $s.OptionsRelationshipGathering.FileRelationshipSettings.VersionGatheringOption = "Latest"
    $s.OptionsRelationshipGathering.FileRelationshipSettings.IncludeLibraryContents = $true
    foreach($file in $files) {
        $fileIteration = [Autodesk.DataManagement.Client.Framework.Vault.Currency.Entities.FileIteration]::new($vaultConnection, $file)
        $s.AddFileToAcquire($fileIteration, "Download")
    }
    $acquireFilesResults = $vaultConnection.FileManager.AcquireFiles($s)
    foreach ($fileResult in $acquireFilesResults.FileResults) {
        if (-not $results.ContainsKey($fileResult.File)) {
            $results.Add($fileResult.File, $fileResult.LocalPath)
        }
    }

    Write-Host "$($results.Count) files downloaded"
    return $results
}
#endregion

#region Publish Functions
function PublishFile($file, $fullFileName, $isNative, $isPdf, $isDxf, $packageDirectory) {
    Write-Host "Publishing file '$($file.Name)'..."

    $extension = [System.IO.Path]::GetExtension($file.Name)
    $nativeFileCopied = $false
    if ($isNative) {
        Write-Host "Adding native file '$($file.Name)' to package..."
        Copy-Item $fullFileName -Destination $packageDirectory -Force | Out-Null
        $nativeFileCopied = $true
    }

    if (-not $isPdf -and -not $isDxf) {
        return
    }

    try {
        $openResult = $true
        $pdfExportResult = $true
        $dxfExportResult = $true
        $closeResult = $true

        $openResult = Open-Document -LocalFile $fullFileName
        if ($openResult) {
            if ($isPdf) {
                if ( @(".idw", ".dwg") -notcontains $extension ) {
                    Write-Host "The file '$($file._Name)' cannot be exported to PDF!"
                    if (-not $nativeFileCopied) {
                        Write-Host "Adding native file '$($file.Name)' to package..."
                        Copy-Item $fullFileName -Destination $packageDirectory -Force | Out-Null
                        $nativeFileCopied = $true
                    }
                } else {
                    Write-Host "Generating PDF file..."
                    $pdfFileName = "$($file.Name).pdf"
                    $localPDFfileLocation = "$workingDirectory\$pdfFileName"
                    if ($openResult.Application.Name -like 'Inventor*') {
                        $configFile = "$($env:POWERJOBS_MODULESDIR)Export\PDF_2D.ini"
                    } else {
                        $configFile = "$($env:POWERJOBS_MODULESDIR)Export\PDF.dwg"
                    }
                    $pdfExportResult = Export-Document -Format 'PDF' -To $localPDFfileLocation -Options $configFile
                    if ($pdfExportResult) {
                        Copy-Item -Path $localPDFfileLocation -Destination $packageDirectory
                    }                      
                }
            }

            if ($isDxf) {
                if (@(".idw", ".dwg", ".ipt") -notcontains $extension -or ($extension -eq ".ipt" -and $openResult.Document.Instance.ComponentDefinition.Type -ne [Inventor.ObjectTypeEnum]::kSheetMetalComponentDefinitionObject)) {
                    Write-Host "The file '$($file._Name)' is not a sheet metal part and cannot be exported to DXF!"
                    if (-not $nativeFileCopied) {
                        Write-Host "Adding native file '$($file.Name)' to package..."
                        Copy-Item $fullFileName -Destination $packageDirectory -Force | Out-Null
                        $nativeFileCopied = $true
                    }
                } else {
                    Write-Host "Generating DXF file..."
                    $dxfFileName = "$($file.Name).dxf"
                    $localDXFfileLocation = "$workingDirectory\$dxfFileName"
                    if ($extension -eq ".ipt") { 
                        $configFile = "$($env:POWERJOBS_MODULESDIR)Export\DXF_SheetMetal.ini"
                    } else {
                        $configFile = "$($env:POWERJOBS_MODULESDIR)Export\DXF_2D.ini"
                    }
                    $dxfExportResult = Export-Document -Format 'DXF' -To $localDXFfileLocation -Options $configFile
                    if ($dxfExportResult) {
                        $exportedFiles = Get-ChildItem -Path "$workingDirectory\*" -Include "$($localDXFfileLocation.BaseName)*.dxf", "$($localDXFfileLocation.BaseName)*.zip"
                        foreach ($exportedFile in $exportedFiles) {
                            Copy-Item -Path $exportedFile -Destination $packageDirectory
                        }
                    }
                }
            }

            $closeResult = Close-Document
        }

        if (-not $openResult) {
            throw("Failed to open document $($file.Name)! Reason: $($openResult.Error.Message)")
        }
        if (-not $pdfExportResult) {
            throw("Failed to export document $($file.Name)! Reason: $($pdfExportResult.Error.Message)")
        }
        if (-not $dxfExportResult) {
            throw("Failed to export document $($file.Name)! Reason: $($dxfExportResult.Error.Message)")
        }
        if (-not $closeResult) {
            throw("Failed to close document $($file.Name)! Reason: $($closeResult.Error.Message))")
        }            
    } catch {
        Write-Error $_
    }
}
#endregion

Write-Host "Reading Transmittal properties..."
#region Reading Transmittal properties
$propDefs = $vault.PropertyService.GetPropertyDefinitionsByEntityClassId("CUSTENT")
$propDefIds = @()
$iterationPropDef = $propDefs | Where-Object { $_.DispName -eq "Iteration" }
$propDefIds += $iterationPropDef.Id
$projectPropDef = $propDefs | Where-Object { $_.DispName -eq "Project" }
$propDefIds += $projectPropDef.Id
$recepientPropDef = $propDefs | Where-Object { $_.DispName -eq "Recipient (Email)" }
$propDefIds += $recepientPropDef.Id

$propInsts = $vault.PropertyService.GetProperties("CUSTENT", @($custEnt.Id), $propDefIds)
[long]$iteration = ($propInsts | Where-Object { $_.PropDefId -eq $iterationPropDef.Id }).Val
$project = ($propInsts | Where-Object { $_.PropDefId -eq $projectPropDef.Id }).Val
$recepient = ($propInsts | Where-Object { $_.PropDefId -eq $recepientPropDef.Id }).Val

$iteration++
#endregion

Write-Host "Querying files..."
#region Querying files
$metaLinks = @()
$linkIds = @()
$links = $vault.DocumentService.GetLinksByParentIds(@($custEnt.Id), @("FILE"))
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

$fileIds = @()
$metaLinks | Where-Object { $_.AddNative -or $_.AddPdf -or $_.AddDxf } | ForEach-Object { $fileIds += $_.FileId }
$files = $vault.DocumentService.GetFilesByIds($fileIds)

$allFileIds = @()
$metaLinks | ForEach-Object { $allFileIds += $_.FileId }
$allFiles = $vault.DocumentService.GetFilesByIds($allFileIds)

$downloadedFiles = DownloadFiles $files
#Reload files where the exact version was not yet downloaded
foreach ($file in $files) {
    if (-not $downloadedFiles.ContainsKey($file)) {
        Write-Host "Reload file $($file.Name)" -ForegroundColor Green
        $reloadedFiles = DownloadFiles @($file)
        foreach($reloadedFile in $reloadedFiles.GetEnumerator()) {
            if (-not $downloadedFiles.ContainsKey($reloadedFile.Key)) {
                $downloadedFiles.Add($reloadedFile.Key, $reloadedFile.Value)
            }
        }
    }
}

$nativeFileIds = $metaLinks | Where-Object { $_.AddNative -eq $true } | Select-Object -ExpandProperty FileId
$pdfFileIds = $metaLinks | Where-Object { $_.AddPdf -eq $true } | Select-Object -ExpandProperty FileId
$dxfFileIds = $metaLinks | Where-Object { $_.AddDxf -eq $true } | Select-Object -ExpandProperty FileId

Write-Host "File to be included in ZIP: Native: $($nativeFileIds.Count)x, PDF: $($pdfFileIds.Count)x, DXF: $($dxfFileIds.Count)x"

$packageDirectory = [System.IO.Path]::Combine($workingDirectory, "Package")
if (-not [System.IO.Directory]::Exists($packageDirectory)) {
    [System.IO.Directory]::CreateDirectory($packageDirectory) | Out-Null
}

foreach($file in $files) {
    $fullFileName = $downloadedFiles[$file]    
    $isNative = $nativeFileIds -contains $file.Id
    $isPdf = $pdfFileIds -contains $file.Id
    $isDxf = $dxfFileIds -contains $file.Id
    PublishFile $file $fullFileName $isNative $isPdf $isDxf $packageDirectory
}
#endregion

Write-Host "Compressing files to ZIP..."
#region Compressing files to ZIP
$zipFileName = "$($custEnt.Name)-$($iteration).zip"
$zipFileFullName = [System.IO.Path]::Combine($workingDirectory, $zipFileName)
$ProgressPreference = 'SilentlyContinue' 
Compress-Archive -Force -Path "$packageDirectory\*.*" -DestinationPath $zipFileFullName
$ProgressPreference = 'Continue'

$transmittalFolder = $transmittalFolder.TrimEnd('/')
$zipFile = Add-VaultFile -From $zipFileFullName -To "$transmittalFolder/$zipFileName"
#endregion

Write-Host "Generating PDF report..."
#region Generating PDF report
$pdfFileName = "$($custEnt.Name)-$($iteration).pdf"
$pdfFileFullName = [System.IO.Path]::Combine($workingDirectory, $pdfFileName)

if (-not $user) {
    $jobs = $vault.JobService.GetJobsByDate([int]::MaxValue, [DateTime]::MinValue)
    $user = $vault.AdminService.GetUserByUserId(($jobs | Where-Object { $_.Id -eq $job.Id }).CreateUserId)
}

$parameters = @{
    Report_UserName = $user.Name
    Report_Name = $customObject.EntityName
    Report_Iteration = $iteration
    Report_Project = $project
    Report_Recipient = $recepient
    Report_Date = Get-Date
    Report_FilesCountAndSize = $allFiles.Count
}

CreateReport $rdlcFileFullName $rdlcDataSetName $allFiles $pdfFileFullName $parameters

$transmittalFolder = $transmittalFolder.TrimEnd('/')
$pdfFile = Add-VaultFile -From $pdfFileFullName -To "$transmittalFolder/$pdfFileName"
#endregion

Write-Host "Updating transmittal..."
#region Updating transmittal"
$linkIds = @()
$linkIdsToDelete = @()
$links = $vault.DocumentService.GetLinksByParentIds(@($custEnt.Id), @("FILE"))
if (-not $links) { return }
$links | ForEach-Object { $linkIds += $_.Id }

$metas = @($vault.DocumentService.GetMetaOnLinks($linkIds))
for($i=0; $i -lt $linkIds.Count; $i++) {
    $meta = $metas[$i]
    try {
        $internalLink = ConvertFrom-Json $meta
        $internalLink = [InternalLink]$internalLink
        if ($internalLink.Iteration -eq $iteration) {
            $linkIdsToDelete += $linkIds[$i]
        }
    } catch {}
}
if ($linkIdsToDelete) {
    $vault.DocumentService.DeleteLinks($linkIdsToDelete)
}

$pdfMeta = [InternalLink]::new()
$pdfMeta.FileId = $file.Id
$pdfMeta.Iteration = $iteration
$pdfMeta.LinkType = "PDF"
$json = ConvertTo-Json -InputObject $pdfMeta -Compress
$vault.DocumentService.AddLink($custEnt.Id, "FILE", $pdfFile.Id, $json) | Out-Null

$zipMeta = [InternalLink]::new()
$zipMeta.FileId = $file.Id
$zipMeta.Iteration = $iteration
$zipMeta.LinkType = "ZIP"
$json = ConvertTo-Json -InputObject $zipMeta -Compress
$vault.DocumentService.AddLink($custEnt.Id, "FILE", $zipFile.Id, $json) | Out-Null

$propInstParams = @()
$propInstParam = New-Object Autodesk.Connectivity.WebServices.PropInstParam
$propInstParam.PropDefId = $iterationPropDef.Id
$propInstParam.Val = $iteration
$propInstParams += $propInstParam

$propInstParamArray = New-Object Autodesk.Connectivity.WebServices.PropInstParamArray
$propInstParamArray.Items = $propInstParams
$vault.CustomEntityService.UpdateCustomEntityProperties(@($custEnt.Id), @($propInstParamArray))

$definitions = $vault.LifeCycleService.GetAllLifeCycleDefinitions()
$definition = $definitions  | Where-Object { $_.DispName -eq "Transmittal Process" }
$state = $definition.StateArray | Where-Object { $_.DispName -eq "Ready to send" }
if ($custEnt.LfCyc.LfCycStateId -ne $state.Id) {
    $vault.CustomEntityService.UpdateCustomEntityLifeCycleStates(@($custEnt.Id), @($state.Id), "Transmittal package compilation completed")
}
#endregion

Write-Host "Completed job '$($job.Name)'"