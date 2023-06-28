function logInfo {
	param([String] $msg)
	"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffff') $msg" | Tee-Object -FilePath "$log_file" -Append
}

$current_dir = Split-Path $MyInvocation.MyCommand.Definition -Parent;
$mid_container_dir = "${current_dir}\mid_container";
$log_file = "${current_dir}\mid-container.log";
$drain_marker_file = "${current_dir}\.drain_before_termination";

if (Test-Path -Path $mid_container_dir -PathType Container) {
	$log_file = "${mid_container_dir}\mid-container.log";
}

if (Test-Path -Path $drain_marker_file -PathType Leaf) {
	try {
		Remove-Item -Path $drain_marker_file -Force -ErrorAction Stop
		logInfo "The drain marker file $drain_marker_file has been removed"
	}
	catch {
		logInfo "Failed to remove the drain marker file $drain_marker_file. Error: $($_.Exception.Message)"
	}
}
