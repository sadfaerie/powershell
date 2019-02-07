$resourceGroups = Get-AzureRmResourceGroup
if ($resourceGroups) 
{
foreach ($resourceGroup in $resourceGroups)
    {
    $resourceGroupName = "$($resourceGroup.ResourceGroupName)"
    $autoAccounts = Get-AzureRmAutomationAccount -ResourceGroupName $resourceGroupName      
    if ($autoAccounts)
        {
        $autoAccountName = "$($autoAccounts.AutomationAccountName)"
        $autoResourceGroup = "$($autoAccounts.ResourceGroupName)"
        $autoAccountCertificates = Get-AzureRmAutomationCertificate -ResourceGroupName $autoResourceGroup -AutomationAccountName $autoAccountName

        $certArray = @()
        foreach ($certificate in $autoAccountCertificates)
            {            
                [string]$Name = $certificate.Name
                [string]$AutomationAccountName = $certificate.AutomationAccountName
                [string]$ResourceGroupName = $certificate.ResourceGroupName
                [string]$Thumbprint = $certificate.Thumbprint
                [string]$CreationTime = $certificate.CreationTime.Date
                [string]$ExpiryTime = $certificate.ExpiryTime.Date

                $certSub = Get-AzureRmContext
                [string]$certSub = $certSub.Subscription.Name 

                $certObj = $null
                $certObj = New-Object System.Object
                $certObj | Add-Member -type NoteProperty -Name Name -Value $Name
                $certObj | Add-Member -type NoteProperty -Name Subscription -Value $certSub
                $certObj | Add-Member -type NoteProperty -Name ResourceGroupName -Value $ResourceGroupName
                $certObj | Add-Member -type NoteProperty -Name Thumbprint -Value $Thumbprint
                $certObj | Add-Member -type NoteProperty -Name CreationTime -Value $CreationTime
                $certObj | Add-Member -type NoteProperty -Name ExpiryTime -Value $ExpiryTime
                
                $certArray += $certObj            
            }

        $tableItems = @()
        foreach ($item in $certArray) 
            {
                $certName = $item | select -ExpandProperty Name
                $certSub = $item | select -ExpandProperty Subscription
                $certRG = $item | select -ExpandProperty ResourceGroupName
                $certThumbprint = $item | select -ExpandProperty Thumbprint
                $certCreate = $item | select -ExpandProperty CreationTime
                $certExpire = $item | select -ExpandProperty ExpiryTime

                [string]$certItem = "<tr><td>$certName</td><td>$certSub</td><td>$certRG</td><td>$certThumbprint</td><td>$certCreate</td><td>$certExpire</td></tr>"

                $tableItems += $certItem
            }

        [string]$tableHeader = "<table cellpadding='15' cellspacing='2'><tr><th bgcolor='#f2f2f2'>Subscription</th><th bgcolor='#f2f2f2'>Name</th><th bgcolor='#f2f2f2'>Resource Group</th><th bgcolor='#f2f2f2'>Thumbprint</th><th bgcolor='#f2f2f2'>Created on</th><th bgcolor='#f2f2f2'>Expires on</th></tr>"
        [string]$tableFooter = "<tr><td><br></td></tr></table>"
        [string]$table = $tableHeader + $tableItems + $tableFooter

        $table

        }
    }
}

