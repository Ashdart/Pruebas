Param(
    $currentDir = "$pwd",
    $projectDir = "${PSScriptRoot}",
    $configuration = "Release",
    $webappConfiguration = "PROD",
    $targetDir = "G:/Current",
    $targetName = "Relay-PROD-" + (Get-Date -format "yyyy-MM-dd-HHmm")
)

if (!$projectDir) {
    # Workaround for old PowerShell
    $projectDir = Split-Path $MyInvocation.MyCommand.Path -Parent
}

function CheckLastExitCode {
    param ([int[]]$SuccessCodes = @(0))

    if ($SuccessCodes -notcontains $LastExitCode) {
        throw "EXE RETURNED EXIT CODE $LastExitCode"
    }
}

trap {
    "ERROR"
    "====="
    "$_ $(Get-PSCallStack | Out-String)"
    exit 1
}

$targetWEB02 = "${targetName}-WEB02"
$targetSERVER13 = "${targetName}-SERVER13"
$targetWEB01 = "${targetName}-WEB01"

try
{
    Add-Type -assembly "System.IO.Compression.FileSystem"

    cd $projectDir

    New-Item -ItemType Directory -Force -Path "$targetDir/$targetWEB02"

    # By the moment, this line will only work in Andres' Environment
    ./build-webapp.cmd $webappConfiguration
    CheckLastExitCode
    Copy-Item "$projectDir/src/build" "$targetDir/$targetWEB02/sites/webapp" -recurse

    ./publish-relay.ps1 `
        -projectDir "$projectDir" `
        -configuration "$configuration" `
        -omitTests $TRUE `
        -compressOutput $FALSE `
        -folderOutput $TRUE `
        -targetDir "$targetDir/$targetWEB02" `
        -targetActionWorker "services/Relay.BackgroundProcesses.ActionWorker" `
        -targetBounceWorker "services/Relay.BackgroundProcesses.BounceWorker" `
        -targetOutboundWorker "services/Relay.BackgroundProcesses.OutBoundWorker" `
        -targetPreProcessWorker "services/Relay.BackgroundProcesses.PreProcessWorker" `
        -targetRecurringTasksWorker "services/Relay.BackgroundProcesses.RecurringTasksWorker" `
        -targetReportsWorker "services/Relay.BackgroundProcesses.Reports" `
        -targetResponseWorker "services/Relay.BackgroundProcesses.ResponseWorker" `
        -targetTracingWorker "services/Relay.BackgroundProcesses.TracingWorker" `
        -targetInboundWorker "services/Relay.SmtpGateway.InBound" `
        -targetActionsApi "sites/Actions" `
        -targetApplicationApi "sites/API"
    CheckLastExitCode

    New-Item -ItemType Directory -Force -Path "$targetDir/$targetSERVER13/services"
    Move-Item -Path "$targetDir/$targetWEB02/services/Relay.BackgroundProcesses.OutBoundWorker" -Destination "$targetDir/$targetSERVER13/services" -Force
    Move-Item -Path "$targetDir/$targetWEB02/services/Relay.BackgroundProcesses.BounceWorker" -Destination "$targetDir/$targetSERVER13/services" -Force

    [io.compression.zipfile]::CreateFromDirectory("$targetDir/$targetWEB02", "$targetDir/$targetWEB02.zip")
    [io.compression.zipfile]::CreateFromDirectory("$targetDir/$targetSERVER13", "$targetDir/$targetSERVER13.zip")

    New-Item -ItemType Directory -Force -Path "$targetDir/$targetWEB01/services"
    Move-Item -Path "$targetDir/$targetWEB02/sites" -Destination "$targetDir/$targetWEB01" -Force
    Move-Item -Path "$targetDir/$targetWEB02/services/Relay.SmtpGateway.InBound" -Destination "$targetDir/$targetWEB01/services" -Force
    [io.compression.zipfile]::CreateFromDirectory("$targetDir/$targetWEB01", "$targetDir/$targetWEB01.zip")

    Remove-Item "$targetDir/$targetWEB02" -Recurse -Force
    Remove-Item "$targetDir/$targetSERVER13" -Recurse -Force
    Remove-Item "$targetDir/$targetWEB01" -Recurse -Force
}
finally
{
    cd $currentDir
}