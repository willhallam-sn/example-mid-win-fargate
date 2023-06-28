param([String] $mid_installation_file)

$current_dir = Split-Path $MyInvocation.MyCommand.Definition -Parent;

Write-Host "Extracting $mid_installation_file to $current_dir";
Expand-Archive -Path $mid_installation_file -DestinationPath $current_dir;

Write-Host "Removing temp file $mid_installation_file"
try {
    Remove-Item -Path "$mid_installation_file" -Force
} catch {
    Write-Host "Failed to remove ${mid_installation_file}: $PSItem"    
}

Write-Host "Apply required settings to support running as process"
$wrapper_params="`nwrapper.single_invocation=TRUE`nwrapper.anchorfile=./mid.anchor`nwrapper.commandfile=./mid.command`nwrapper.restart.reload_configuration=TRUE`n";
Add-Content -Path "agent\conf\wrapper-override.conf" -Value $wrapper_params;
