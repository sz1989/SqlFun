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


I believe I can reproduce Andy's UAT issue last Thursday in the Development environment. After the user clicked the ‘To Next Month’ button, there was a delay of more than a few seconds for the Data Validation service call to complete (the delay was likely due to the recent transition to cloud-based data storage). However, the ‘To New Month’ button remained clickable. The user might have clicked on it more than once, causing the browser to generate multiple click events. This, in turn, triggered the service to move the Loss Period forward more than once.

On the other hand, the Loss Calculator is designed to run one instance per server. Once the Loss Calculator runs in the “move Loss to the new period” mode, any further incoming requests to the Loss Calculator service will result in an error message stating that the Loss Calculator is unavailable (error code: 503). This was why, even though the Loss period had been forwarded more than once, the Loss Calculator calculated only once. 

I suggest once the user clicks on the 'To Next Month' button, it should be immediately disabled. There will be no need to wait for the Loss Calculator to start running on the server and send a signal through SignalR to disable all buttons on the Loss Home page. This straightforward approach will effectively resolve the issue.

Thanks,
David Kao
