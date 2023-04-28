# This project is called ShellRock (powerShell bedRock) or ShellRock Server
# ShellRock will become an all-in-one Bedrock server 
# management tool written in pure powershell for maximum compatibility
# Completed Features:
#   Basic Automatic World Backups
#   Message of the Day
#   Safety Automatic Shutdown
# Planned Features include:
#   Ability to program server commands conditionally
#   Automatic online backups
#   Breakout settings into shellrock.cfg
#   Ability to run commands on the fly, if not in terminal then via updating a file
#   Potentially create a custom gui or display in the console that can show updating stats 

[Console]::TreatControlCAsInput = $true #allows interception of ctrl+c

$global:server_path = ""
$global:server_proc = "bedrock_server.exe"
$global:backup = $false
$global:output = "" #allow any function to access most recent output
$global:players = 0 #count of active players
$global:total_players = 0 #total count of all players who have ever joined the server
$global:player_names = @{ "Test Player" = @("Offline", "MOTDTrue"); } #hash table containing player names keys with status values
$global:server = $false #making the server variable global to allow easier access
$global:motd = ""
$global:name_pattern = ": .+(?=,)" #pattern for matching player names, due to $ps limitations includes ": " at start

function Poll-CtrlC {
    #Intercepts ctrl+c interrupt and properly exits the server
    if( [Console]::KeyAvailable ) {
        $readkey = [Console]::ReadKey($true)
        if ($readkey.Modifiers -eq "Control" -and $readkey.Key -eq "C") {                
            Write-Output "Stopping server..."
            $global:server.StandardInput.WriteLine("stop")
            1..5 | foreach{Start-Sleep -s 1}
            Write-Output "Server has stopped, you may now close this window."
            while( $true ){ Start-Sleep -s 1 }
        }
    }
}

function Manage-MOTD {
    #Handles the sending of the MOTD message based on global variables set by the ServerOutputHandler
    $iter_players = @($global:player_names.GetEnumerator()).GetEnumerator()
    foreach( $player in $iter_players ) {
        if($player.Value[1] -eq "MOTDFalse") {
            1..10 | foreach{ Start-Sleep -s 1 }
            Write-Output "Sending MOTD to $($player.Name)"
            $global:server.StandardInput.WriteLine("tellraw `"$($player.Name)`" {`"rawtext`":[{`"text`":`"$global:motd`"}]} ")
            $global:player_names[$player.Name] = @($player.Value[0], "MOTDTrue")
        }
    }
}

function Backup-World {
    #Handles file operations for save backups
    $stopwatch = New-Object System.Diagnostics.Stopwatch
    $stopwatch.Start()
    $world_path =  "$global:server_path\worlds"
    $backup_path = "$global:server_path\world_backups"
    $world_folders = Get-ChildItem $world_path | Where-Object { $_.PSIsContainer }
    ForEach ($world in $world_folders) {
        $timestamp = Get-Date -Format FileDateTimeUniversal
        $full_path = "$world_path\$world"
        $copy_path = "$backup_path\$world"
        Copy-Item -Path $full_path -Destination $copy_path -Recurse
        $zipname = "$world [$timestamp].zip"
        $zippath = "$backup_path\$zipname"
        #sz a $zippath -mx9 -tzip -r $copy_path -sdel | out-null
        Compress-Archive -Path $copy_path -DestinationPath $zippath
        Remove-Item -LiteralPath $copy_path -Force -Recurse
        $stopwatch.Stop()
        Write-Output "Backed up: $world, in $($stopWatch.ElapsedMilliseconds)ms"
    }
}

function Manage-Backups {
    #Manages autoamtic backup scheduling
    if(-not $global:backup -and $global:players -le 0) { return }
    #Write-Output "Starting Backup Manager"
    $minute = Get-Date -format mm #string
    if ($minute -eq "00" -and $global:players -ge 1) { $global:backup = $true }
    if ($global:backup -eq $true) {
        Write-Output "Beginning backup..."
        $global:backup = $false #track backup state to avoid duplicate backups
        $global:server.StandardInput.WriteLine("say BACKUP IMMINENT, STOP BUILDING!");
        1..5 | foreach{Start-Sleep -s 1}
        $global:server.StandardInput.WriteLine("save hold");
        1..5 | foreach{Start-Sleep -s 1}
        Backup-World
        $global:server.StandardInput.WriteLine("save resume");
        $global:server.StandardInput.WriteLine("say BACKUP COMPLETE! THANK YOU! :)");
    }
}

$ServerOutputHandler = {
    #Handler for the Server output event, assigned by Start-Server
    param([object]$sender, [System.Diagnostics.DataReceivedEventArgs]$e)
    $output = $e.Data #output starts internal for easy referencing later
    $global:output = $output
    Write-Host $output
    $player_state = $false #tracks if a player joined or left for status, begins false to identify if it's a join/leave event
    $motd_state = "MOTDFalse" #tracks motd state
    if( $output.contains("Player connected") ) { $global:players += 1; $player_state = "Online"; }
    if( $output.contains("Player disconnected") ) { $global:players -= 1; $global:backup = $true; $player_state = "Offline" }
    #Beginning player name tracking
    if( $player_state ) {
        $name_match = $output -match $global:name_pattern
        if( $name_match ) {
            $player_name = $matches[0] -replace ": ", ""
            if( $global:player_names.ContainsKey($player_name) ) { #if player is already present, update record
                $global:player_names[$player_name] = @( $player_state, $motd_state )
            } else {
                $global:player_names += @{ $player_name = @( $player_state, $motd_state ) } #otherwise, add a new record by combining hash tables
            }
        } else { Write-Host "Failed to match player name despite identifying connection event in this output:\n$output" }
    }
}

function Start-Server {
    # Starts the server and begins the async read, then returns the server process
    # Sending commands: $server.StandardInput.WriteLine("stop");
    $server_object = New-Object System.Diagnostics.ProcessStartInfo
    $server_object.FileName = "$global:server_path\$global:server_proc"
    $server_object.UseShellExecute = $false # start the process from it's own file
    $server_object.RedirectStandardInput = $true # enable the process to read from standard input
    $server_object.RedirectStandardOutput = $true # enable redirection of output to the script
    $server = [System.Diagnostics.Process]::Start( $server_object )
    $server_objevent = Register-ObjectEvent $server -EventName OutputDataReceived -Action $ServerOutputHandler
    $server.BeginOutputReadLine()
    return $server
}

$global:server = Start-Server
$tick = 0
while( -not $global:server.HasExited ) {
    $tick += 1
    if($tick % 50 -eq 0) { Manage-MOTD } # 5 seconds
    if($tick % 300 -eq 0) { Manage-Backups } # 30 seconds
    #if($tick % 600 -eq 0) { Write-Output $global:player_names }
    1..100 | foreach{Start-Sleep -m 1} # 10 ticks per second
    Poll-CtrlC # catch ctrl-c for safe exits
}
