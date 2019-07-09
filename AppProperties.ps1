# David Wong
# Updated 7/09/19
# Create a report of the Applications and Properties on a XenApp Server.
	
# Adding Citrix Snapins
Add-PSSnapin Citrix*

############ Set DDC and Output variables ############
$DDCServer = "YourDDCServerHere"
$DDCEnv = 'Prod'
$ReportLoc = "\\Server\Share\XA7Reports"
######################################################

# Setting File name. 
$FileDateTime = get-date -format filedatetime
$FileDateTime = $FileDateTime[0..12] -join ''
$Filename = "AppProperties_" + $DDCEnv + "_" + $FileDateTime + ".csv"
if (!(Test-Path $ReportLoc)){New-Item -ItemType Directory -Path $ReportLoc -Force}

$AllApps = Get-BrokerApplication -AdminAddress $DDCServer | Sort name

$Results = @()
$AppGroup = New-Object system.Collections.ArrayList
$RestrictToTag = New-Object system.Collections.ArrayList
$DesktopGroup = New-Object system.Collections.ArrayList

Write-host "Processing .... "
foreach ($App in $AllApps)
{
	$App.PublishedName
    	$AppGroup.Clear()
	$RestrictToTag.Clear()
	$DesktopGroup.Clear()

    	# Get the AppGroupname from uid
	$AG = $App.AssociatedApplicationGroupUids
	if ($AG)
	{
           foreach ($A in $AG)
           {
        	$GetAG = Get-BrokerApplicationGroup -uid $A
		$AppGroup.add($GetAG.Name) | Out-Null
		$RestrictToTag.add($GetAG.RestrictToTag) | Out-Null
           }
    	}

    # Get the DesktopGroupname from uid
    $DG = $App.AllAssociatedDesktopGroupUIDs
    if ($DG)
    {
        foreach ($D in $DG)
        {
		$DesktopGroup.add((Get-BrokerDesktopgroup -uid $D).Name) | Out-Null
        }
    }
	
	# if UserFilterEnabled -eq $false, don't show AssociatedUserFullNames
    if ($app.UserFilterEnabled -eq $False){$AssociatedUserFullNames = ''}else{$AssociatedUserFullNames = $app.AssociatedUserFullNames}

		# Building Properties for each application
		$Properties = @{
			Name = $app.Name
			ApplicationName = $app.ApplicationName
            		PublishedName = $app.PublishedName
			CommandLineExecutable = $app.CommandLineExecutable
			CommandLineArguments = $app.CommandLineArguments
			WorkingDirectory = $app.WorkingDirectory
			Description = $app.Description
			Enabled = $app.Enabled
			MaxPerUser = $app.MaxPerUserInstances
			MaxTotal = $app.MaxTotalInstances
			UserFilterEnabled = $app.UserFilterEnabled
			#Visible = $app.Visible
			Visibility = $AssociatedUserFullNames -join ', '
           		ApplicationGroup = $AppGroup -join ', '
			RestrictToTag = $RestrictToTag -join ', '
			DeliveryGroup = $DesktopGroup -join ', '
        }
	#Store results for export	
    	$Results += New-Object psobject -Property $properties
}

# Exporting results
Write-host "Exporting CSV file to $ReportLoc\$Filename"

$results | select-Object PublishedName, ApplicationGroup, RestrictToTag, DeliveryGroup, Description, Enabled, commandlineexecutable, commandlinearguments, WorkingDirectory, MaxPerUser, Visibility |
 export-csv -Path $ReportLoc\$Filename -NoTypeInformation

Start-Sleep -s 10
