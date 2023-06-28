param([String] $download_url, [String] $local_file, [String] $signature_verification)

Write-Host "Validate build arguments";
if ([String]::IsNullOrWhiteSpace($download_url) -and 
    [String]::IsNullOrWhiteSpace($local_file)) {
    throw "Both MID_INSTALLATION_FILE and MID_INSTALLATION_URL are missing!";
} 

if (-not [String]::IsNullOrWhiteSpace($local_file)) {
    Write-Host "Check the local installation file $local_file";
    if (Test-Path $local_file -PathType Leaf) {
        $file_extension = [System.IO.Path]::GetExtension($local_file);
        if (".zip" -ne $file_extension) {
            throw "The installation file must be a ZIP file!";
        }
        Write-Host "Rename $local_file to mid.zip";
        Rename-item -Path $local_file -NewName "mid.zip" -Force
    } else {
        throw "The local installation file $local_file doesn't exist";
    }
} else {
    Write-Host "Validate the download link $download_url";
    $tmp_file = Split-Path $download_url -leaf;
    if (-not [String]::IsNullOrWhiteSpace($tmp_file)) {
        $file_extension = [System.IO.Path]::GetExtension($tmp_file);
        if (".zip" -ne $file_extension) {
            throw "The download file must be a ZIP file!";
        }
        Write-Host "Downloading $tmp_file from $download_url";
        $ProgressPreference = 'SilentlyContinue'; # accelerate downloading
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 ;
        Invoke-WebRequest -Uri $download_url -OutFile $tmp_file -UseBasicParsing;
        Write-Host "Check the downloaded file $tmp_file";
        if (-not (Test-Path $tmp_file -PathType Leaf)) {
            throw "The downloaded file $tmp_file doesn't exist.";        
        }
        Write-Host "Rename $tmp_file to mid.zip";
        Rename-item -Path $tmp_file -NewName "mid.zip" -Force
    } else {
        throw "The download link $download_url is invalid!";  
    }
}

if ("TRUE" -eq $signature_verification) {
    Write-Host ("Install OpenJDK from https://adoptopenjdk.net/archive.html");
    Write-Host ("Downloading {0} ..." -f $env:JAVA_URL);
    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12;
    Invoke-WebRequest -Uri $env:JAVA_URL -OutFile openjdk.zip -UseBasicParsing;
    Write-Host ("Verifying OpenJDK sha256 checksum {0} ..." -f $env:JAVA_SHA256);
    $sha256 = (Get-FileHash openjdk.zip -Algorithm sha256).Hash;
    if ($sha256 -ne $env:JAVA_SHA256) { 
        throw ("SHA256 mismatched: {0} (downloaded) <> {1} (expected)" -f $sha256, $env:JAVA_SHA256) 
    }

    Write-Host 'Installing OpenJDK ...';
    Expand-Archive -Path openjdk.zip -DestinationPath C:\ ;
    Remove-Item -Path openjdk.zip -Force;
 
    $newPath = ("{0}\bin;{1}" -f $env:JAVA_HOME, $env:PATH);
    Write-Host ("Update PATH for current session: {0}" -f $newPath);
    [Environment]::SetEnvironmentVariable('PATH', $newPath);
 
    Write-Host "javac -version: " -NoNewLine; 
    javac -version
    Write-Host "Verifying signature of the MID installation file ...";
    jarsigner -verify -strict -verbose:grouped mid.zip | Out-String | Tee-Object -Variable result > $null
    Write-Host "jarsigner result is `n$result";
    $signer_org = "O=ServiceNow";
    if ($result -NotMatch "(?m)^jar verified\.\s*" -or $result -NotMatch "(?m)^- Signed by(.+)${signer_org}(.*)$") {
        throw "Signature verification failed!";
    }
} else { 
    Write-Host "MID_signature_verification is $signature_verification";
    Write-Host "Skip the MID installation file signature verification!";
} 
