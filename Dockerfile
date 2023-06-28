# escape=`
FROM mcr.microsoft.com/windows/servercore:ltsc2019 as builder
SHELL ["powershell"]

WORKDIR "C:\snc_mid_server\"
COPY asset\* .\

ARG MID_INSTALLATION_URL=<put MID download URL here>
ARG MID_INSTALLATION_FILE
ARG MID_SIGNATURE_VERIFICATION=TRUE

ENV JAVA_HOME="C:\jdk8u282-b08" `
    JAVA_VERSION="1.8.0_282" `
    JAVA_URL="https://github.com/AdoptOpenJDK/openjdk8-binaries/releases/download/jdk8u282-b08/OpenJDK8U-jdk_x64_windows_hotspot_8u282b08.zip" `
    JAVA_SHA256="e0862e9978a49f162f0d50a0347a189b33f90bad98207535df1969299d0e4167"

# Use the local installation file or download from the provided URL
# If MID_SIGNATURE_VERIFICATION=TRUE then install OpenJDK and verify signature
RUN $ErrorActionPreference = 'Stop'; `
    .\download.ps1 -download_url $env:MID_INSTALLATION_URL `
    -local_file $env:MID_INSTALLATION_FILE `
    -signature_verification $env:MID_SIGNATURE_VERIFICATION;

# Create final image
FROM mcr.microsoft.com/windows/servercore:ltsc2019
SHELL ["powershell"]

WORKDIR "C:\snc_mid_server\"
COPY --from=builder "C:\snc_mid_server\mid.zip" mid.zip
COPY asset\install.ps1 asset\init.ps1 asset\healthcheck.ps1 asset\post_start.ps1 asset\pre_stop.ps1 asset\.container .\

# Change ownership so that the file can be deleted
#RUN $acl = Get-Acl mid.zip; `
#    $newowner = [system.security.principal.ntaccount]('user manager\containeruser'); `
#    $acl.setOwner($newOwner); `
#    Set-Acl -path .\mid.zip -AclObject $acl; `
#    Set-Acl -path .\.container -AclObject $acl;

#RUN secedit /export /cfg c:\secpol.cfg; `
#    (gc C:\secpol.cfg) -replace 'SeCreateSymbolicLinkPrivilege = .*','SeCreateSymbolicLinkPrivilege = manager\containeruser,ContainerUser,ContainerAdministrator'|Out-File c:\secpol.cfg; `
#    secedit /configure /db c:\windows\security\local.sdb /cfg c:\secpol.cfg /areas SECURITYPOLICY; `
#    rm -force c:\secpol.cfg -confirm:$false;

# Switch to new owner
#USER ContainerUser

# Installation MID Server
RUN $ErrorActionPreference = 'Stop'; .\install.ps1 mid.zip;

# Define Environment Variables
ENV MID_INSTANCE_URL= `
    MID_INSTANCE_USERNAME= `
    MID_INSTANCE_PASSWORD= `
    MID_SERVER_NAME= `
    MID_USE_PROXY= `
    MID_PROXY_HOST= `
    MID_PROXY_PORT= `
    MID_PROXY_USERNAME= `
    MID_PROXY_PASSWORD= `
    MID_SECRETS_FILE= `
    MID_MUTUAL_AUTH_PEM_FILE= `
    MID_SSL_BOOTSTRAP_CERT_REVOCATION_CHECK= `
    MID_SSL_USE_INSTANCE_SECURITY_POLICY=

# Check if the wrapper PID file exists and a HeartBeat is processed in the last 30 minutes
HEALTHCHECK --interval=5m --start-period=3m --retries=3 --timeout=15s `
    CMD ["powershell", "-command", "./healthcheck.ps1",  "30"]

ENTRYPOINT ["powershell", "-command", "./init.ps1"]
CMD ["mid:start","-force"]
