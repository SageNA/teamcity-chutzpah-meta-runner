<#
 #>
param (
    [string]$nugetExe = ".\.nuget\NuGet.exe", # The path to the NuGet executable, only required if useExistingPackage is not set
    [switch]$useExistingPackage, # Use the existing Chutzpah NuGet package, typically that was downloaded by version in an earlier build step
    [string]$path,        # Adds semicolon-separated paths to folders or files to the list of test paths to run.
    [switch]$teamcity,    # Forces TeamCity mode (normally auto-detected)
    [switch]$coverage,    # Enable coverage collection
    [switch]$failOnError, # Throws an exception if any script errors or timeouts occurs, resulting in the build step failing
    [switch]$debug        # Print debugging information and tracing to the console
)

$params = @() # An array of parameters to pass to the console program

if ($path) {
    foreach ($pathLine in ($path -split ';')) {
        $params += "/path `"$pathLine`""
    }
}

if ($teamcity) {
    $params += "/teamcity"
}

if ($coverage) {
    # set up to place the coverage file straight into an index.html that can be defined as an artifact so that TeamCity will give it a tab automatically
    # e.g. https://blog.jetbrains.com/teamcity/2013/02/continuous-integration-for-php-using-teamcity/
    $ChutzpahCoverageFolderName = '_ChutzpahCoverage'
    $ChutzpahCoverageFileName = 'index.html'
    # We should be OK using the relative path rather than an absolute path
    $ChutzpahCoverageFilePath = ($ChutzpahCoverageFolderName | Join-Path -ChildPath $ChutzpahCoverageFileName)
    if (!(Test-Path $ChutzpahCoverageFolderName)) {
        mkdir $ChutzpahCoverageFolderName >$null
    }
    $params += "/coverage"
    $params += "/coveragehtml $ChutzpahCoverageFilePath"
}

if ($failOnError) {
     $params += "/failOnError"
}

if ($debug) {
     $params += "/debug"
}

Write-Output "Command line parameters passed in:"
$params | Out-String | Write-Output

if ($useExistingPackage) {
    # If we are using an existing Nuget package (e.g. fetched by an earlier build step) it may have been fetched by version
    # There is a small risk that a versionless version may actually be newer than the last versioned one, or that they may be fetched in a strange order
    $ChutzpahPackage = ((Get-ChildItem -Path packages) | where {$_ -match '^Chutzpah((.[0-9]+)*)$'} | Select-Object -Last 1).name
} else {
    # Get the latest Chutzpah
    . $nugetExe Install "Chutzpah" -OutputDirectory "packages" -ExcludeVersion
    $ChutzpahPackage = 'Chutzpah'
}

# Run the tests and generate coverage
# Chutzpah automatically detects that it is running under TeamCity and sends the test results to TeamCity through messages
Invoke-Expression ".\packages\$ChutzpahPackage\tools\chutzpah.console.exe $params"
$ChutzpahReturnCode = $LASTEXITCODE

if ($coverage) {
    # If required mine coverage statistics out of the coverage report and send them to TeamCity so that they appear on the Overview tab of a run
    # Send the statistics as 'line coverage' so that it does not collide with Class/Method/Block coverage from .NET coverage
    # A working method appears to be simply to take the last percentage and ratio from the coverage file; it is much easier than trying to parse and navigate the html
    $all = Get-Content $ChutzpahCoverageFilePath
    $percentage = ($all | where {$_ -match '^[\s]*[0-9]+\.[0-9]+[\s]*%$'} | Select-Object -Last 1)
    if ($percentage -ne $null) {
        "##teamcity[buildStatisticValue key='CodeCoverageB' value='$($percentage.replace('%','').trim())']"
    }
    $ratio = ($all | where {$_ -match '^[\s]*[0-9]+[\s]*/[\s]*[0-9]+[\s]*$'} | select-object -last 1)
    if ($ratio -ne $null) {
        $ratioArray = $ratio.split('/')
        "##teamcity[buildStatisticValue key='CodeCoverageAbsLCovered' value='$($ratioArray[0].trim())']"
        "##teamcity[buildStatisticValue key='CodeCoverageAbsLTotal' value='$($ratioArray[1].trim())']"
    }
    Write-Output "Ensure that in the General Settings your Artifacts paths includes '$ChutzpahCoverageFolderName=>Coverage.zip' to have the coverage tab added automatically"
}

# Ensure that the build step counts as failed if that was requested
if ($failOnError -and $ChutzpahReturnCode -ne 0) {
    throw "The test run failed in some way. Refer to the log for details."
}
