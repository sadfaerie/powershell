
$resourceGroup = " "
$storageAccountName = " "
$containerName = " "
$prefix = " "

$storageAccount = Get-AzureRmStorageAccount -ResourceGroupName $resourceGroup -Name $storageAccountName
$storageAccountKey = (Get-AzureRmStorageAccountKey -Name $storageAccountName -ResourceGroupName $resourceGroup).Value[0]

$storageContext = New-AzureStorageContext -StorageAccountName $storageAccountName -StorageAccountKey $storageAccountKey
$blob = Get-AzureStorageBlob -Context $storageContext -Container $containerName -Prefix $prefix

$arrList = New-Object System.Collections.ArrayList($null)

$blobContent = $blob.ICloudBlob.DownloadText()

$blobItems = (($blobContent -split ' ').Trim() | ForEach-Object { $_ }) -Join ' '

$arrList.AddRange(@($blobItems))

$arrList

# PSEUDOCODE
for ($item in $items) {
  $arrList += "$($item.property)"
}


# UPLOAD NEW BLOB CONTENT (OVERWRITES CURRENT BLOB CONTENT, TO APPEND - READ CURRENT CONTENT > ADD NEW CONTENT > OVERWRITE WITH UPDATED
$blob.ICloudBlob.UploadText($$arrList)
