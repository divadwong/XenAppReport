# David Wong  4/3/19
# 7/09/19 - Added TaggedCount and GroupCount of servers. Removed ALEGroups from report.
# 4/24/19 - Added SendMail
# 4/08/19 - Added tagging option and logging.
#  Can be used with Task Scheduler, but need a service account with rights to DDC and AD. 
#  usage:  powershell.exe -executionpolicy bypass RestrictToTagReport.ps1 -ReTag True|False
# Create a csv report from RestrictToTag perspective
# Lists RestrictToTag, AppGroup, DeliveryGroup, Applications, ALEGroups, ServersTagged, ServersInGroup, ServersMatch
# If Servers tagged don't match with Servers in the ADgroup, you can run Tagging to match them up
Param(
	[Parameter(Mandatory=$False)]
	[string]$Retag="null")
#  $ReTag is "null" or "True" or "False"
# If passing parameter -Retag "true", then mismatches will Retagged without prompting.
# passing parameter -Retag (anything other than null or true, e.g. False), will not tag and not prompt to tag


function SendMail
{
	if ($Retag -eq "True"){$RetagStatus = "Retag was initiated"}else{$RetagStatus = "Machines were not retagged"}
	$PSEmailServer = 'mail.emailserver.com'
	$Subjectline = "CTX-SER tag and group mismatch found"
	$bodymessage = "The following have mismatched servers between tag and group
	`n$ShowNotMatched
	`n$RetagStatus
	`nReview file at $ReportLoc\$Filename"

	Send-MailMessage -To $EmailTo -From "CitrixXA7Alert <noreply@emailserver.com>" -Subject $Subjectline -body $bodymessage
}   
	
function TagServersinGroup
{
	Param(
	[Parameter(Mandatory=$True)]
	[string]$ADGroupname)
	
	$DateTime = Get-Date -Format g
	$WhoDidIt=$env:username

	if (!(Test-Path $ReportLoc`\TagLogs)){New-Item -ItemType Directory -Path $ReportLoc`\TagLogs -Force}
	# --------------------------------------------------------------
	# Read Servers in ADGroup and tag them in Citrix
	# Get Servers Tagged with ADGroupname
	$ServerTagged = Group-BrokerMachine -Tag $ADGroupname -Property HostedMachineName | select name
	# Get Servers in ADGroupname
	$ServerinGroup = Get-ADGroupmember $ADGroupname | Where objectclass -eq 'Computer' | sort name
	
	# Create Arraylists
	$ServerTaggedList = New-Object system.Collections.ArrayList
	$ServerinGroupList = New-Object system.Collections.ArrayList
    
	#  Add Servers to Arraylist
	foreach ($Server in $ServerTagged.name){$ServerTaggedList.add($Server) | Out-Null}
	
	#  Add Servers to Arraylist
	foreach ($Server in $ServerinGroup.name){$ServerinGroupList.add($Server) | Out-Null}
	
	$TaggedNotIngroup = $ServerTaggedList | Where-Object {$ServerinGroupList -notcontains $_}
	$IngroupNotTagged = $ServerinGroupList | Where-Object {$ServerTaggedList -notcontains $_} 
		
	# Untag Servers that are not in ADGroup
	if ($TaggedNotIngroup)
	{
        	write-host "Untagging $ADGroupname from...." -ForegroundColor Yellow
		foreach ($Server in $TaggedNotIngroup)
		{
		    Write-host "$Server" -ForegroundColor Green
		    "Remove $Server, $DateTime, $WhoDidIt" | Out-File $ReportLoc`\TagLogs\$ADGroupname`_Tag.txt -Append
		    Remove-BrokerTag -Name $ADGroupname -Machine domain\$Server
		}
	}

	# if Tag doesn't exist and Servers in ADGroup, create the Tag
	$AllTags = (Get-BrokerTag).Name
	if (($AllTags -notcontains $ADGroupname) -And $IngroupNotTagged)
	{
		Write-host "$ADGroupname Tag created"
		New-BrokerTag $ADGroupname | Out-Null
	}
	
	# Tag Servers that are in the AppGroup
	if ($IngroupNotTagged)
   	{	# Get list of servers in Machine Catalog
   		$Machines = Group-BrokerMachine -property HostedMachineName | select Name
        
		Write-host "Tagging $ADGroupname to...." -ForegroundColor Yellow
		foreach ($Server in $IngroupNotTagged)
		{	# Tag Server
            		if ($Machines.Name -contains $Server)
            		{
			    Write-host "$Server" -ForegroundColor Green
				"Add $Server, $DateTime, $WhoDidIt" | Out-File $ReportLoc`\TagLogs\$ADGroupname`_Tag.txt -Append
			    Add-BrokerTag -Name $ADGroupname -Machine domain\$Server
            		}
            		else
            		{	# if Server is not in a Machine Catalog, show error
                		Write-host "** Error ** $Server is not in a Machine Catalog" -ForegroundColor Red
            		}
		}
	}
}

######## START ########
# Adding Citrix Snapins
Add-PSSnapin Citrix*
##################################################
# Mail to if mismatches detected
$EmailTo = "adming@emailserver.com"

# Set DDC and Output variables 
$DDCServer = "YourDDCServerHere"
$DDCEnv = 'Prod'
$ReportLoc = "\\Server\Share\XA7Reports"
##################################################

# Setting File name. Exit if not running from DDC
$FileDateTime = get-date -format filedatetime
$FileDateTime = $FileDateTime[0..12] -join ''
$Filename =  "RestrictToTag_" + $DDCEnv + "_" + $FileDatetime + ".csv"
if (!(Test-Path $ReportLoc)){write-host "Creating $Reportloc";New-Item -ItemType Directory -Path $ReportLoc -Force}

# Get all apps on DDC
$Apps = Get-BrokerApplication -AdminAddress $DDCServer
if (!($Apps)){write-host "ERROR: Rights to XenApp Server and Citrix Powershell Snap-in are pre-requisites to run this script";Start-Sleep -s 10;Exit}
# Get all application groups on DDC
$AppGroupNames = Get-BrokerApplicationGroup
# Get all Tags on DDC starting with CTX-SER
$RestrictToTags = Get-BrokerTag | where {$_.Name -like "CTX-SER*"}
# Get all CTX-SER groups
$SERGroups = Get-ADObject -Filter 'ObjectClass -eq "group"' -SearchBase "OU=YourOU,OU=Servers,DC=domain,DC=com"
	
$Results = @()
$DesktopGroup = New-Object system.Collections.ArrayList
$Appgroup = New-Object system.Collections.ArrayList
$AppsinGroup = New-Object system.Collections.ArrayList
$AppTagServersNotMatched = New-Object system.Collections.ArrayList

Write-host "Processing .... "
foreach ($AppTag in $RestrictToTags.Name)
{
	$AppTag
	# Building Properties for each application group
	$Appgroup.Clear()
	$DesktopGroup.Clear()
	$AppsinGroup.Clear()	
	
	# Get the Groupname from uid
	foreach ($AppGroupName in $AppGroupNames)
    	{
		if ($AppGroupName.RestrictToTag -eq $AppTag)
		{
			$Appgroup.add($AppGroupName.Name) | Out-Null
			# Get the DesktopGroup from uid
            		$DTG = $AppGroupName.AssociatedDesktopGroupUids
            		foreach ($D in $DTG)
            		{
			    $DesktopGroup.add((Get-BrokerDesktopgroup -uid $D).Name) | Out-Null
            		}
			# Get Apps in AppGroup
            		foreach ($App in $Apps)
            		{
                		if ($app.AssociatedApplicationGroupUids -eq $Appgroupname.uid){$AppsinGroup.add($App.Name) | Out-Null}
            		}
		}
	}

	# Get Tagged Servers
	$MachinesTagged = $null
	$MachinesTagged = (Group-BrokerMachine -Tag $AppTag -Property HostedMachineName).name | sort
	if ($MachinesTagged){$MachinesTaggedCount = $MachinesTagged.Count}else{$MachinesTaggedCount = "NA"}
	
    	# Get membersof the CTX-SER group
	$GroupExist = $SERGroups | Where {$_.Name -eq $AppTag}
	if ($GroupExist)
	{
		# Get ALE groups associated with CTX-SER group
		$ALEGroups = $null
		$ALEGroups = (Get-ADPrincipalGroupMembership $AppTag).Name | sort
	
		# Get Servers in CTX-SER group
		$Servers = $null
		$Servers = (Get-ADGroupMember $AppTag).name | sort
		$ServersInGroupCount = $Servers.Count
		# Compare Tagged Servers and Servers in CTX-SER group to see if matched.
		$ServersMatch = "True"
		foreach ($machine in $MachinesTagged)
		    {if ($Servers -notcontains $machine){$ServersMatch = "False"}}
	
		foreach ($server in $servers)
		    {if ($MachinesTagged -notcontains $Server){$ServersMatch = "False"}}
	
		if ($ServersMatch -eq "False"){$AppTagServersNotMatched.add($AppTag) | Out-Null }
	}
	else
	{
		$ALEGroups = ""
		$Servers = "NoGroup"
		$ServersMatch = "NA"
		$ServersInGroupCount = "NA"
	}
	
	$Properties = @{
		RestrictToTag = $AppTag
        	AppGroup = $AppGroup -join ', '
		DeliveryGroup = $DesktopGroup -join ', '
        	Applications = $AppsinGroup -join ', '
		ALEGroups = $ALEGroups -join ', '
        	ServersTagged = $MachinesTagged -join ', '
		ServersInGroup = $Servers -join ', '
		GroupCount = $ServersInGroupCount
		TaggedCount = $MachinesTaggedCount
        	ServersMatch = $ServersMatch
	}
	
	# Store results for export
	$Results += New-Object psobject -Property $properties
}	

# Exporting results
Write-host "Exporting CSV file to $ReportLoc\$Filename"

# Show Server mismatch was found.
$ShowNotMatched = $AppTagServersNotMatched -join "`n"
if ($AppTagServersNotMatched){write-host "Servers Tagged and Servers in ADGroup mismatch detected" -foregroundcolor Red}

$results | select-Object RestrictToTag, AppGroup, DeliveryGroup, Applications, TaggedCount, ServersTagged, GroupCount, ServersInGroup, ServersMatch | Sort RestrictToTag |
 export-csv -Path $ReportLoc\$Filename -NoTypeInformation

$Answer1 = ''
$Answer2 = ''
if ($Retag -eq "null")
{
	Do{$Answer1 = Read-Host -Prompt "Display Report on screen? Type Y or N"}
	Until ($Answer1 -eq "Y" -or $Answer1 -eq "N")
	if ($Answer1 -eq "Y"){Import-CSV $ReportLoc\$Filename | ogv}
}	

# if NotMatches are found, Ask to run TagServersinGroup to Match them up.
if ($AppTagServersNotMatched)
{
	if ($Retag -eq "null")
	{
		Write-host "The Servers in the following AD Group does not match with Server Tagging." -ForegroundColor Yellow
		$ShowNotMatched
		Write-host "Match the tagging on servers to the AD Group?"
		Do{$Answer2 = Read-Host -Prompt "Type Y Process or N to exit"}
		Until ($Answer2 -eq "Y" -or $Answer2 -eq "N")
	}
	else {SendMail}
	
	if (($Answer2 -eq 'Y') -or ($ReTag -eq "True"))
	{
		foreach($NotMatched in $AppTagServersNotMatched)
		    {TagServersinGroup $NotMatched}
	}
}

if ($ReTag -eq "null"){Read-Host -Prompt "Hit Enter to Exit"}
	else
{Start-Sleep -s 3}
