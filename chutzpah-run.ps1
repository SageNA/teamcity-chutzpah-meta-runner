<#
 #>
param (
    [string]$workingDir, # Optionally specify the working directory
    [string]$nugetExe = ".\.nuget\NuGet.exe", # The path to the NuGet executable, only required if useExistingPackage is not set
    [switch]$useExistingPackage, # Use the existing Chutzpah NuGet package, typically that was downloaded by version in an earlier build step
    [string]$path,        # Adds semicolon-separated paths to folders or files to the list of test paths to run.
    [switch]$teamcity,    # Forces TeamCity mode (normally auto-detected)
    [switch]$coverage,    # Enable coverage collection
    [switch]$failOnError, # Throws an exception if any script errors or timeouts occurs, resulting in the build step failing
    [switch]$debug        # Print debugging information and tracing to the console
)

$params = @() # An array of parameters to pass to the console program

# Sometimes the build runner works from the working directory and sometimes from its own location, so explicitly run
# from the working directory.
if ($workingDir -ne $null) {
    if ($workingDir -ne $PWD) {
        Write-Output "Setting the working directory to $workingDir from $PWD"
        cd $workingDir
    } else {
        Write-Output "The working directory is $PWD"
    }
}

if ($path) {
    # TeamCity seems to vary in how parameters are passed, with the result that if the outer script uses quotes around
    # a paths list that potentially contains a semicolon the quotes sometimes get passed in.
    # So if there are matched opening and closing quotes then remove them; they are clearly not supposed to be part of
    # the path.
    $pathFirstChar = $path.Substring(0,1)
    if (@("'",'"').contains($pathFirstChar)) {
        $path = $path.Trim($pathFirstChar)
    }

    # Now we can safely split at the semicolons
    $pathsSpecified =  $false
    foreach ($pathLine in ($path -split ';')) {
        if (Test-Path -Path $pathLine) {
            $params += "/path `"$pathLine`""
            $pathsSpecified = $true
        } else {
            Write-Output "Ignoring path $pathLine as it does not exist"
        }
    }
    if (-not $pathsSpecified) {
        throw New-Object System.ArgumentException(
                'Aborting since none of the specified paths exist')
    }
}

if ($teamcity) {
    $params += "/teamcity"
}

if ($coverage) {
    # set up to place the coverage file straight into an index.html that can be defined as an artifact so that TeamCity
    # will give it a tab automatically
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

Write-Output "Command line parameters passed to the console runner:"
$params | Out-String | Write-Output

if ($useExistingPackage) {
    # If we are using an existing NuGet package (e.g. fetched by an earlier build step) it may have been fetched by
    # version.
    # There is a small risk that a versionless version may actually be newer than the last versioned one, or that they
    # may be fetched in a strange order; we accept that risk.
    Write-Output "Looking for package under $PWD"
    if (Test-Path packages -PathType Container) {
        $ChutzpahPackageFileInfo = (Get-ChildItem -Path packages | where {$_.Name -match '^Chutzpah((.[0-9]+)*)$'} |
                                    Select-Object -Last 1)
        if ($ChutzpahPackageFileInfo -eq $null)
        {
            throw New-Object System.ArgumentException(
                    'useExistingPackage was specified but no Chutzpah package was found')
        }
        $ChutzpahPackage = $ChutzpahPackageFileInfo.name
        Write-Output "Using existing Chutzpah package $ChutzpahPackage"
    } else {
        throw New-Object System.ArgumentException(
                'useExistingPackage was specified but no NuGet packages folder was found')
    }
} else {
    # Get the latest Chutzpah
    . $nugetExe Install "Chutzpah" -OutputDirectory "packages" -ExcludeVersion
    $ChutzpahPackage = 'Chutzpah'
    Write-Output "Using the latest Chutzpah package"
}

# Run the tests and generate coverage
# When Chutzpah automatically detects that it is running under TeamCity or is told to assume it is it sends the test
# results to TeamCity through messages, but not the coverage
Invoke-Expression ".\packages\$ChutzpahPackage\tools\chutzpah.console.exe $params"
# Remember the return code, in case we are supposed to fail on error
$ChutzpahReturnCode = $LASTEXITCODE

if ($coverage) {
    # If required extract coverage statistics out of the coverage report and send them to TeamCity so that they appear
    # on the Overview tab of a run
    # Send the statistics as 'line coverage' so that it does not collide with Class/Method/Block coverage from .NET
    # coverage
    # A working method appears to be simply to take the last percentage and ratio from the coverage file; it is much
    # easier than trying to parse and navigate the html
    if (Test-Path $ChutzpahCoverageFilePath) {
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
    } else {
        Write-Error "For some reason the coverage file was not generated." -ErrorAction Continue
    }
}

# Ensure that the build step counts as failed if that was requested
if ($failOnError -and $ChutzpahReturnCode -ne 0) {
    # Although throwing an exception within a direct PowerShell step results in the step failing
    # it does not work in a PowerShell-based TeamCity plugin. So instead report the error and exit explicitly
    Write-Error "The test run failed in some way. Refer to the log for details." -ErrorAction Continue
    exit -1
}
