param([Parameter(Mandatory=$true)][String] $cmd, [switch] $force=$False)
function logInfo {
	param([String] $msg)
	"$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.ffff') $msg" | Tee-Object -FilePath "$log_file" -Append
}

$current_dir = Split-Path $MyInvocation.MyCommand.Definition -Parent;
$mid_container_dir = "${current_dir}\mid_container";
$log_file = "${current_dir}\mid-container.log";
$config_file = "${current_dir}\agent\config.xml";
$wrapper_file = "${current_dir}\agent\conf\wrapper-override.conf";
$agent_log_file = "${current_dir}\agent\logs\agent0.log.0";
$manage_certificates_bat_file = "${current_dir}\agent\bin\scripts\manage-certificates.bat";
$init_file = "${current_dir}\agent\.initialized";
$container_meta_file = "${current_dir}\.container";

$net=new-object -ComObject WScript.Network
$net.MapNetworkDrive("$Env:SHARE_DRIVE", "$Env:SHARE_PATH", $false, "$Env:SHARE_USER", "$Env:SHARE_PASSWD")
New-Item -Path $mid_container_dir -ItemType SymbolicLink -Value $Env:SHARE_DRIVE\
cd $mid_container_dir
whoami > who.txt
dir > dir.txt
if (Test-Path -Path $mid_container_dir) {
    logInfo "Found $mid_container_dir"
	$log_file = "${mid_container_dir}\mid-container.log";
} 
else {
    logInfo "No $mid_container_dir"
}

function isInitialized {
    return Test-Path -Path $init_file;
}

function preserveEnv {
    # promoting process-level environment variables to machine-level
    foreach($key in [System.Environment]::GetEnvironmentVariables('Process').Keys) {
        if ($null -eq [System.Environment]::GetEnvironmentVariable($key, 'Machine')) {
            $value = [System.Environment]::GetEnvironmentVariable($key, 'Process');
            [System.Environment]::SetEnvironmentVariable($key, $value, 'Machine')
        }
    }
}

function updateConfigXMLFromEnvVars {
    param([String] $xmlFile)

    loginfo "Updating Config.xml from environment variables";

    $configParamRegex = "MID_CONFIG_(?<name>.+)";
    $props = getEnvVars $configParamRegex;
    [xml] $xmlDoc = Get-Content $xmlFile -Raw
    $nodeList = $xmlDoc.selectNodes("//parameters/parameter");

    # For compatibility with Rome we check if any of these variables have been manually set.
    # Values from MID profiles or secrets file will override these.
    $defaultParams = @{};
    $defaultParams.Add('url', 'MID_INSTANCE_URL');
    $defaultParams.Add('mid.instance.username', 'MID_INSTANCE_USERNAME');
    $defaultParams.Add('mid.instance.password', 'MID_INSTANCE_PASSWORD');
    $defaultParams.Add('name', 'MID_SERVER_NAME');
    $defaultParams.Add('mid.proxy.host', 'MID_PROXY_HOST');
    $defaultParams.Add('mid.proxy.port', 'MID_PROXY_PORT');
    $defaultParams.Add('mid.proxy.username', 'MID_PROXY_USERNAME');
    $defaultParams.Add('mid.proxy.password', 'MID_PROXY_PASSWORD');
    $defaultParams.Add('mid.ssl.bootstrap.default.check_cert_revocation', 'MID_SSL_BOOTSTRAP_CERT_REVOCATION_CHECK');
    $defaultParams.Add('mid.ssl.use.instance.security.policy', 'MID_SSL_USE_INSTANCE_SECURITY_POLICY');

    $envVars = [System.Environment]::GetEnvironmentVariables();
    foreach ($key in $defaultParams.keys) {

        # If key is present in $props, then it was defined in the profile and that value has precedence.
        # If default key/value is not present in env vars, then don't add to $props.
        if ($props.containsKey($key) -or -not $envVars.ContainsKey($defaultParams[$key])) {
            continue;
        }

        [String] $val = $envVars[$defaultParams[$key]];
        if ($val -eq $null) {
            continue;
        }

        $props.Add($key, $val);
    }

    if (-not $props.ContainsKey('mid.secure_encrypter')) {
        $props.add("mid.secure_encrypter", "com.service_now.mid.services.config.WindowsDPAPIEncrypter");
    }

    # Process secrets file last, these have precedence and overwrite any existing values
    $MID_SECRETS_FILE = [System.Environment]::GetEnvironmentVariable('MID_SECRETS_FILE');
    if (-not [String]::IsNullOrWhiteSpace($MID_SECRETS_FILE) -and (Test-Path -Path "$MID_SECRETS_FILE")) {
        logInfo "Found the secrets file `"$MID_SECRETS_FILE`"";
        $secrets = Get-Content "$MID_SECRETS_FILE" -Raw | ConvertFrom-StringData;
        foreach ($key in $secrets.keys) {
            $val = [String]$secrets[$key];

            #disallow null values (empty value is allowed)
            if ($val -eq $null) {
                continue;
            }

            if ($props.ContainsKey($key)) {
                $props[$key] = $val;
            } else {
                $props.Add($key,$val);
            }
        }
    }

    # update existing nodes with new values from env vars
    foreach ($node in $nodeList) {
        $name = $node.name;
        if ($props.ContainsKey($name)) {
            [String] $val = $props[$name];
            $props.remove($name);

            if ($val -eq $null) {
                continue;
            }

            # process mid server name template
            if ("name" -eq $name) {
                if ($val.EndsWith("_AUTO_GENERATED_UUID_")) {
                    $_replacement = (New-Guid).Guid;
                    $val = $val.Replace("_AUTO_GENERATED_UUID_", $_replacement);
                    logInfo "GUID $_replacement is generated and the new value $val is assigned to the $name parameter"
                } elseif ($val.EndsWith("_NAMESPACE_HOSTNAME_")) {
                    $MID_CONTAINER_DEPLOYMENT_NAMESPACE = [System.Environment]::GetEnvironmentVariable('MID_CONTAINER_DEPLOYMENT_NAMESPACE');
                    if ([String]::IsNullOrWhiteSpace($MID_CONTAINER_DEPLOYMENT_NAMESPACE) -or ("default" -eq $MID_CONTAINER_DEPLOYMENT_NAMESPACE)) {
                        $_replacement="$(hostname)";
                    } else {
                        $_replacement="${MID_CONTAINER_DEPLOYMENT_NAMESPACE}_$(hostname)";
                    }
                    $val = $val.Replace("_NAMESPACE_HOSTNAME_", $_replacement);
                    logInfo "_NAMESPACE_HOSTNAME_ $_replacement is generated and the new value $val is assigned to the $name parameter"
                } elseif ($val.EndsWith("_HOSTNAME_NAMESPACE_")) {
                    $MID_CONTAINER_DEPLOYMENT_NAMESPACE = [System.Environment]::GetEnvironmentVariable('MID_CONTAINER_DEPLOYMENT_NAMESPACE');
                    if ([String]::IsNullOrWhiteSpace($MID_CONTAINER_DEPLOYMENT_NAMESPACE) -or ("default" -eq $MID_CONTAINER_DEPLOYMENT_NAMESPACE)) {
                        $_replacement="$(hostname)";
                    } else {
                        $_replacement="$(hostname)_${MID_CONTAINER_DEPLOYMENT_NAMESPACE}";
                    }
                    $val = $val.Replace("_HOSTNAME_NAMESPACE_", $_replacement);
                    logInfo "_HOSTNAME_NAMESPACE_ $_replacement is generated and the new value $val is assigned to the $name parameter"
                }
            }

            $node.value = $val;
        }
    }

    # add any new values
    foreach ($prop in $props.keys) {
        $val = $props[$prop.ToString()];
        if ($val -eq $null) {
            continue;
        }

        $newNode = $xmlDoc.CreateElement("parameter");
        $newNode.SetAttribute("name", $prop.ToString());
        $newNode.SetAttribute("value", $val);
        $null = $xmlDoc.parameters.AppendChild($newNode);
    }

    loginfo "Writing to file: $xmlFile";
    $xmlDoc.Save($xmlFile);
}

function updateWrapperConfFromEnvVars {
    param([String] $wrapperFilePath);

    loginfo "Updating wrapper-override.conf from environment variables";

    $envVarWrapperConfRegex = "MID_WRAPPER_(?<name>.+)";
    $wrapperPropRegex = "^#?\s*(?<name>wrapper\..*?)=(?<value>.*)$"
    $props = getEnvVars $envVarWrapperConfRegex;
    $wrapperFile = Get-Content $wrapperFilePath;
    updatePropertyFile $wrapperFile $props $wrapperFilePath $wrapperPropRegex;
}

function updateContainerMetaFileFromEnvVars {
	param([String] $containerFilePath, [HashTable] $props);

    loginfo "Updating .container from environment variables";

    $propRegex = "^#?\s*(?<name>.*?)=(?<value>.*)$"
    $containerFile = Get-Content $containerFilePath;
    updatePropertyFile $containerFile $props $containerFilePath $propRegex;
}

function updatePropertyFile {
    param([Object[]] $oldFile, [HashTable] $props, [String] $filePath, [String] $propRegex)
    $updatedFile = "";
    # Update existing file
    $oldFile | ForEach-Object {
        if ($_ -match $propRegex) {
            $name = $Matches.name;
            $value = $Matches.value;
            $newline = "";
            if ($props.ContainsKey($name)) {
                $value = $props[$name];
                $props.Remove($name);
            } else {
                if ($_.ToString().StartsWith("#")) {
                    $newline = "#";
                }
            }
            $newline += "$name=$value`n";
            $updatedFile += $newline;

        } else {
            if (-not ($_ -match "`n$")) {
                $_ += "`n";
            }
            $updatedFile += "$_";
        }
    };

    # Add new env vars to file
    foreach ($prop in $props.keys) {
        $name = $prop;
        $value = $props[$prop];
        $updatedFile += "$name=$value`n"
    };

    loginfo "Writing to file: $filePath";
    Set-Content -Path $filePath -Value $updatedFile;
}

function getEnvVars {
    param([String] $regex)

    $envProps = [System.Environment]::GetEnvironmentVariables();
    $props = @{};
    foreach ($prop in $envProps.keys) {
        if (-not ($prop -match $regex) -or [String]::IsNullOrWhiteSpace($Matches.name)) {
            continue;
        }

        $propName = $Matches.name
        $propValue = $envProps[$prop];

        if ($propValue -eq $null) {
            continue;
        }

        # Bash environment variable names can only contain alpha-numeric characeters and the underscore
        # and as such, the period (.) is an offending character and has been remapped to
        # two consecutive underscores (__).
        # example: mid.log.level is stored as mid__log__level
        # Even though Windows doesn't have this limitation, we use the same pattern for unified handling.
        # The following line restores the original name.
        $propName = $propName -replace '__', '.'
        $props.Add($propName, $propValue);
    }

    return $props;
}

function validateMandatoryParameters() {
    param($useMutualAuth)

    logInfo "Validating mandatory parameters in config.xml"

    [xml] $xmlDoc = Get-Content $config_file -Raw

    # username/pw is only mandatory if not using mutual auth
    $mandatoryParams = @{
        "url" = @{
            templateValue = "https://YOUR_INSTANCE.service-now.com/"
            shouldExist = $true
        }
        "name" = @{
            templateValue = "YOUR_MIDSERVER_NAME_GOES_HERE"
            shouldExist = $true
        }
        "mid.instance.username" = @{
            templateValue = "YOUR_INSTANCE_USER_NAME_HERE"
            shouldExist = !($useMutualAuth)
        }
        "mid.instance.password" = @{
            templateValue = "YOUR_INSTANCE_PASSWORD_HERE"
            shouldExist = !($useMutualAuth)
        }
    }

    $valid = $true;

    $mandatoryParams.Keys | ForEach-Object {
        if ($valid) {
            if (-not (validateMandatoryParameter $xmlDoc $_ $($mandatoryParams[$_].shouldExist) $($mandatoryParams[$_].templateValue) -eq $true)) {
                logInfo "Required parameter `"$_`" failed to update.";
                $valid = $false;
            }
        }
    }
    return $valid;
}

function validateMandatoryParameter() {
    param($xmlDoc, $paramName, $shouldExist, $templateValue)

    logInfo "Validating parameter: $paramName"
    $node = $xmlDoc.selectSingleNode("//parameters/parameter[@name='$paramName']");
    if (!$node) {
        # Node should not be present if mutual auth is enabled. If not present and mutual auth not enabled, then there was a problem with mutual auth setup.
        if ($shouldExist) {
            logInfo "Parameter $paramName expected but not found in config.xml.";
        }
        return !($shouldExist);
    } else {
        if (!($shouldExist)) {
            logInfo "Parameter $paramName found but not expected in config.xml.";
            return $false;
        }
    }

    if ($node.value -eq "" -or $node.value -eq $templateValue) {
        logInfo "Parameter $paramName failed to update in config.xml."
        return $false
    }
    return $true;
}

function setup {

    if (Test-Path -Path "${mid_container_dir}") {
        logInfo "Found ${mid_container_dir}"
        if (!(Test-Path -Path "${mid_container_dir}\agent")) {
            logInfo "No ${mid_container_dir}\agent directory, populating from container"
            Copy-Item -Path "${current_dir}\agent" -Destination "${mid_container_dir}\agent" -Recurse
            if (Test-Path -Path "${current_dir}\agent.dist") {
                Remove-Item -Path "${current_dir}\agent.dist" -Recurse -Force
            }
            Rename-Item -Path "${current_dir}\agent" -NewName "${current_dir}\agent.dist"
            New-Item -Path "${current_dir}\agent" -ItemType SymbolicLink -Value "${mid_container_dir}\agent"
        }
        else {
            logInfo "Checking agent subdir"
            if (Test-Path -Path "${current_dir}\agent" -PathType Container) {
                logInfo "Creating ./agent symlink"
                if (Test-Path -Path "${current_dir}\agent.dist") {
                    Remove-Item -Path "${current_dir}\agent.dist" -Recurse -Force
                }
                Rename-Item -Path "${current_dir}\agent" -NewName "${current_dir}\agent.dist"
                New-Item -Path "${current_dir}\agent" -ItemType SymbolicLink -Value "${mid_container_dir}\agent"
            }
        }
    }
    dir ${current_dir}
    # restore the config, wrapper config and other metadata files
    if (Test-Path -Path "${mid_container_dir}\config.xml" -PathType Leaf ) {
        logInfo "Restore the config and other metadata files from the persistent volume"
        Copy-Item "${mid_container_dir}\config.xml" -Destination "$config_file" -Force -ErrorAction Continue
        Copy-Item "${mid_container_dir}\wrapper-override.conf" -Destination "$wrapper_file" -Force -ErrorAction Continue
        Copy-Item "${mid_container_dir}\.initialized" -Destination "$init_file" -Force -ErrorAction Continue
        Copy-Item "${mid_container_dir}\.container" -Destination "$container_meta_file" -Force -ErrorAction Continue
        Copy-Item "${mid_container_dir}\glide.properties" -Destination "${current_dir}\agent\properties\" -Force -ErrorAction Continue
    }

    if ($force -or -not (isInitialized)) {
        logInfo "Setup MID server";

        # Update configuration files. remote.properties is updated by startup sequencer when MID starts.
        if (Test-Path $config_file) {
            updateConfigXMLFromEnvVars $config_file;
        } else {
            logInfo "Could not find config.xml in path: $config_file. Unable to complete setup."
            return $false;
        }

        if (Test-Path $wrapper_file) {
            updateWrapperConfFromEnvVars $wrapper_file;
        } else {
            logInfo "Could not find wrapper-conf.override in path: $wrapperFilePath. Unable to complete setup."
            return $false;
        }

        $useMutualAuth = $false;
        # install mutual auth certificate
        $MID_MUTUAL_AUTH_PEM_FILE = [System.Environment]::GetEnvironmentVariable('MID_MUTUAL_AUTH_PEM_FILE');
        if (-not [String]::IsNullOrWhiteSpace($MID_MUTUAL_AUTH_PEM_FILE) -and (Test-Path -Path "$MID_MUTUAL_AUTH_PEM_FILE")) {
            logInfo "Install the mutual auth PEM file `"$MID_MUTUAL_AUTH_PEM_FILE`"";
            $_cmd = "`"${manage_certificates_bat_file}`" -a `"DefaultSecurityKeyPairHandle`" `"${MID_MUTUAL_AUTH_PEM_FILE}`"";
            & "$Env:SystemRoot\System32\cmd.exe" /c $_cmd;

            logInfo "Enabling mutual auth"
            $_cmd = "`"${manage_certificates_bat_file}`" -m"
            & "$Env:SystemRoot\System32\cmd.exe" /c $_cmd;

            $useMutualAuth = $true;
        }
        # mark that the mid server is initialized
        Add-Content -Path "$init_file" -Value "$(Get-Date)";

		# update .container with Env Var MID_CONTAINER_DEPLOYMENT_NAME, MID_CONTAINER_DEPLOYMENT_NAMESPACE and DEPLOYMENT_MID_ID
		$MID_CONTAINER_DEPLOYMENT_NAME = [System.Environment]::GetEnvironmentVariable('MID_CONTAINER_DEPLOYMENT_NAME');
        $MID_CONTAINER_DEPLOYMENT_NAMESPACE = [System.Environment]::GetEnvironmentVariable('MID_CONTAINER_DEPLOYMENT_NAMESPACE');
        $DEPLOYMENT_MID_ID = [System.Environment]::GetEnvironmentVariable('DEPLOYMENT_MID_ID');
		$containerProps = @{};
        if ((-not [String]::IsNullOrWhiteSpace($MID_CONTAINER_DEPLOYMENT_NAME)) -and (-not [String]::IsNullOrWhiteSpace($DEPLOYMENT_MID_ID))) {
			$containerProps.Add('ContainerDeploymentName', $MID_CONTAINER_DEPLOYMENT_NAME);
			$containerProps.Add('DeploymentMidId', $DEPLOYMENT_MID_ID);
		}
        if (-not [String]::IsNullOrWhiteSpace($MID_CONTAINER_DEPLOYMENT_NAMESPACE)) {
            $containerProps.Add('ContainerDeploymentNamespace', $MID_CONTAINER_DEPLOYMENT_NAMESPACE);
		}
        updateContainerMetaFileFromEnvVars $container_meta_file $containerProps;
    }
    # Validate that required parameters have been populated
    $validated = validateMandatoryParameters $useMutualAuth
    if ($validated -eq $false) {
        logInfo "One or more required parameters failed to update in Config.xml."
        return $false;
    }
    return $true;
}

switch ($cmd) {
    "mid:setup" {
        setup;
    }

    "mid:start" {
        $setupResult = setup;
        if ($setupResult -eq $false) {
            $errMsg = "Setup was not completed successfully. Abandoning MID Server startup."
            logInfo $errMsg
            throw $errMsg
        }

        logInfo "MID server is starting";
        Start-Process -NoNewWindow -FilePath "$env:comspec" -WorkingDirectory "$current_dir" -ArgumentList "/c","agent\start.bat";

        # Follow the rolling agent log file
        $max_wait_seconds = 300;
        $wait_time = 0;
        while ($wait_time -le $max_wait_seconds) {
            if (Test-Path "$agent_log_file") {
                try {
                    logInfo "Reading `"$agent_log_file`"";
                    Get-Content -Path "$agent_log_file" -Wait;
                } catch {
                    logInfo "Reading `"$agent_log_file`" is interrupted.";
                    $wait_time = 0;
                }
            }
            Start-Sleep 1;
            $wait_time = $wait_time + 1;
            if ($wait_time % 5 -eq 0) {
                logInfo "Wait $wait_time seconds for the agent log file";
            }
        }
    }

    "mid:stop" {
        logInfo "Stop MID server"
        Start-Process -NoNewWindow -FilePath "$env:comspec" -WorkingDirectory "$current_dir" -ArgumentList "/c","agent\stop.bat";
    }

    "mid:restart" {
        logInfo "Restart MID server"
        Start-Process -NoNewWindow -FilePath "$env:comspec" -WorkingDirectory "$current_dir" -ArgumentList "/c","agent\restart.bat";
    }
}
