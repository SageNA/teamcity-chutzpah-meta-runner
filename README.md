# TeamCity Chutzpah Meta-Runner
TeamCity meta-runner for the Chutzpah Console JavaScript test runner. Does not require Chutzpah to be pre-installed on agents as the runner can automatically download the latest
Chutzpah Console NuGet package.

## How to use

### Installing plugin in TeamCity
Copy the plugin zip (ChutzpahConsole-plugin.zip) into the main TeamCity plugins directory, located at _**\<TeamCity Data Directory>**/plugins_. 
It will automatically get unpacked into the Build Agent Tools folder located at _**\<TeamCity Home>**/buildAgent/tools_.

If you are not sure where the home or data directories are located you can find them in the Administration section of TeamCity.

### Added Meta-Runner to Build Configuration

Once the plugin has unpacked you should see _Chutzpah Console_ as an option when you add a new build step in you build configuration. Test folder is the only manadatory field 
and should match the -path parameter for the chutzpah console exe.

![Setup Report Tab](https://joncubed.github.io/teamcity-chutzpah-meta-runner/assests/teamcity-build-step.png)

### Set Up Code Coverage
If you want to display the code coverage results as another tab on the build results page and the summary on the overview page, you will need to add an artifact.

For each project that is doing code coverage you will also need to add the generated code coverage file as a build artifact.
![Setup Report Tab](https://joncubed.github.io/teamcity-chutzpah-meta-runner/assests/teamcity-build-artifacts.png)

## How to build the plugin

This requires PowerShell 5.0
Run build-plugin.ps1 from root folder and the plugin will be created in _**./.artifacts**_ as ChutzpahConsole-plugin.zip 
````PowerShell
PS c:\source\teamcity-chutzpah-meta-runner>.\build-plugin.ps1
````

