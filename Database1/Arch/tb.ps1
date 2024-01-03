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


I can confirm that I can reproduce the user’s UAT issue last Thursday in the Development environment. The issue occurred after the user clicked on the 'To Next Month' button, and experienced a delay of more than a few seconds for the Data Validation service call to the server to complete. The delay may have been caused by the recent transition to cloud-based data storage. Despite the delay, the 'To New Month' button remained clickable, which may have caused the user to click on it multiple times, generating multiple click events. This, in turn, caused the service to move the Loss Period forward more than once.

The Loss Calculator is designed to run one instance per server. Once the Loss Calculator runs in the “move Loss to the new period” mode, any further incoming requests to the Loss Calculator service will result in an error message stating that the Loss Calculator is unavailable (error code: 503). So, despite forwarding the Loss Period more than once, the Loss Calculator only calculated it once. 

To avoid such an issue in the future, I suggest updating the code to disable the ‘To Next Month’ button immediately after the user clicks it. So, the Loss Home page does not have to wait for the Loss Calculator to start running on the server and send a signal to disable all buttons on the Loss Home page. This solution will address the UAT issue that occurred last Thursday. 

Thanks,
David Kao


By disabling the button after the user clicks, we can easily solve this problem. It's a simple solution that will prevent any further issues down the line.
