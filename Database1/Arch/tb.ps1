$ServerName='SqlDev3'# the server it is on
$Database='CoreLog' # the name of the database you want to script as objects
$DirectoryToSaveTo='E:\Tmp' # the directory where you want to store them
# Load SMO assembly, and if we're running SQL 2008 DLLs load the SMOExtended and SQLWMIManagement libraries
$v = [System.Reflection.Assembly]::LoadWithPartialName( 'Microsoft.SqlServer.SMO')
if ((($v.FullName.Split(','))[1].Split('='))[1].Split('.')[0] -ne '9') {
    Write-Host 'a'
    [System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SMOExtended') | out-null
}
[System.Reflection.Assembly]::LoadWithPartialName('Microsoft.SqlServer.SmoEnum') | out-null
set-psdebug -strict # catch a few extra bugs
$ErrorActionPreference = "stop"
$My='Microsoft.SqlServer.Management.Smo'
$srv = new-object ("$My.Server") $ServerName # attach to the server
if ($srv.ServerType-eq $null) # if it managed to find a server
   {
   Write-Error "Sorry, but I couldn't find Server '$ServerName'"
   return
} 
$scripter = new-object ("$My.Scripter") $srv # create the scripter
$scripter.Options.ToFileOnly = $true 


# Happy New Year, all, 

# I am writing to provide an update regarding Andy’s issue in the UAT last Thursday. I tried to replicate the issue in the DEV but was unable to reproduce it. 

# After closely re-analyzing the code that is responsible for the Loss Monthly closing process this morning, and I will make another attempt to create a situation in DEV that might reproduce the issue. I will keep everyone informed about my progress as I continue to work on this.

# Thank you for your attention to this matter.

# Best regards.
