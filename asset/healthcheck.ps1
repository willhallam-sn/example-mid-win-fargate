param([Parameter(Mandatory=$true)][int] $max_noactivity_minutes)

try {
    Write-Host "max_noactivity_minutes = $max_noactivity_minutes";
    $current_dir = Split-Path $MyInvocation.MyCommand.Definition -Parent;
    $agent_folder = "${current_dir}\agent\";
    if (-not (Test-Path -Path "${agent_folder}mid.anchor")) {
        Write-Host "${$agent_folder}mid.anchor doesn't exist";
        exit 1;
    }
    
    if (-not (Test-Path -Path "${agent_folder}.healthcheck")) {
        Write-Host "${agent_folder}.healthcheck doesn't exist";
        exit 1;
    }
    
    $lastModified = (Get-Item "${agent_folder}.healthcheck").LastWriteTime;
    if ((Get-Date) -gt $lastModified.AddMinutes($max_noactivity_minutes)) {
        Write-Host "No heartbeat in last $max_noactivity_minutes minutes";
        exit 1;
    }
    Write-Host "Last heartbeat at $lastModified";
    exit 0;
} catch {
    Write-Host "Error: $_";
    exit 1;
}

