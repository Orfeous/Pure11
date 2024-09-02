#requires -runasadministrator

<#
    .SYNOPSIS
        Pure11. Windows 11, minus the junk they thought you needed.
    .DESCRIPTION
        Windows 11 arrives loaded with more than just an operating system—there's also bloatware, relentless telemetry, and a host of so-called 'features' designed to serve everyone except the end user.

        Pure11 cuts through the nonsense, providing a streamlined, privacy-focused, and highly efficient version of the operating system.

        This PowerShell script strips away the bloatware, removes ads, disables intrusive features, and performs essential system hardening, delivering a clean, secure, and responsive Windows 11 installation

        Pure11 is for those who prefer an OS that works for them, not the other way around.

    .PARAMETER BuildIso
        Builds the Pure 11 install iso.

    .PARAMETER Init
        When used in conjuction with [-Buildiso] it will create the required folder structure and exit.

    .LINK
        https://github.com/Orfeous/Pure11
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $false, HelpMessage = "Initializes the folder structure.")]
    [switch] $Init,
    [Parameter(Mandatory = $false, HelpMessage = "Builds a Pure11 install iso.")]
    [switch] $BuildIso
);

#region Imports
Add-Type -AssemblyName System.Windows.Forms; # Required to display gui stuff.
Add-Type -AssemblyName System.Drawing; # Same.
#endregion

#region Script State

[hashtable] $P11State = @{}; # Shared state for the script.
[array] $P11State.DetectedWindowsImages = @(); # List of the SKUs detected in install.wim (IsoBuild).
[string] $P11State.ImageName = [string]::Empty; # Name of the selected SKU, substitute with a string if you want to make the script automatic (IsoBuild). Ex: "Windows 11 Enterprise"
[string] $P11State.Language = [string]::Empty; # Primary language of the image (detected)
[string] $P11State.Edition = [string]::Empty; # Edition of the selected image (detected)
[string] $P11State.Architecture = [string]::Empty; # Architecture of the selected image (detected)
[string] $P11State.Build = [string]::Empty; # Build.SPBuild of the selected image (detected)
[string] $P11State.IsoPath = [string]::Empty; # Full path to the source ISO
[string] $P11State.IsoDrive = [string]::Empty; # Drive letter of the mounted source iso

#endregion

#region Constants & Globals

# Psst!
$ProgressPreference = 'SilentlyContinue';

# Consistent file-path friendly timestamp.
$P11DateTime = [DateTime]::Now.ToString("yyyy-MM-dd_HH-mm");

# Static locations
[hashtable] $P11Paths = @{};
[string] $P11Paths.LogDirectory = "${PSScriptRoot}\logs"; # Logs are stored here.
[string] $P11Paths.ConfigDirectory = "${PSScriptRoot}\config"; # Pure11 script config files are stored here.
[string] $P11Paths.RegistryConfigDirectory = "${PSScriptRoot}\config\reg"; # Registry customization files.
[string] $P11Paths.PostInstallScriptsDirectory = "${PSScriptRoot}\config\post-install"; # Scripts to be run on the deployed image.
[string] $P11Paths.IsoDirectory = "${PSScriptRoot}\iso"; # Generated ISO files are stored here.
[string] $P11Paths.WorkDirectory = "${PSScriptRoot}\work"; # The script will work inside this directory.
[string] $P11Paths.IsoSourceDirectory = "$($P11Paths.WorkDirectory)\iso-source"; # The contents of the source iso are cached here.
[string] $P11Paths.MountDirectory = "$($P11Paths.WorkDirectory)\mount"; # The wim files will be mounted here.
[string] $P11Paths.ScratchDirectory = "$($P11Paths.WorkDirectory)\scratch"; # Used by dism operations.
[string] $P11Paths.DriversDirectory = "$($P11Paths.WorkDirectory)\drivers"; # Place drivers here, they will be added to the image.
[string] $P11Paths.UpdatesDirectory = "$($P11Paths.WorkDirectory)\updates"; # Place windows updates here, they will be added to the image.

[string] $P11Paths.ScriptLogFile = "$($P11Paths.LogDirectory)\${P11DateTime}.Pure11.log"; # Pure11 script log.
[string] $P11Paths.DismLogFile = "$($P11Paths.LogDirectory)\${P11DateTime}.Dism.log"; # Dism log.

[string] $P11Paths.InstallWim = "$($P11Paths.IsoSourceDirectory)\sources\install.wim"; # Main install wim containing the deployable image.
[string] $P11Paths.BootWim = "$($P11Paths.IsoSourceDirectory)\sources\boot.wim"; # Boot and windows setup image.

[string] $P11Paths.OscdimgExe = "$($P11Paths.WorkDirectory)\oscdimg.exe"; # Used to create the bootable iso.
[string] $P11Paths.OscdimgUrl = "https://msdl.microsoft.com/download/symbols/oscdimg.exe/3D44737265000/oscdimg.exe"; # MS Symbol server to download oscdimg.exe from official source.
[string] $P11Paths.OscdimgChecksum = "F5129F313ED7EB46F2677CF522E64264A225F226307ED0DDB52BB14C46E7CFDD"; # SHA256 checksum of oscdimg.exe
[string] $P11Paths.AutounattendXml = "$($P11Paths.ConfigDirectory)\autounattend.xml"; # Source unattended file.
[string] $P11Paths.AutounattendXmlIso = "$($P11Paths.IsoSourceDirectory)\autounattend.xml"; # Destination unattended file.

[string] $P11Paths.AppxConfig = "$($P11Paths.ConfigDirectory)\appx.conf"; # Config file for AppXPackages to be removed.
[string] $P11Paths.FeaturesConfig = "$($P11Paths.ConfigDirectory)\features.conf"; # Config file for OptionalFeatures to be removed.
[string] $P11Paths.CapabilitiesConfig = "$($P11Paths.ConfigDirectory)\capabilities.conf"; # Config file for Capabilities to be removed.
[string] $P11Paths.FilesConfig = "$($P11Paths.ConfigDirectory)\files.txt"; # Config file for Files and Directories to be removed. Relative to [MountDirectory].
[string] $P11Paths.HostsConfig = "$($P11Paths.ConfigDirectory)\hosts.conf"; # Config file for DNS entries to be blocked by hosts file.
[string] $P11Paths.SysReqRegConfig = "$($P11Paths.RegistryConfigDirectory)\system-requirements.reg"; # System Requirement bypass registry entries.

# [string] $P11Paths. # Template for copy & paste <3

[hashtable] $P11Config = @{}; # Information loaded from the config files.
[array] $P11Config.AppxPackagesToRemove = @(); # List of AppXPackages to be removed.
[array] $P11Config.FeaturesToRemove = @(); # List of OptionalFeatures to be removed.
[array] $P11Config.CapabilitiesToRemove = @(); # List of Capabilities to be removed.
[array] $P11Config.PathsToRemove = @(); # List of Files and Directories to be removed. (Already prefixed with [MountDirectory])
[array] $P11Config.HostsToBlock = @(); # List of DNS entries to be blocked by hosts file.
[array] $P11Config.RegistryFiles = @(); # List of reg files. (Minus the one defined in [SysReqRegConfig])
[array] $P11Config.PostInstallScripts = @(); # List of scripts to be added to the image and setup to be executed when the user logs in for the first time.

#endregion

#region Helper Functions

function Write-Log {
    <#
        .SYNOPSIS
            Logging function.
        .PARAMETER Message
            Log message.
        .PARAMETER Function
            Parent funtion.
        .PARAMETER Severity
            Severity of the message.
    #>

    [CmdletBinding()] [OutputType([System.Void])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Log message.")]
        [ValidateNotNullOrEmpty()]
        [string] $Message,
 
        [Parameter(Mandatory = $false, HelpMessage = "Parent funtion.")]
        [ValidateNotNullOrEmpty()]
        [string] $Function,

        [Parameter(Mandatory = $false, HelpMessage = "Severity of the message.")]
        [ValidateNotNullOrEmpty()]
        [ValidateSet('Debug', 'Info', 'Warning', 'Error', 'General')]
        [string] $Severity = 'General'
    );

    
    switch ($Severity) {
        "Debug" { 
            [System.ConsoleColor] $messageColor = 'DarkMagenta';
        };
        "Info" { 
            [System.ConsoleColor] $messageColor = 'DarkGreen';
        };
        "Warning" { 
            [System.ConsoleColor] $messageColor = 'DarkYellow';
        };
        "Error" { 
            [System.ConsoleColor] $messageColor = 'DarkRed';
        };
        Default {
            [System.ConsoleColor] $messageColor = 'DarkGray';
        };
    };

    $logTime = [DateTime]::Now.ToString("yyyy-MM-dd HH:mm:ss");
    $logSeverity = $Severity.ToUpper();

    $logMessage = "[${logTime}]";
    $logMessage += "[${logSeverity}]";
    if (-not([string]::IsNullOrEmpty($Function))) { $logMessage += "[${Function}]"; };
    $logMessage += "${Message}";
    # Write-Host "[${logTime}][${logSeverity}]${Message}" -ForegroundColor $messageColor;
    Write-Host "${logMessage}" -ForegroundColor $messageColor;
};

function New-P11Directories {
    <#
        .SYNOPSIS
            Creates the directory layout needed for the script to work.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    New-Item -Path "$($P11Paths.LogDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.ConfigDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.RegistryConfigDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.IsoDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.WorkDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.IsoSourceDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.MountDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.ScratchDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.UpdatesDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    New-Item -Path "$($P11Paths.DriversDirectory)" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    Write-Log -Message "Pure11 directory structure created." -Severity Info;
};

function Test-P11RunAsSystem {
    <#
        .SYNOPSIS
            Validates if the script is running as NT AUTHORITY\SYSTEM.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    if ($(whoami) -ne "nt authority\system") {
        $errorMessage = "This script is designed to be executed as 'NT AUTHORITY\SYSTEM'!`n`a";
        $errorMessage += "You can do so by opening powershell through PsExec.`n";
        $errorMessage += "`tpsexec64.exe -nobanner -s -i powershell`n";
        $errorMessage += "and then running Pure11.ps1`n";
        Write-Log -Message "${errorMessage}" -Severity Error;
        throw "Permission error!";
    };
};

function Get-P11OscdimgExe {
    <#
        .SYNOPSIS
            Downloads oscdimg.exe from microsoft.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Invoke-WebRequest -Uri $P11Paths.OscdimgUrl -OutFile "$($P11Paths.OscdimgExe)";
    if ((Get-FileHash -Path "$($P11Paths.OscdimgExe)" -Algorithm SHA256).Hash -ne $P11Paths.OscdimgChecksum) {
        throw "oscdimg.exe is corrupt!";
    };
    Write-Log -Message "oscdimg.exe downloaded." -Severity Info;
};

function Test-P11OscdimgExe {
    <#
        .SYNOPSIS
            Validates the availability of oscdimg.exe.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    if (Test-Path -Path "$($P11Paths.OscdimgExe)") {
        Write-Log -Message "Local oscdimg.exe found: $($P11Paths.OscdimgExe)" -Severity Debug;
        if ((Get-FileHash -Path "$($P11Paths.OscdimgExe)" -Algorithm SHA256).Hash -ne $P11Paths.OscdimgChecksum) {
            throw "oscdimg.exe is corrupt!";
        };
        Write-Log -Message "Local oscdimg.exe hash matches! Yaay \o/" -Severity Debug;
    }
    else {
        Get-P11OscdimgExe;
    };
};

function Test-P11IsoSource {
    <#
        .SYNOPSIS
            Simple check to make sure the source is what it should be (:
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    if (-not(Test-Path -Path "$($P11Paths.InstallWim)")) { throw "Install.wim not found in $($P11Paths.IsoDirectory)"; };
    if (-not(Test-Path -Path "$($P11Paths.BootWim)")) { throw "Boot.wim not found in $($P11Paths.IsoDirectory)"; };
};

function Get-P11Config {
    <#
        .SYNOPSIS
            Helper function to load the config file contents. Not antipattern at all... ¯\_(ツ)_/¯
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Loading config..." -Severity Info;
    # Load AppX
    Get-Content -Path "$($P11Paths.AppxConfig)" | Where-Object { (-not $_.StartsWith('#')) -and (-not ([string]::IsNullOrEmpty($_))) } | ForEach-Object {
        $Script:P11Config.AppxPackagesToRemove += $_;
    }; 
    Write-Log -Message "Loaded $($P11Config.AppxPackagesToRemove.Count) Appx packages to remove." -Severity Debug;

    # Load Features
    Get-Content -Path "$($P11Paths.FeaturesConfig)" | Where-Object { (-not $_.StartsWith('#')) -and (-not ([string]::IsNullOrEmpty($_))) } | ForEach-Object {
        $Script:P11Config.FeaturesToRemove += $_;
    }; 
    Write-Log -Message "Loaded $($P11Config.FeaturesToRemove.Count) Features to remove." -Severity Debug;

    # Load Capabilities
    Get-Content -Path "$($P11Paths.CapabilitiesConfig)" | Where-Object { (-not $_.StartsWith('#')) -and (-not ([string]::IsNullOrEmpty($_))) } | ForEach-Object {
        $Script:P11Config.CapabilitiesToRemove += $_;
    }; 
    Write-Log -Message "Loaded $($P11Config.CapabilitiesToRemove.Count) Capabilities to remove." -Severity Debug;

    # Load Hosts
    Get-Content -Path "$($P11Paths.HostsConfig)" | Where-Object { (-not $_.StartsWith('#')) -and (-not ([string]::IsNullOrEmpty($_))) } | ForEach-Object {
        $Script:P11Config.HostsToBlock += $_;
    }; 
    Write-Log -Message "Loaded $($P11Config.HostsToBlock.Count) Hosts to block." -Severity Debug;

    # Load File & Folder paths
    Get-Content -Path "$($P11Paths.FilesConfig)" | Where-Object { (-not $_.StartsWith('#')) -and (-not ([string]::IsNullOrEmpty($_))) } | ForEach-Object {
        $Script:P11Config.PathsToRemove += "$($P11Paths.MountDirectory)\$($_)";
    }; 
    Write-Log -Message "Loaded $($P11Config.PathsToRemove.Count) filesystem paths to remove." -Severity Debug;

    # Load registry tweak files
    # Exclude the one which sets the system requirements.
    # Exclude the ones which uses a dash (-) as the first character in their name.
    Get-ChildItem -Path "$($P11Paths.RegistryConfigDirectory)" -Include "*.reg" -Recurse | Where-Object { ($_.FullName -ne "$($P11Paths.SysReqRegConfig)") -and (-not($_.Name.StartsWith('-'))) } | ForEach-Object {
        $Script:P11Config.RegistryFiles += "$($_.FullName)";
    };
    Write-Log -Message "Loaded $($P11Config.RegistryFiles.Count) registry files." -Severity Debug;

    # Load post install scripts
    Get-ChildItem -Path "$($P11Paths.PostInstallScriptsDirectory)" | Select-Object -Property Name, FullName | ForEach-Object {
        $P11Config.PostInstallScripts += $_;
    };
    Write-Log -Message "Loaded $($P11Config.PostInstallScripts.Count) post-install script(s)." -Severity Debug;
};

function Get-P11DismBaseArgs {
    <#
        .SYNOPSIS
            It generates the base splat object for dism stuff.
    #>
    [CmdletBinding()] [OutputType([hashtable])] 
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Adds the mount directory path.")]
        [switch] $WithPath,
        [Parameter(Mandatory = $false, HelpMessage = "Adds the install.wim image path.")]
        [switch] $InstallWim,
        [Parameter(Mandatory = $false, HelpMessage = "Adds the boot.wim image path.")]
        [switch] $BootWim
    );

    [hashtable] $dismArgs = @{
        ScratchDirectory = "$($P11Paths.ScratchDirectory)";
        LogPath          = "$($P11Paths.DismLogFile)";
        LogLevel         = "Warnings";
    };

    if ($WithPath.IsPresent) { 
        $dismArgs.Path = "$($P11Paths.MountDirectory)"; 
    };
    if ($InstallWim.IsPresent) {
        $dismArgs.ImagePath = "$($P11Paths.InstallWim)"; 
    }
    elseif ($BootWim.IsPresent) {
        $dismArgs.ImagePath = "$($P11Paths.BootWim)"; 
    };
    return $dismArgs;
};

function Mount-P11Wim {
    <#
        .SYNOPSIS
            Helper function to mount wim files.
    #>
    [CmdletBinding()] [OutputType([System.Void])] 
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Mounts install.wim.")]
        [switch] $InstallWim,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts boot.wim")]
        [switch] $BootWim
    );

    if ($InstallWim.IsPresent) {
        $MountWindowsImageArgs = Get-P11DismBaseArgs -InstallWim -WithPath;
        $MountWindowsImageArgs.Index = 1; # install.wim should only have 1 index left after (Remove-P11UnusedSku).
        $image = "install.wim"; # for logging
    }
    elseif ($BootWim.IsPresent) {
        $MountWindowsImageArgs = Get-P11DismBaseArgs -BootWim -WithPath;
        $MountWindowsImageArgs.Index = 2; # Index=2 is Windows Setup.
        $image = "boot.wim"; # for logging
    };
    Write-Log -Message "Mounting ${image}..." -Severity Info;
    Mount-WindowsImage @MountWindowsImageArgs | Out-Null;
};

function Dismount-P11Wim {
    <#
        .SYNOPSIS
            Helper function to dismount wim files.
    #>
    [CmdletBinding()] [OutputType([System.Void])] 
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Dismounts install.wim.")]
        [switch] $InstallWim
    );

    $image = "boot.wim"; # for logging
    $DismountWindowsImageArgs = Get-P11DismBaseArgs -WithPath;
    $DismountWindowsImageArgs.Save = $true;
    $DismountWindowsImageArgs.CheckIntegrity = $true;

    if ($InstallWim.IsPresent) {
        $image = "install.wim"; # for logging
        $RepairWindowsImageArgs = Get-P11DismBaseArgs -WithPath;
        $RepairWindowsImageArgs.LimitAccess = $true;
        $RepairWindowsImageArgs.StartComponentCleanup = $true;
        $RepairWindowsImageArgs.ResetBase = $true;
        Write-Log -Message "Clearing ${image}..." -Severity Info;
        Repair-WindowsImage @RepairWindowsImageArgs | Out-Null;        
    };

    Write-Log -Message "Dismounting ${image}..." -Severity Info;
    Dismount-WindowsImage @DismountWindowsImageArgs | Out-Null;
};

function Mount-P11RegistryHive {
    <#
        .SYNOPSIS
            Mounts registry hives.
    #>
    [CmdletBinding()] [OutputType([System.Void])] 
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Mounts all registry hives.")]
        [switch] $All,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts the COMPONENTS registry hive.")]
        [switch] $Components,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts the DEFAULT registry hive.")]
        [switch] $Default,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts the NTUSER registry hive.")]
        [switch] $NTUSER,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts the SOFTWARE registry hive.")]
        [switch] $Software,
        [Parameter(Mandatory = $false, HelpMessage = "Mounts the SYSTEM registry hive.")]
        [switch] $System
    );

    if ($All.IsPresent) {
        Write-Log -Message "Mounting all registry hives..." -Severity Debug;
        $(& "reg" "load" "HKLM\P11_COMPONENTS" "$($P11Paths.MountDirectory)\Windows\System32\config\COMPONENTS" 2>&1) | Out-Null;
        $(& "reg" "load" "HKLM\P11_DEFAULT" "$($P11Paths.MountDirectory)\Windows\System32\config\default" 2>&1) | Out-Null;
        $(& "reg" "load" "HKLM\P11_NTUSER" "$($P11Paths.MountDirectory)\Users\Default\ntuser.dat" 2>&1) | Out-Null;
        $(& "reg" "load" "HKLM\P11_SOFTWARE" "$($P11Paths.MountDirectory)\Windows\System32\config\SOFTWARE" 2>&1) | Out-Null;
        $(& "reg" "load" "HKLM\P11_SYSTEM" "$($P11Paths.MountDirectory)\Windows\System32\config\SYSTEM" 2>&1) | Out-Null;
    }
    else {
        if ($Components.IsPresent) { 
            Write-Log -Message "Mounting the COMPONENTS registry hive." -Severity Debug;
            $(& "reg" "load" "HKLM\P11_COMPONENTS" "$($P11Paths.MountDirectory)\Windows\System32\config\COMPONENTS" 2>&1) | Out-Null;
        };
        if ($Default.IsPresent) { 
            Write-Log -Message "Mounting the DEFAULT registry hive." -Severity Debug;
            $(& "reg" "load" "HKLM\P11_DEFAULT" "$($P11Paths.MountDirectory)\Windows\System32\config\default" 2>&1) | Out-Null;
        };
        if ($NTUSER.IsPresent) { 
            Write-Log -Message "Mounting the NTUSER registry hive." -Severity Debug;
            $(& "reg" "load" "HKLM\P11_NTUSER" "$($P11Paths.MountDirectory)\Users\Default\ntuser.dat" 2>&1) | Out-Null;
        };
        if ($Software.IsPresent) { 
            Write-Log -Message "Mounting the SOFTWARE registry hive." -Severity Debug;
            $(& "reg" "load" "HKLM\P11_SOFTWARE" "$($P11Paths.MountDirectory)\Windows\System32\config\SOFTWARE" 2>&1) | Out-Null;
        };
        if ($System.IsPresent) { 
            Write-Log -Message "Mounting the SYSTEM registry hive." -Severity Debug;
            $(& "reg" "load" "HKLM\P11_SYSTEM" "$($P11Paths.MountDirectory)\Windows\System32\config\SYSTEM" 2>&1) | Out-Null;
        };
    };
};

function Dismount-P11RegistryHives {
    <#
        .SYNOPSIS
            Dismounts registry hives.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Dismounting registry hives." -Severity Debug;
    $(& "reg" "unload" "HKLM\P11_COMPONENTS" 2>&1) | Out-Null;
    $(& "reg" "unload" "HKLM\P11_DEFAULT" 2>&1) | Out-Null;
    $(& "reg" "unload" "HKLM\P11_SOFTWARE" 2>&1) | Out-Null;
    $(& "reg" "unload" "HKLM\P11_SYSTEM" 2>&1) | Out-Null;
    $(& "reg" "unload" "HKLM\P11_NTUSER" 2>&1) | Out-Null;
};

function Add-P11HostsFileBlockEntry {
    <#
        .SYNOPSIS
            Creates entries in the hosts file to block the provided domain. Covers both ipv4 and ipv6.
        .LINK
            Proudly stolen from: 
                https://privacy.sexy/ 
                https://github.com/undergroundwires/privacy.sexy
    #>
    [CmdletBinding()] [OutputType([System.Void])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "DNS entry to be blocked.")]
        [string] $Domain
    );

    $hostsFilePath = "$($P11Paths.MountDirectory)\Windows\System32\drivers\etc\hosts";
    $comment = "Managed by Pure11";
    # $hostsFileEncoding = [Microsoft.PowerShell.Commands.FileSystemCmdletProviderEncoding]::Utf8;
    # $hostsFileEncoding = [System.Text.Encoding]::UTF8;
    $hostsFileEncoding = 'UTF8'; # idk which one hurts more, time zones or character encoding?!
    $blockingHostsEntries = @(;
        @{ AddressType = "IPv4";
            IPAddress  = '0.0.0.0';
        };
        @{ AddressType = "IPv6";
            IPAddress  = '::1';
        };
    );
    try {
        $isHostsFilePresent = Test-Path -Path "${hostsFilePath}" -PathType Leaf -ErrorAction Stop;
    }
    catch {
        Write-Log -Message "Failed to check hosts file existence. Error: $($_)`n$($_.ScriptStackTrace)" -Severity Error;
        return;
    };
    if (-not $isHostsFilePresent) {
        Write-Log -Message "Creating a new hosts file at ${hostsFilePath}." -Severity Debug;
        try {
            New-Item -Path $hostsFilePath -ItemType File -Force -ErrorAction Stop | Out-Null;
            Write-Host "Successfully created the hosts file." -ForegroundColor DarkBlue;
        }
        catch {
            Write-Log -Message "Failed to create the hosts file. Error: $($_)`n$($_.ScriptStackTrace)" -Severity Error;
            return;
        };
    };
    Write-Log -Message "Processing addition for '${Domain}' entry." -Severity Debug;
    foreach ($blockingEntry in $blockingHostsEntries) {
        try {
            $hostsFileContents = Get-Content -Path "${hostsFilePath}" -Raw -Encoding $hostsFileEncoding -ErrorAction Stop;
        }
        catch {
            Write-Log -Message "Failed to read the hosts file. Error: $($_)`n$($_.ScriptStackTrace)" -Severity Error;
            continue;
        };
        $hostsEntryLine = "$($blockingEntry.IPAddress)`t${Domain} $([char]35) ${comment}";
        if ((-not [String]::IsNullOrWhiteSpace($hostsFileContents)) -and ($hostsFileContents.Contains($hostsEntryLine))) {
            continue;
        };
        try {
            Add-Content -Path "${hostsFilePath}" -Value "${hostsEntryLine}" -Encoding $hostsFileEncoding -ErrorAction Stop;
        }
        catch {
            Write-Log -Message "Failed to add the entry. Error: $($_)`n$($_.ScriptStackTrace)" -Severity Error;
            continue;
        };
    }
};

function Get-P11WindowsImageInfo {
    <#
        .SYNOPSIS
            Retrieves image information from install.wim and stores it in [P11State].
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    $ArchString = @{ [UInt32]0 = 'x86'; [UInt32]5 = 'arm'; [UInt32]6 = 'ia64'; [UInt32]9 = 'amd64'; [UInt32]12 = 'arm64' };

    $GetWindowsImageArgs = Get-P11DismBaseArgs -InstallWim;
    $GetWindowsImageArgs.Index = 1;
    $imageInfo = (Get-WindowsImage @GetWindowsImageArgs | Select-Object -Property *);

    $Script:P11State.Language = ($imageInfo.Languages[0]);
    $Script:P11State.Edition = $imageInfo.EditionId;
    $Script:P11State.Architecture = $ArchString[$imageInfo.Architecture];
    $Script:P11State.Build = "$($imageInfo.Build).$($imageInfo.SPBuild)";

    Write-Log -Message "Selected Image is: $($P11State.ImageName)" -Severity Info;
    Write-Log -Message "Selected Image Language: $($P11State.Language)" -Severity Info;
    Write-Log -Message "Selected Image Edition: $($P11State.Edition)" -Severity Info;
    Write-Log -Message "Selected Image Architecture: $($P11State.Architecture)" -Severity Info;
    Write-Log -Message "Selected Image Build: $($P11State.Build)" -Severity Info;
};

function Copy-P11GuiRecursiveWithProgress {
    <#
        .SYNOPSIS 
            Gui (Windows Shell) progress window for file copy operations.
    #>
    [CmdletBinding()] [OutputType([System.Void])]
    param(
        [Parameter(Mandatory = $true, HelpMessage = "Source to copy from.")]
        [ValidateNotNullOrEmpty()]
        [string] $Path,
        [Parameter(Mandatory = $true, HelpMessage = "Destination to copy to.")]
        [ValidateNotNullOrEmpty()]
        [string] $Destination
    );

    if (Test-Path -Path "${Path}" -PathType Container) {
        $Path = "${Path}\*";
    };

    $fof_createprogressdlg = "&H0&";
    $shellApplication = New-Object -ComObject "Shell.Application";
    $destLocationFolder = $shellApplication.NameSpace($Destination);
    $destLocationFolder.CopyHere($Path, $fof_createprogressdlg);
};

function Get-P11GuiFileNameDialog {
    <#
        .SYNOPSIS
            Opens a gui file-picker dialog.
    #>
    [CmdletBinding()] [OutputType([string])]
    param(
        [Parameter(Mandatory = $false, HelpMessage = "Directory path to open the dialog in. Default: ScriptRoot.")]
        [string] $InitialDirectory = "${PSScriptRoot}",
        [Parameter(Mandatory = $false, HelpMessage = "File type filter string. Default: `"ISO (*.iso) | *.iso`"")]
        [string] $Filter = "ISO (*.iso) | *.iso"
    );

    if (($null -eq $InitialDirectory) -or ($InitialDirectory -eq "")) {
        $InitialDirectory = "${PSScriptRoot}"
    }

    $OpenFileDialog = New-Object System.Windows.Forms.OpenFileDialog;
    $OpenFileDialog.Title = "Please select a Windows installer iso."
    $OpenFileDialog.InitialDirectory = "${InitialDirectory}";
    $OpenFileDialog.Filter = "${Filter}";
    $dialogResult = $OpenFileDialog.ShowDialog();
    if ($dialogResult.ToString() -eq "Cancel") {
        return $null;
    }
    else {
        [string] $fullIsoPath = $OpenFileDialog.FileName;
        if (($null -eq $fullIsoPath) -or (-not($fullIsoPath.EndsWith(".iso"))) -or (-not(Test-Path -Path "${fullIsoPath}"))) {
            throw "Invalid ISO! '${fullIsoPath}'"
        };
        return $fullIsoPath;
    };
};

function Mount-P11WindowsIso {
    <#
        .SYNOPSIS
            Mounts the source ISO.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    $isoImage = (Get-DiskImage -ImagePath "$($P11State.IsoPath)");
    if (-not ($isoImage.Attached)) {
        Write-Log -Message "Mounting ISO `"$($P11State.IsoPath)`"" -Severity Debug;
        Mount-DiskImage -ImagePath "$($P11State.IsoPath)" -ErrorAction Stop | Out-Null;
    };

    $isoDrive = $(Get-WmiObject -Class Win32_LogicalDisk  -Filter "DriveType = 5" | Where-Object { $_.Size -eq $isoImage.Size }).DeviceID;
    $isoBootWim = "${isoDrive}\sources\boot.wim";
    # $isoBootWim = Join-Path -Path "${isoDrive}" -ChildPath "sources" -AdditionalChildPath "boot.wim";

    if (Test-Path -Path "${isoBootWim}" -PathType Leaf) {
        $script:P11State.IsoDrive = "${isoDrive}";
        Write-Log -Message "ISO mounted as drive $($P11State.IsoDrive)" -Severity Info;
    }
    else {
        throw "Invalid ISO ('${isoBootWim} not found') or Failed to mount!";
    };
};
function Dismount-P11WindowsIso {
    <#
        .SYNOPSIS
            Dismounts the source iso.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    $isoImage = (Get-DiskImage -ImagePath "$($P11State.IsoPath)");
    if ($isoImage.Attached) {
        Dismount-DiskImage -ImagePath "$($P11State.IsoPath)" -ErrorAction Stop | Out-Null;
        Write-Log -Message "Dismounted ISO from drive $($P11State.IsoDrive)" -Severity Info;
    };
};
#endregion

#region Low level BuildIso functions

function Add-P11HostsFileBlocks {
    <#
        .SYNOPSIS
            Populates the hosts file with goodies from .\config\hosts.conf
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Adding hosts file blocks..." -Severity Info;
    $P11Config.HostsToBlock | ForEach-Object {
        Add-P11HostsFileBlockEntry -Domain $_;
    };
};

function Remove-P11AppxProvisionedPackages {
    <#
        .SYNOPSIS
            Removes AppX packages defined in .\config\appx.conf (if they exists on the image)
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Removing AppX packages..." -Severity Info;

    $GetAppxProvisionedPackageArgs = Get-P11DismBaseArgs -WithPath;
    [array] $detectedAppxProvisionedPackages = (Get-AppxProvisionedPackage @GetAppxProvisionedPackageArgs | Select-Object -Property DisplayName, PackageName, PublisherId, InstallLocation);

    foreach ($detectedAppxProvisionedPackage in $detectedAppxProvisionedPackages) {
        Write-Log -Message "Detected AppX Package: $($detectedAppxProvisionedPackage.DisplayName)" -Severity Debug;
    };

    [array] $flaggedForRemoval = @();
    foreach ($detectedPackage in $detectedAppxProvisionedPackages) {
        foreach ($removablePackage in $P11Config.AppxPackagesToRemove) {
            if ($detectedPackage.DisplayName -contains $removablePackage) {
                $flaggedForRemoval += $detectedPackage;
            };
        };
    };

    foreach ($package in $flaggedForRemoval) {
        Write-Log -Message "Removing AppX package: $($package.DisplayName)" -Severity Debug;
        $RemoveAppxProvisionedPackageArgs = Get-P11DismBaseArgs -WithPath;
        $RemoveAppxProvisionedPackageArgs.PackageName = "$($package.PackageName)";
        $RemoveAppxProvisionedPackageArgs.ErrorAction = "Continue";
        Remove-AppxProvisionedPackage @RemoveAppxProvisionedPackageArgs | Out-Null;
    };

    Mount-P11RegistryHive -Software;
    foreach ($package in $flaggedForRemoval) {
        [string] $installPath = $package.InstallLocation.ToString();
        [string] $installPath = $installPath.Replace("%SYSTEMDRIVE%", "$($P11Paths.MountDirectory)");
        [string] $fullInstallPath = "$(([IO.FileInfo] $installPath).Directory.Parent.FullName)";
        Remove-Item -Path "${fullInstallPath}\*" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null;
        # Mark the package as Deprovisioned and EndOfLife to prevent reinstallation.
        $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\$($package.DisplayName)_$($package.PublisherId)" "/f" 2>&1) | Out-Null;
        # Adding this line breaks windows updates
        # $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\S-1-1-0\$($package.DisplayName)_$($package.PublisherId)" "/f" 2>&1) | Out-Null;
    };
    Dismount-P11RegistryHives;
};

function Disable-P11WindowsOptionalFeature {
    <#
        .SYNOPSIS
            Disables Optional Features defined in .\config\features.conf (if they exists on the image)
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Removing Optional Features..." -Severity Info;
    $GetWindowsOptionalFeatureArgs = Get-P11DismBaseArgs -WithPath;
    [array] $detectedOptionalFeatures = (Get-WindowsOptionalFeature @GetWindowsOptionalFeatureArgs | Where-Object { $_.State -eq 'Enabled' } | Select-Object -Property FeatureName).FeatureName;
    
    foreach ($feature in $detectedOptionalFeatures) {
        Write-Log -Message "Detected Optional Feature: ${feature}" -Severity Debug;
    };

    foreach ($feature in $detectedOptionalFeatures) {
        if ($P11Config.FeaturesToRemove -contains $feature) {

            $DisableWindowsOptionalFeatureArgs = Get-P11DismBaseArgs -WithPath;
            $DisableWindowsOptionalFeatureArgs.FeatureName = "${feature}";
            $DisableWindowsOptionalFeatureArgs.ErrorAction = "Continue";
            Write-Log -Message "Removing Feature: ${feature}" -Severity Debug;
            Disable-WindowsOptionalFeature @DisableWindowsOptionalFeatureArgs | Out-Null;
        };
    };
};

function Remove-P11WindowsCapability {
    <#
        .SYNOPSIS
            Removes Windows Capabilities defined in .\config\capabilities.conf (if they exists on the image)
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Removing Windows Capabilities..." -Severity Info;
    $GetWindowsCapabilityArgs = Get-P11DismBaseArgs -WithPath;
    $GetWindowsCapabilityArgs.LimitAccess = $true;
    [array] $detectedCapabilities = (Get-WindowsCapability @GetWindowsCapabilityArgs | Where-Object { $_.State -ne 'NotPresent' } | Select-Object -Property Name).Name;

    foreach ($detectedCapability in $detectedCapabilities) {
        Write-Log -Message "Detected Windows Capability: $($detectedCapability)" -Severity Debug;
    };

    foreach ($detectedCapability in $detectedCapabilities) {
        foreach ($removableCapability in $P11Config.CapabilitiesToRemove) {
            if ($detectedCapability -like "*${removableCapability}*") {
                $RemoveWindowsCapabilityArgs = Get-P11DismBaseArgs -WithPath;
                $RemoveWindowsCapabilityArgs.Name = "${detectedCapability}";
                Write-Log -Message "Removing Windows Capability: ${detectedCapability}" -Severity Debug;
                Remove-WindowsCapability @RemoveWindowsCapabilityArgs | Out-Null;
            };
        };
    };
};

function Remove-P11FileSystemBloat {
    <#
        .SYNOPSIS
            Removes Files and Folders defined in .\config\files.txt (if they exists on the image)
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Removing Files and Folders..." -Severity Info;
    foreach ($removablePath in $P11Config.PathsToRemove) {
        $resolvedPath = (Resolve-Path -Path "${removablePath}" -ErrorAction SilentlyContinue).Path;
        if ($null -ne $resolvedPath) {
            if ($resolvedPath.GetType().Name -eq "Array") {
                foreach ($path in $resolvedPath) {
                    if (Test-Path -Path "${path}" -PathType Container) {
                        Write-Log -Message "Removing Directory: ${path}" -Severity Debug;
                        Remove-Item -Path "${path}" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null;
                    }
                    elseif (Test-Path -Path "${path}" -PathType Leaf) {
                        Write-Log -Message "Removing File: ${path}" -Severity Debug;
                        Remove-Item -Path "${path}" -Force -ErrorAction SilentlyContinue | Out-Null;
                    };
                };
            }
            else {
                if (Test-Path -Path "${resolvedPath}" -PathType Container) {
                    Write-Log -Message "Removing Directory: ${resolvedPath}" -Severity Debug;
                    Remove-Item -Path "${resolvedPath}" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null;
                }
                elseif (Test-Path -Path "${resolvedPath}" -PathType Leaf) {
                    Write-Log -Message "Removing File: ${resolvedPath}" -Severity Debug;
                    Remove-Item -Path "${resolvedPath}" -Force -ErrorAction SilentlyContinue | Out-Null;
                };
            };
        };
    };
};

function Invoke-P11ManualTweaks {
    <#
        .SYNOPSIS
            Rigs certain stubborn software like: 
             - Edge
             - Microsoft.OutlookForWindows
             - Microsoft.Windows.DevHome
             - MicrosoftWindows.CrossDevice
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Deploying manual tweaking for certain apps..." -Severity Info;
    Mount-P11RegistryHive -Software;

    # Edge
    $edgeExeFolder = "$($P11Paths.MountDirectory)\Windows\SystemApps\Microsoft.MicrosoftEdge_8wekyb3d8bbwe";
    $edgeExePath = "${edgeExeFolder}\MicrosoftEdge.exe";
    New-Item -Path "${edgeExeFolder}" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;
    Set-Content -Path "${edgeExePath}" -Value "[Pure11] We don't appreciate Microsoft junk here!" -Force | Out-Null;    
    $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;
    # Adding this line breaks windows updates
    # $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\S-1-1-0\Microsoft.MicrosoftEdge_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;

    # Microsoft.OutlookForWindows
    $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.OutlookForWindows_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;
    # Adding this line breaks windows updates
    # $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\S-1-1-0\Microsoft.OutlookForWindows_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;

    # Microsoft.Windows.DevHome
    $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\Microsoft.Windows.DevHome_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;
    # Adding this line breaks windows updates
    # $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\S-1-1-0\Microsoft.Windows.DevHome_8wekyb3d8bbwe" "/f" 2>&1) | Out-Null;

    # MicrosoftWindows.CrossDevice
    $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\Deprovisioned\MicrosoftWindows.CrossDevice_cw5n1h2txyewy" "/f" 2>&1) | Out-Null;
    # Adding this line breaks windows updates
    # $(& "reg" "add" "HKLM\P11_SOFTWARE\Microsoft\Windows\CurrentVersion\Appx\AppxAllUserStore\EndOfLife\S-1-1-0\MicrosoftWindows.CrossDevice_cw5n1h2txyewy" "/f" 2>&1) | Out-Null;

    Dismount-P11RegistryHives;
};

function Invoke-P11BypassSystemRequirements {
    <#
        .SYNOPSIS 
            Bypassing Windows 11 System requirements.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Bypassing system requirements..." -Severity Info;
    Mount-P11RegistryHive -Default -NTUSER -System;
    $(& "reg" "import" "$($P11Paths.SysReqRegConfig)" 2>&1) | Out-Null;
    Dismount-P11RegistryHives;
};

function Invoke-P11RegistryTweaks {
    <#
        .SYNOPSIS 
            Imports registry tweaks defined in .\config\reg\*.reg
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Importing registry tweaks..." -Severity Info;
    Mount-P11RegistryHive -All;
    $P11Config.RegistryFiles | ForEach-Object {
        Write-Log -Message "Importing registry tweak: $($_)" -Severity Debug;
        $(& "reg" "import" "$($_)" 2>&1) | Out-Null;
    };
    Dismount-P11RegistryHives;
};

function Install-P11Drivers {
    <#
        .SYNOPSIS 
            Imports drivers placed to .\work\drivers
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Importing drivers..." -Severity Info;
    $AddWindowsDriverArgs = Get-P11DismBaseArgs -WithPath;
    $AddWindowsDriverArgs.Driver = "$($P11Paths.DriversDirectory)";
    $AddWindowsDriverArgs.Recurse = $true;
    Add-WindowsDriver @AddWindowsDriverArgs | Out-Null;
};

function Install-P11Updates {
    <#
        .SYNOPSIS 
            Imports windows updates placed to .\work\updates
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Importing windows updates..." -Severity Info;
    $AddWindowsPackageArgs = Get-P11DismBaseArgs -WithPath;
    $AddWindowsPackageArgs.PackagePath = "$($P11Paths.UpdatesDirectory)";
    $AddWindowsPackageArgs.IgnoreCheck = $true;
};

#endregion

#region High level BuildIso functions

function Copy-P11IsoToSourceCache {
    <#
        .SYNOPSIS
            Populates the [work\iso-source] directory with the install iso contents.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Caching ISO contents..." -Severity Info;
    Mount-P11WindowsIso;
    Copy-P11GuiRecursiveWithProgress -Path "$($P11State.IsoDrive)" -Destination "$($P11Paths.IsoSourceDirectory)";
    Dismount-P11WindowsIso;
    Write-Log -Message "ISO contents cached." -Severity Info;
};

function Select-P11WindowsIso {
    <#
        .SYNOPSIS
            Prompts the user to pick a source ISO.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    $selectedIso = Get-P11GuiFileNameDialog -InitialDirectory "$($Env:P11_ISOPATH)";
    
    if ($null -eq $selectedIso) {
        throw "No ISO selected!";
    };
    if (-not(Test-Path -Path "${selectedIso}" -PathType Leaf)) {
        throw "Source ISO not found!";
    };

    $Env:P11_ISOPATH = (Get-Item -Path "${selectedIso}").Directory.FullName;
    $Script:P11State.IsoPath = "${selectedIso}";

    Write-Log -Message "Selected source ISO: $($P11State.IsoPath)" -Severity Info;
};

function Select-P11Sku {
    <#
        .SYNOPSIS
            Reads the available images from install.wim and prompts the user to pick one.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    
    Write-Log -Message "Loading available SKU images..." -Severity Info;

    [hashtable] $GetWindowsImageArgs = Get-P11DismBaseArgs -InstallWim;
    [array] $detectedWindowsImages = (Get-WindowsImage @GetWindowsImageArgs | Select-Object -Property ImageName).ImageName;
    $Script:P11State.DetectedWindowsImages = $detectedWindowsImages;

    if ($P11State.ImageName -eq [string]::Empty) {
        Write-Host "";
        $index = 0;
        foreach ($image in $detectedWindowsImages) {
            Write-Host "[${index}] ${image}" -ForegroundColor DarkBlue;
            $index ++;
        };
        Write-Host "";
        if ($($index - 1) -ge 1) {
            [int] $selectedImageIndex = [int](Read-Host "Please select the SKU (0-$($index-1)) to customize");
        }
        else {
            [int] $selectedImageIndex = 0;
        };
        [string] $Script:P11State.ImageName = $detectedWindowsImages[$selectedImageIndex];
    };

    Write-Log -Message "Selected Image is: $($P11State.ImageName)" -Severity Info;
};

function Remove-P11UnusedSku {
    <#
        .SYNOPSIS
            Removes all SKU from install.wim with the exception of the selected one from (Select-P11Sku).
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    if ($P11State.DetectedWindowsImages.Count -gt 1) {
        Write-Log -Message "Removing unused SKU images..." -Severity Info;
        foreach ($image in ($P11State.DetectedWindowsImages | Where-Object { $_ -ne "Windows 11 Enterprise" })) {
            Write-Log -Message "Removing SKU: ${image}" -Severity Debug;
    
            $RemoveWindowsImageArgs = Get-P11DismBaseArgs -InstallWim;
            $RemoveWindowsImageArgs.Name = "${image}";
            Remove-WindowsImage @RemoveWindowsImageArgs | Out-Null;
        };
    };

    Get-P11WindowsImageInfo;
};

function Deploy-P11AutounattendXml {
    <#
        .SYNOPSIS
            Copies the autounattend.xml to the iso root.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Deploying autounattend.xml..." -Severity Info;
    $localizedAutounattendXml = "$($P11Paths.ConfigDirectory)\autounattend.$($P11State.Language).xml";
    if (Test-Path -Path "${localizedAutounattendXml}") {
        Write-Log -Message "Using Localized autounattend.$($P11State.Language).xml..." -Severity Info;
        Copy-Item -Path "${localizedAutounattendXml}" -Destination "$($P11Paths.AutounattendXmlIso)" -Force -ErrorAction SilentlyContinue | Out-Null;
    }
    else {
        Copy-Item -Path "$($P11Paths.AutounattendXml)" -Destination "$($P11Paths.AutounattendXmlIso)" -Force -ErrorAction SilentlyContinue | Out-Null;
    };
};

function Deploy-P11PostInstallScripts {
    <#
        .SYNOPSIS
            Copies the post install scripts into the image.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();

    Write-Log -Message "Deploying post install scripts..." -Severity Info;
    $setupDirectory = "$($P11Paths.MountDirectory)\Windows\Setup\Scripts";
    New-Item -Path "${setupDirectory}" -ItemType Directory -Force -ErrorAction SilentlyContinue | Out-Null;

    Mount-P11RegistryHive -NTUSER;
    [int] $scriptIndex = 0;
    $P11Config.PostInstallScripts | ForEach-Object {
        Copy-Item -Path "$($_.FullName)" -Destination "${setupDirectory}\$($_.Name)" -Force -ErrorAction SilentlyContinue | Out-Null;
        $(& "reg" "add" "HKLM\P11_NTUSER\Software\Microsoft\Windows\CurrentVersion\RunOnce" "/v" "Pure11-PostInstall-${scriptIndex}" "/t" "REG_SZ" "/d" "start c:\Windows\Setup\Scripts\$($_.Name)" "/f" 2>&1) | Out-Null;
        Write-Log -Message "Deployed post install script: $($_.Name)" -Severity Debug;
        $scriptIndex += 1;
    };
    Dismount-P11RegistryHives;
};

function Invoke-P11InstallWimActions {
    <#
        .SYNOPSIS 
            Applies the customization steps to install.wim.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Customizing install.wim..." -Severity Info;
    Mount-P11Wim -InstallWim;
    Add-P11HostsFileBlocks;
    Install-P11Drivers;
    Install-P11Updates;
    Deploy-P11PostInstallScripts;
    Remove-P11AppxProvisionedPackages;
    Disable-P11WindowsOptionalFeature;
    Remove-P11WindowsCapability;
    Remove-P11FileSystemBloat;
    Invoke-P11ManualTweaks;
    Invoke-P11BypassSystemRequirements;
    Invoke-P11RegistryTweaks;
    Dismount-P11Wim -InstallWim;
    Write-Log -Message "install.wim customization finished." -Severity Info;
};

function Invoke-P11BootWimActions {
    <#
        .SYNOPSIS 
            Applies the customization steps to install.wim.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Customizing boot.wim..." -Severity Info;
    Mount-P11Wim -BootWim;
    Invoke-P11BypassSystemRequirements;
    Install-P11Drivers;
    Dismount-P11Wim;
    Write-Log -Message "boot.wim customization finished." -Severity Info;
};

function New-P11Iso {
    <#
        .SYNOPSIS 
            Builds the Pure11 iso.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    Write-Log -Message "Building Pure11 iso..." -Severity Info;
    $outputIso = "$($P11Paths.IsoDirectory)\Pure11-$($P11State.Edition)-$($P11State.Language)-$($P11State.Build)-$($P11State.Architecture)-${P11DateTime}.iso";
    $etfsboot = "$($P11Paths.IsoSourceDirectory)\boot\etfsboot.com";
    $efisys = "$($P11Paths.IsoSourceDirectory)\efi\microsoft\boot\efisys.bin";

    $(& "$($P11Paths.OscdimgExe)" "-m" "-o" "-u2" "-udfver102" "-bootdata:2#p0,e,b${etfsboot}#pEF,e,b${efisys}" "$($P11Paths.IsoSourceDirectory)" "${outputIso}") | Out-Null;
    if ($?) {
        Write-Log -Message "Built Pure11 ISO: ${outputIso}" -Severity Info;
    }
    else {
        throw "Pure11 ISO build failed.";
    };
};

#endregion

#region WorkFlow functions
function Build-P11Iso {
    <#
        .SYNOPSIS
            ISO build mode.
    #>
    [CmdletBinding()] [OutputType([System.Void])] param();
    [DateTime] $P11StartTime = [DateTime]::Now;
    $Host.UI.RawUI.WindowTitle = "[Pure11] Iso builder";
    Clear-Host;
    Start-Transcript -Path "$($P11Paths.ScriptLogFile)";
    try {
        Test-P11RunAsSystem;
        New-P11Directories;
        Test-P11OscdimgExe;
        Get-P11Config;

        Select-P11WindowsIso;
        Copy-P11IsoToSourceCache;
        Test-P11IsoSource;        

        Select-P11Sku;
        Remove-P11UnusedSku;
        Deploy-P11AutounattendXml;

        Invoke-P11InstallWimActions;
        Invoke-P11BootWimActions;
        New-P11Iso;
    }
    catch {
        Write-Log -Message "$($_)`n$($_.ScriptStackTrace)" -Severity Error;
    }
    finally {
        Write-Log -Message "Running some cleanup... finally." -Severity Debug; # pun intended
        try { Dismount-P11WindowsIso | Out-Null; } catch {};
        try { $(& "reg" "unload" "HKLM\P11_COMPONENTS" 2>&1) | Out-Null; } catch {};
        try { $(& "reg" "unload" "HKLM\P11_DEFAULT" 2>&1) | Out-Null; } catch {};
        try { $(& "reg" "unload" "HKLM\P11_SOFTWARE" 2>&1) | Out-Null; } catch {};
        try { $(& "reg" "unload" "HKLM\P11_SYSTEM" 2>&1) | Out-Null; } catch {};
        try { $(& "reg" "unload" "HKLM\P11_NTUSER" 2>&1) | Out-Null; } catch {};
        try { Get-windowsImage -Mounted | Dismount-WindowsImage -Discard | Out-Null; } catch {};
        try { Clear-WindowsCorruptMountPoint | Out-Null; } catch {};
        try { $(& "dism" "/cleanup-wim" 2>&1) | Out-Null; } catch {};
        try { Remove-Item -Path "$($P11Paths.MountDirectory)" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null; } catch {};
        try { Remove-Item -Path "$($P11Paths.ScratchDirectory)" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null; } catch {};
        try { Remove-Item -Path "$($P11Paths.IsoSourceDirectory)" -Recurse -Force -ErrorAction SilentlyContinue | Out-Null; } catch {};
    };
    [TimeSpan] $P11ElapsedTime = ([DateTime]::Now) - $P11StartTime;
    [string] $P11TotalTime = "{0:HH:mm:ss}" -f ([DateTime] $P11ElapsedTime.Ticks);
    Write-Log -Message "Pure11 Iso builder finished ${P11TotalTime}" -Severity Info;
    Stop-Transcript;
};

#endregion

#region Script Main
if ($Init.IsPresent) {
    New-P11Directories; 
}
elseif ($BuildIso.IsPresent) {
    Build-P11Iso; 
}
else {
    Write-Log -Message "Missing parameter!" -Severity Warning;
    Get-Help "${PSScriptRoot}\Pure11.ps1";
};
#endregion
