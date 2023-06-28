
# Example Windows ServiceNow MID Server Image

**DISCLAIMER:** This example is provided as an academic exercise and comes with no support or warranty, implicit or explicit.

This recipe will build a container image for a Windows-based ServiceNow MID server, which can be run on an AWS Fargate container.

## Prerequisites

In order to run this container in AWS Fargate, the following are required:

- ECS Cluster designated for Fargate launch type/capacity provider
- AWS directory
- A mid server service account created in the above directory
- FsX for Windows filesystem tied to aforementioned AWS directory, owned by the mid server service account
- AWS secrets which store the following:
    1. MID user name on SN instance
    2. MID user password on SN instance
    3. MID instance URL
    4. Drive letter to use for FsX filesystem
    5. Path to FsX filesystem in UNC format
    6. User name from AWS directory for the mid server service account
    7. User password from AWS directory for the mid server service account
- ECS task definition which launches this image with the following environment variables defined:
    1. MID_INSTANCE_USERNAME, value take from secret #1 above
    2. MID_INSTANCE_PASSWORD, value take from secret #2 above
    3. MID_INSTANCE_URL, value take from secret #3 above
    4. SHARE_DRIVE, value take from secret #4 above
    5. SHARE_PATH, value take from secret #5 above
    6. SHARE_USER, value take from secret #6 above
    7. SHARE_PASSWD, value take from secret #7 above

## Building Image

This image is meant to be built using Azure DevOps (yes, I appreciate the irony; AWS CodeBuild doesn't seem to want to build Windows docker images).  Define the following variables in your ADO pipeline as a group named "docker-vars":
- DOCKER_PASS - docker hub password
- DOCKER_USER - docker hub username
Also, add the applicable MID download link to the Dockerfile.
Then create an ADO pipeline using the included azure-pipelines.yml file.

## Invocation

With the prerequisites set up, launching this container image via a Fargate task should produce a serverless Windows MID.  Mounting the FsX filesystem to a separate system will allow access to the full "agent" folder for monitoring, debugging, and further development.
