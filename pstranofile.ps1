# Generally you don't need to edit this file
# Use deploy.ps1 for your custom project settings instead
include 'config\deploy.ps1'

[string]$script:user = $null
[hashtable]$script:vars = @{}

# Default Settings
$vars["install_util"] = '\Windows\Microsoft.NET\Framework\v2.0.50727\InstallUtil.exe'
$vars["scm"] = 'git'
$vars["scm_command"] = '\Program Files\Git\bin\git'
$vars["deployment_tools_url"] = "http://file.bluedotsolutions.com/public/Deployment_tools (1).zip"
$vars["remote_pstrano_url"] = "http://github.com/downloads/tclem/pstrano/remotepstrano.zip"

setup {

	$vars["environment"] = $script:defaultEnvironment
	CheckVars
	Write-Host ("Connecting to {0} host(s): " -f $roles.web.count) -NoNewline
	$roles.web | %{ "$_, " | Write-Host -NoNewline  }
	Write-Host
	
	if ($vars["user"] -eq $null){
		Write-Host ("Deployment Credentials set to {0}" -f ([Security.Principal.WindowsIdentity]::GetCurrent()).Name) 
	}
	else{
		$vars["user"] = $host.ui.PromptForCredential("Deployment User", "Enter password for deployment user", $vars["user"],"")
		Write-Host ("Deployment Credentials set to {0}" -f $vars["user"].Username) 
	}
	# if ($vars["user"] -eq $null){
		# $vars["user"] = ([Security.Principal.WindowsIdentity]::GetCurrent()).Name
	# }
	# $vars["user"] = $host.ui.PromptForCredential("Deployment User", "Enter password for deployment user", $vars["user"],"")
	# Write-Host ("Deployment Credentials set to {0}" -f $vars["user"].Username) 
		
	if ($vars["service_user"] -ne $null){
		$vars["service_user"] = $host.ui.PromptForCredential("Service User", "Enter password for service user", $vars["service_user"],"")	
	}
	else{
		$vars["service_user"] = $vars["user"]
	}	
	Write-Host ("Service Credentials set to {0}" -f $vars["service_user"].Username) 
	
	if ($vars["download_user"] -ne $null){
		$vars["download_user"] = $host.ui.PromptForCredential("Download User", "Enter password for package download user", $vars["download_user"],"")		
	}
	else{
		$vars["download_user"] = $vars["user"]
	}	
	Write-Host ("Download Credentials set to {0}" -f $vars["download_user"].Username) 		
	Write-Host	
	
	if ($vars["user"] -eq $null){
		$sessions = New-PSSession $roles.web
	}
	else{
		$sessions = New-PSSession $roles.web -Credential $vars["user"]
	}
	SetupRemoteFunctions $sessions

	# this setups db server remote session
	#$dbSession = New-PSSession $roles.db[0] -Credential $vars["user"]
	#SetupRemoteFunctions $dbSession
}

teardown {
	$sessions | Remove-PSSession
	# this tearsdown db server remote session
	#$dbSession | Remove-PSSession
}

task Setup {
	RunBoth {
		#CheckCreatePath $deploy_dir
		CheckCreatePath ( $deploy_dir_releases )
		#CheckCreatePath ( $deploy_dir_shared )
		CheckCreatePath ( $deploy_dir_current )
		
		cd $deploy_dir_shared
		if(!(Test-Path 'tools.zip')){
			WriteHostName "Downloading tools to "
			(Get-WebFile2 $vars["deployment_tools_url"] 'tools.zip') | Write-Host -ForegroundColor DarkGray
			
			WriteHostName 'Extracted package to '
			(Unzip 'tools.zip' 'tools') | Write-Host -ForegroundColor DarkGray
		}
		CheckFile ( Join-Path $deploy_dir_shared '\tools\junction.exe' )
		Write-Host "!Make sure you run junction once manually (double click on the .exe) and accept the license agreement!" -ForegroundColor Green
	}
} -description "Sets up each of the web server roles" 

task Check {
	Invoke-Command $sessions {
		if($vars["deploy_via"] -eq 'remote_cache'){
			Assert(Test-Path $scm_cmd) "Failed: Cannot find scm exe (scm_command) here: $scm_cmd"
		}
	}
} -description "Checks server dependencies and such"

task Deploy {
} -description "Deploys your project"

task DeployViaRemoteCache {
	Invoke-Command $sessions {
		# get the latest code from the scm
		WriteHostName
		$cached_copy = Join-Path $deploy_dir_shared '\cached-copy'
		if(!(Test-Path $cached_copy)){
			# clone the repo
			(& $scm_cmd clone $repo "$cached_copy") | Write-Host -ForegroundColor DarkGreen
		}
		else{
			# pull the repo
			cd $cached_copy 
			(& $scm_cmd pull) | Write-Host -ForegroundColor DarkGreen
		}
	}
} -description "Deploys your project via remote cache" -precondition { return ($vars["deploy_via"] -eq 'remote_cache')}

task DeployViaHttp {

	Invoke-Command $sessions {
		cd $deploy_dir_shared
		
		WriteHostName "Downloading from $http_download_url to "
		(Get-WebFile2 $http_download_url 'package.zip') | Write-Host -ForegroundColor DarkGray
#		$f = (Get-WebFile $http_download_url)
#		Write-Host "$filename" -ForegroundColor DarkGray
		
		WriteHostName 'Extracted package to '
		($cached_copy = UnZip 'package.zip' 'package') | Write-Host -ForegroundColor DarkGray
#		($cached_copy = UnZip $f) | Write-Host -ForegroundColor DarkGray
		
		# bits doesn't work over pssession :(
#		Import-Module BitsTransfer
#		Start-BitsTransfer $bits_package (Join-Path $deploy_dir 'package.zip')
	}
	
} -description "Deploys your project via Http" -precondition { return ($vars["deploy_via"] -eq 'http')}

task UpdateRelease {
	Invoke-Command $sessions {
		# the release directory
		$release_dir = Join-Path $deploy_dir_releases "\$release_time_stamp"
		
		# copy over the latest-greatest
		Copy-Item $cached_copy $release_dir -Recurse
		WriteHostName
		Write-Host ("Copied the latest cached version to {0}" -f $release_dir) -ForegroundColor Magenta
	}
}

task SymLink {
	Invoke-Command $sessions {
	
		# this should work in iis
		$juncExe = (Join-Path $deploy_dir_shared '\tools\junction.exe')
		if(Test-Path $deploy_dir_current){
			& $juncExe -d "$deploy_dir_current"
		}
		& $juncExe "$deploy_dir_current" "$release_dir"
		
		# this doesn't actually work for iis
#		$current_symlnk = (Join-Path $deploy_dir '\current.lnk')
#		$shell = New-Object -COM WScript.Shell
#		$shortcut = $shell.CreateShortcut($current_symlnk)
#		$shortcut.TargetPath = Resolve-Path $release_dir
#		$shortcut.Save()

		WriteHostName
		Write-Host ("Created Symlink {0}" -f $current_symlnk) -ForegroundColor Magenta
	}
} -description "Creates the final symlink to the just released version"


task Restart{
	#todo: restart iis or windows services
}

# Task ordering 
after Deploy -do DeployViaRemoteCache, DeployViaHttp, UpdateRelease
after UpdateRelease -do SymLink

task Rollback {
	Invoke-Command $sessions {
		# find the current version
		$current = Get-ChildItem $deploy_dir current.lnk
		$shell = New-Object -COM WScript.Shell
		$shortcut = $shell.CreateShortcut($current.fullname)
		$current_release = Split-Path $shortcut.TargetPath -Leaf
		"Current release is {0}" -f $current_release
		
		# find the previous version
		$releases_dir = Join-Path $deploy_dir 'releases'
		$prev_release = Get-ChildItem $releases_dir | where {$_.Name -lt $current_release} | sort Name -Descending | select -First 1
		if ($prev_release -eq $null) { throw "Failed: Nothing to rollback to" }
		"Previous release is {0}" -f $prev_release
		
		# do the rollback
		$shortcut.TargetPath = Resolve-Path (Join-Path $deploy_dir "releases\$prev_release")
		$shortcut.Save()
	}
} -description "Rollsback to the previous deployment"

function Run
{
	param([scriptblock]$script)
	Invoke-Command $sessions $script
}

function RunBoth
{
	param([scriptblock]$script)

	Invoke-Command $sessions $script
	if ($roles.web[0] -ne $roles.db[0]){
		Invoke-Command $dbSession $script
	}
}

function RunDb
{
	param([scriptblock]$script)
	Invoke-Command $dbSession $script
}

# Private Functions
function CheckVars
{
	$roles.web | %{ "$_ " } | Write-Verbose
	$deploy_to = $vars['deploy_to']
	$deploy_via = $vars['deploy_via']
	$repository = $vars["repository"]
	$scm = $vars["scm"]
	$scm_command = $vars["scm_command"]
	
	Write-Verbose "deploy_to = $deploy_to"
	Write-Verbose "scm = $scm"
	Write-Verbose "scm_command = $scm_command"
	Write-Verbose "repository = $repository"
	Write-Verbose "deploy_via = $deploy_via"
	
	Assert $roles.ContainsKey('web') "Failed: No servers defined for the web role, You must define at least 1 web server"
	Assert ($deploy_to -ne $null) "Failed: deploy_to has not been set"
	Assert ($deploy_via -ne $null) "Failed: You must specify a value for deploy_via"
	if($deploy_via -eq 'remote_cache'){
		Assert ($scm -eq 'git') "Failed: The only support scm is git right now"
		Assert ($scm_command -ne $null) "Failed: You must specify the scm_command"
		Assert (($repository -ne $null)) "Failed: You must specify the repository"
	}
	elseif($deploy_via -eq 'http'){
		Assert (($vars["http_source"] -ne $null)) "Failed: You must specify the http_source"
	}
	else{
		throw "Failed. You must specify either 'remote_cache' or 'http' as your deploy_via strategy"
	}
}

function SetupRemoteFunctions
{
	param($sessions_p)
	
	Invoke-Command $sessions_p {
		param($vars_p, $roles_p)
		
		$vars = $vars_p
		$roles = $roles_p
		
		$repo = $vars["repository"]
		$scm = $vars["scm"]
		$scm_cmd = $vars["scm_command"]
		$http_download_url = $vars["http_source"]
		$deploy_strategy = $vars["deploy_via"]
		$deploy_dir = $vars["deploy_to"]

    	if(!(Test-Path $deploy_dir)){
            [void](md $deploy_dir -ea 0)
            if(!(Test-Path $deploy_dir)){
                if ($deploy_dir.Contains(":")){
                    $deploy_dir = $deploy_dir.Substring(2)
                }
            }    
		}

		$deploy_dir_current = (Join-Path $deploy_dir '\current')
		$deploy_dir_shared = (Join-Path $deploy_dir '\shared')
		$deploy_dir_releases = (Join-Path $deploy_dir '\releases')
		$release_time_stamp = [DateTime]::Now.ToString("yyyyMMddhhmmss")
		$host_name = hostname
		
		$vars.Keys | %{ "$_ : " + $vars["$_"]  } | Write-Host -ForegroundColor DarkGray
	
		# this is a little crazy (duplicating these functions out of the remote module)
		# but we have a chicken before the egg problem where for the first deployment
		# these function have to be exported remotely in order to even get our remote module!!
		if(!(Test-Path $deploy_dir_shared )){
			[void](md $deploy_dir_shared )
			cd $deploy_dir_shared

			function WriteHostName {
				param([string]$text)
				Write-Host ("[{0}]# $text" -f (hostname)) -ForegroundColor DarkGray -NoNewline
			}
			function Get-WebFile2 {
				param( 
					$url = (Read-Host "The URL to download"),
					$fileName = $null
				)
				if($fileName -and !(Split-Path $fileName)) {
					$fileName = Join-Path (Get-Location -PSProvider "FileSystem") $fileName
				} 
				$client = New-Object Net.WebClient
				$client.Credentials = $vars["download_user"]
				$client.DownloadFile($url, $fileName)
				if($fileName){
					ls $fileName
				}
			}
			function UnZip{
				param([string]$file, [string]$name = 'UnPack')
				
				$shell=new-object -com shell.application
				$CurrentLocation= get-location 
				$CurrentLocation = Join-Path $CurrentLocation $name
				if(Test-Path $CurrentLocation){ rm $CurrentLocation -Force -Recurse }
				mkdir $CurrentLocation -Force
				$Location=$shell.namespace($CurrentLocation)
				$ZipFiles = get-childitem $file
				foreach ($ZipFile in $ZipFiles){
					$ZipFolder = $shell.namespace($ZipFile.fullname)
					$Location.CopyHere($ZipFolder.Items())
				}
			}
		
			WriteHostName "Downloading remote pstrano module to "
			
			(Get-WebFile2 $vars["remote_pstrano_url"] 'remote_pstrano.zip') | Write-Host -ForegroundColor DarkGray
			
			WriteHostName 'Extracted package to '
			(Unzip 'remote_pstrano.zip' 'remote_pstrano') | Write-Host -ForegroundColor DarkGray
		}
		Import-Module (Join-Path $deploy_dir_shared 'remote_pstrano\PstranoRemote.psd1')
		
	} -ArgumentList $script:vars, $roles
}
