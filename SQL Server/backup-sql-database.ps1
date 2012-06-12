Param([string]$s,[string]$db,[string]$lp,[string]$up,[string]$bp = "C:\SQL_BACKUPS",[byte]$d = 5,[string]$m = "MAILSERVER")
# $s  - The database server instance (e.g. MSSQLSERVER or MSSQLSERVER\INSTANCE)
# $db - The name of the database to be backed up
# $lp - The local path to the backup location on the database server (e.g. E:\Backup_Temp). NOTE: This folder must exist!
# $up - The UNC path to the backup location on the database server (e.g. \\MSSQLSERVER\E$\Backup_Temp)
# $bp - A base local or UNC path for the backup storage server location, defaults to C:\SQL_BACKUPS
# $d  - This number determines how many days backups should be kept, defaults to 5
# $m  - Server name or IP address of the mailserver used to send notifications, defaults to 214.200.251.8

#============================================================================================================
# CHANGES
#==========
# 07/06/2012	AG	Padded YYYY-MM-DD strings with leading zeros using C#/.NET formatter.
#					e.g. 2 digit month with leading zero:- "{0:d2}" -f $gd.Month

[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SMO") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoExtended") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.ConnectionInfo") | Out-Null
[System.Reflection.Assembly]::LoadWithPartialName("Microsoft.SqlServer.SmoEnum") | Out-Null
Import-Module PSCX

$emailFrom = "noreply@backups.com"
$emailTo   = "your.email@here.com"

$gd = Get-Date
$bakNew = $db + "_" + $gd.Year + "-" + "{0:d2}" -f $gd.Month + "-" + "{0:d2}" -f $gd.Day  + ".bak"
$gd = $gd.AddDays(-5)
$bakOld = $db + "_" + $gd.Year + "-" + "{0:d2}" -f $gd.Month + "-" + "{0:d2}" -f $gd.Day  + ".bak.zip"

$dbServer = New-Object ("Microsoft.SqlServer.Management.Smo.Server") ($s)
$dbBackup = New-Object ("Microsoft.SqlServer.Management.Smo.Backup")
$dbRestore = New-object ("Microsoft.SqlServer.Management.Smo.Restore")

$workPath = $lp + "\" + $bakNew

$dbBackup.Database = $db
$dbBackup.Devices.AddDevice($workPath, "File")
$dbBackup.Action="Database"
$dbBackup.Initialize = $TRUE
$dbBackup.SqlBackup($dbServer)
$error[0] | format-list -force

# Was the backup created, if not then email & quit.
$workPath = $up + "\" + $bakNew
if(!(Test-Path $workPath)) {
 $smtp = new-object Net.Mail.SmtpClient($m)
 $smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " failed", "Action required immediately for Full Backup.  File not found: " + $workPath + " [" + (Test-Path $workPath) + "]")
 Exit
}

# Create a Restore object and verify the backup, if invalid then email & quit.
$workPath = $lp + "\" + $bakNew
$dbRestore.Devices.AddDevice($workPath, "File")
if (!($dbRestore.SqlVerify($dbServer))) {
	Remove-Item $workPath
	$smtp = new-object Net.Mail.SmtpClient($m)
	$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " failed", "The backup was invalid and the BAK file was deleted. Action required immediately for Full Backup")
	Exit
}

# Move the valid local archive to the remote storage server, if the file was not moved then email & quit.
$uncPath = $up + "\" + $bakNew
$workPath = $bp + "\" + $s + "\" + $db
New-Item $workPath -type directory -force
Move-Item $uncPath $workPath
$workPath += "\" + $bakNew
if(!(Test-Path $workPath)) {
	$smtp = new-object Net.Mail.SmtpClient($m)
	$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " failed", "Backup was valid but ZIP archive could not be moved to the backup server. Action required immediately for Full Backup")
	Exit
}

# Archive the valid backup file, if the output file doesn't exist then email & quit.
$zipPath = $workPath  + ".zip"
Write-Zip $workPath -OutputPath $zipPath
if(!(Test-Path $zipPath)) {
	$smtp = new-object Net.Mail.SmtpClient($m)
	$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " failed", "Backup was valid but ZIP archive could not be created. Action required immediately for Full Backup")
	Exit
}

# Remove the uncompressed backup, if it still exists then email & quit.
Remove-Item $workPath
if((Test-Path $workPath)) {
	$smtp = new-object Net.Mail.SmtpClient($m)
	$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " warning", "Backup was valid but the uncompressed backup was not deleted from the local server. Action required.")
	Exit
}

# Remove x days old backup, if it still exists then email & quit.
$workPath = $bp + "\" + $s + "\" + $db + "\" + $bakOld
if((Test-Path $workPath)) { Remove-Item $workPath }
if((Test-Path $workPath)) {
	$smtp = new-object Net.Mail.SmtpClient($m)
	$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " warning", "Backup was valid but the old ZIP archive was not deleted from the remote server. Action required.")
	Exit
}

# If we've got this far then everything should be ok.
$smtp = new-object Net.Mail.SmtpClient($m)
$smtp.Send($emailFrom, $emailTo, "Backup for " + $db + " completed", "Backup was valid and was sucessfully archived on the remote server.")