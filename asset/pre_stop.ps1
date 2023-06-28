function logInfo {
	param([String] $msg)
	"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffff') $msg" | Tee-Object -FilePath "$log_file" -Append
}

$current_dir = Split-Path $MyInvocation.MyCommand.Definition -Parent;
$mid_container_dir = "${current_dir}\mid_container";
$log_file = "${current_dir}\mid-container.log";

# Copy the config, wrapper config and other metadata files to the persistent volume
if (Test-Path -Path $mid_container_dir -PathType Container) {
	$log_file = "${mid_container_dir}\mid-container.log";
	logInfo "Backup the config and other metadata files to the persistent volume"
	Copy-Item "${current_dir}\agent\config.xml", `
		"${current_dir}\agent\conf\wrapper-override.conf", `
		"${current_dir}\agent\.initialized", `
		"${current_dir}\.container", `
		"${current_dir}\agent\properties\glide.properties" `
		-Destination "$mid_container_dir" `
		-Force `
		-ErrorAction Continue
} else {
	logInfo "The directory $mid_container_dir does not exist!"
}

# Create the drain marker file
$drain_marker_file = "${current_dir}\.drain_before_termination";
if (-not (Test-Path -Path $drain_marker_file -PathType Leaf)) {
	try {
		New-Item -ItemType File -Path $drain_marker_file -Force -ErrorAction Stop
		logInfo "The drain marker file $drain_marker_file has been created"
	}
	catch {
		logInfo "Failed to create the drain marker file $drain_marker_file. Error: $($_.Exception.Message)"
	}
}

# Tell the wrapper to stop the MID server. Before stop, the MID server will drain if it sees
# the drain marker file and if mid.drain.run_before_container_termination = true
logInfo "Stop the MID server"
Start-Process -NoNewWindow -FilePath "$env:comspec" -WorkingDirectory "$current_dir" -ArgumentList "/c","agent\stop.bat";

# Remove the drain marker file
if (Test-Path -Path $drain_marker_file -PathType Leaf) {
	try {
		Remove-Item -Path $drain_marker_file -Force -ErrorAction Stop
		logInfo "The drain marker file $drain_marker_file has been removed"
	}
	catch {
		logInfo "Failed to remove the drain marker file $drain_marker_file. Error: $($_.Exception.Message)"
	}
}
