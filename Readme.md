# Pure 11 🪟
![Pure11 meme](./.github/pure.png)

Windows 11 arrives loaded with more than just an operating system—there's also bloatware, relentless telemetry, and a host of so-called 'features' designed to serve everyone except the end user.

Pure11 cuts through the nonsense, providing a streamlined, privacy-focused, and highly efficient version of the operating system.

This PowerShell script strips away the bloatware, removes ads, disables intrusive features, and performs essential system hardening, delivering a clean, secure, and responsive Windows 11 installation.

Pure11 is for those who prefer an OS that works for them, not the other way around.


## What is removed / changed / disabled

<details>

- **Microsoft Edge**
    
    It is purged with fire. <3

- **OneDrive**

    With a caveat: you need the post install script to get rid of it completely. It is a very persistent little worm and keeps crawling back. But after the Post install script ran, it is gone forever.

- **Telemetry**

    It's staggering how much telemetry is sewed into the fabric of Windows 11. 
    I highly doubt all of them is disabled, but the wast majority of them should be covered by Pure 11.

- **AppX Packages**

    For the latest list please check the contents of [./config/appx.conf](#)

    <details>

    ```
    ActiproSoftwareLLC
    AdobePhotoshopExpress
    CandyCrushSaga
    CandyCrushSodaSaga
    Clipchamp.Clipchamp
    Duolingo
    EclipseManager
    Flipboard.Flipboard
    iHeartRadio
    Microsoft.3DBuilder
    Microsoft.549981C3F5F10
    Microsoft.AccountsControl
    Microsoft.AsyncTextService
    Microsoft.BingFinance
    Microsoft.BingNews
    Microsoft.BingSports
    Microsoft.BingWeather
    Microsoft.CommsPhone
    Microsoft.Copilot
    Microsoft.GamingApp
    Microsoft.GetHelp
    Microsoft.Getstarted
    Microsoft.GroupMe10
    Microsoft.Messaging
    Microsoft.Microsoft3DViewer
    Microsoft.MicrosoftEdge
    Microsoft.MicrosoftEdge.Stable
    Microsoft.MicrosoftEdgeDevToolsClient
    Microsoft.MicrosoftOfficeHub
    Microsoft.MicrosoftSolitaireCollection
    Microsoft.MicrosoftStickyNotes
    Microsoft.MinecraftUWP
    Microsoft.MixedReality.Portal
    Microsoft.MSPaint
    Microsoft.NetworkSpeedTest
    Microsoft.Office.OneNote
    Microsoft.Office.Sway
    Microsoft.OneConnect
    Microsoft.OutlookForWindows
    Microsoft.Paint
    Microsoft.People
    Microsoft.PowerAutomateDesktop
    Microsoft.Print3D
    Microsoft.ScreenSketch
    Microsoft.SkypeApp
    Microsoft.StorePurchaseApp
    Microsoft.Todos
    Microsoft.Wallet
    Microsoft.Windows.CallingShellApp
    Microsoft.Windows.DevHome
    Microsoft.Windows.Holographic.FirstRun
    Microsoft.Windows.PeopleExperienceHost
    Microsoft.Windows.Photos
    Microsoft.WindowsAlarms
    Microsoft.WindowsCamera
    microsoft.windowscommunicationsapps
    Microsoft.WindowsFeedback
    Microsoft.WindowsFeedbackHub
    Microsoft.WindowsMaps
    Microsoft.WindowsPhone
    Microsoft.WindowsSoundRecorder
    Microsoft.WindowsStore
    Microsoft.Xbox.TCUI
    Microsoft.XboxApp
    Microsoft.XboxGameCallableUI
    Microsoft.XboxGameOverlay
    Microsoft.XboxGamingOverlay
    Microsoft.XboxIdentityProvider
    Microsoft.XboxSpeechToTextOverlay
    Microsoft.YourPhone
    Microsoft.ZuneMusic
    Microsoft.ZuneVideo
    MicrosoftCorporationII.QuickAssist
    MicrosoftWindows.Client.WebExperience
    MicrosoftWindows.CrossDevice
    PandoraMediaInc
    Shazam
    Spotify
    Twitter
    Windows.ContactSupport
    Windows.Print3D
    ```
    </details>

- **Windows Capabilities**

    For the latest list please check the contents of [./config/capabilities.conf](#)

    <details>

    ```
    Accessibility.Braille
    Analog.Holographic.Desktop
    App.StepsRecorder
    Browser.InternetExplorer
    Language.Handwriting
    Language.OCR
    Language.Speech
    Language.TextToSpeech
    MathRecognizer
    Media.WindowsMediaPlayer
    Microsoft.Wallpapers.Extended
    Microsoft.Windows.WordPad
    OneCoreUAP.OneSync
    Windows.Desktop.EMS-SAC.Tools
    ```
    </details>

- **Optional Windows Features**

    For the latest list please check the contents of [./config/capabilities.conf](#)

    <details>

    ```
    Internet-Explorer-Optional-amd64
    Internet-Explorer-Optional-x64
    Internet-Explorer-Optional-x84
    MediaPlayback
    MicrosoftWindowsPowerShellV2
    MicrosoftWindowsPowerShellV2Root
    RasCMAK.Client
    RIP.Listener
    SMB1Protocol
    SMB1Protocol-Client
    SMB1Protocol-Server
    SmbDirect
    SNMP.Client
    TelnetClient
    TFTP
    WCF-TCP-PortSharing45
    WindowsMediaPlayer
    WMI-SNMP-Provider.Client
    WorkFolders-Client                  
    ```
    </details>

- **And a whole heap of other stuff through registry and filesystem changes**

    Please check the contents of the `./config` folder to review what changes are implemented.

</details>

## What is **NOT** removed and hence kept in a fully functional state.

<details>

 - **Windows Updates**
    
    I'm not a savage. Despite it's annoying tendency to introduce junk noone asked for, having patches for 0-days and other nasty bugs are far outweights it's downsides and shortcomings.

 - **Windows Defender**

    Well, maybe i'm a savage after all... I spent like two weeks trying to strip this out from the system in a way which doesn't undermines stability (and windows updates). 
    But it is not possible without breaking things which otherwise useful.

    If you are under age ~45 just keep your system up-to-date and don't do stupid stuff, Defender will provide sufficient protection.
    
    If you are over ~45, please purchase a strong AV engine from a reputable vendor and keep your system updated.

    I don't mean to offend anyone, but statistics and experience never lies...

    If you are looking for a good AV to purchase i recommend to check out this youtube channel:
    [The PC Security Channel](https://www.youtube.com/@pcsecuritychannel) (Note: He will not tell you what to buy, but his videos will provide you the knowledge to be able to form and educated decision for your usecase/situation)

</details>

## Prerequisites

<details>

- Windows 11 Install ISO - [Download Windows 11 - Microsoft](https://www.microsoft.com/software-download/windows11) or [MSDN](https://my.visualstudio.com/)
- PsExec - [PsExec - Sysinternals | Microsoft Learn](https://learn.microsoft.com/sysinternals/downloads/psexec)

- PowerShell - The versions below are just for reference, if yours somewhere in the ballpark, then you should be fine.

    <details>

    ```powershell
    # for Windows PowerShell
    # $PSVersionTable 

    Name                           Value
    ----                           -----
    PSVersion                      5.1.22621.4111
    PSEdition                      Desktop
    PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0...}
    BuildVersion                   10.0.22621.4111
    CLRVersion                     4.0.30319.42000
    WSManStackVersion              3.0
    PSRemotingProtocolVersion      2.3
    SerializationVersion           1.1.0.1

    # or for pwsh
    # $PSVersionTable

    Name                           Value
    ----                           -----
    PSVersion                      7.4.5
    PSEdition                      Core
    GitCommitId                    7.4.5
    OS                             Microsoft Windows 10.0.22631
    Platform                       Win32NT
    PSCompatibleVersions           {1.0, 2.0, 3.0, 4.0…}
    PSRemotingProtocolVersion      2.3
    SerializationVersion           1.1.0.1
    WSManStackVersion              3.0
    ```

    </details>


- Make sure you can run powershell scripts:
    ```powershell
    Set-ExecutionPolicy Bypass -Scope CurrentUser -Force; # for the current user
    # or
    Set-ExecutionPolicy Bypass -Scope LocalMachine -Force; # for the current machine
    ```

</details>

## Configuration

<details>

The script can be configured using the various files in the `./config` folder (and in the `./work` folder, see below).

- 📄 **config/appx.conf**

        List of AppX packages to be removed.
        Lines starting with '#' character interpreted as comments and will be ignored.

- 📄 **config/autounattend.xml**

    Allows customization of the Setup process (among other things)

    Pure11 will try to load one which is matching with the detected language of the OS. 
    
    Allowing the option to create customized ISOs for different languages using the same "purification" process.

        Image language: en-US
            autounattend.en-US.xml will be used (if present)

        Image language: hu-HU
            autounattend.hu-HU.xml will be used (if present)

        if no language specific autounattend.xml is found then it just uses the generic one.

    Read more: 

    [Answer files (unattend.xml)](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/update-windows-settings-and-scripts-create-your-own-answer-file-sxs?view=windows-11)
    
    [schneegans Generate autounattend.xml files for Windows 10/11
](https://schneegans.de/windows/unattend-generator/)



- 📄 **config/capabilities.conf**

        List of Windows Capabilities to be removed.
        Lines starting with '#' character interpreted as comments and will be ignored.

- 📄 **config/features.conf**

        List of Windows Optional Features to be disabled.
        Lines starting with '#' character interpreted as comments and will be ignored.

- 📄 **config/files.txt**

        List of file paths to be deleted.
        They are relative to the mount folder.
        Lines starting with '#' character interpreted as comments and will be ignored.

- 📄 **config/hosts.conf**
    
    [DNS sinkhole Wikipedia](https://en.wikipedia.org/wiki/DNS_sinkhole)

        List of DNS entries to be sinkholed using the hosts file.
        Lines starting with '#' character interpreted as comments and will be ignored.

- 📂 **config/post-install**

    Scripts in this directory will be added to be executed when a user logs in for the first time.

    Post installation they can be found in `c:\Windows\Setup\Scripts` you may need to run them manually (as admin) to make them truly work.

    Note: Todo to investigate why they only executed *'partially'*.

- 📂 **config/reg**

    *.reg files to implement registry changes. File whose name is starting with `-` will be ignored.

    Note: *At present the stuff in the reg files is a mess, i need to come up with a structure to organise them better.*
    
    The registry paths have to match with the mounted hives:

    | Pure11 Hive Path    | Deployed OS Registry Path | Description |
    | -------- | ------- | ------- |
    | HKLM\P11_COMPONENTS  | HKEY_LOCAL_MACHINE\SYSTEM\CurrentControlSet\Components    | Device drivers, services, and other system elements |
    | HKLM\P11_DEFAULT | HKEY_USERS.DEFAULT | User hive of the NT Authority\SYSTEM account |
    | HKLM\P11_SOFTWARE    | HKEY_LOCAL_MACHINE\Software | Settings for installed software and Windows System itself |
    | HKLM\P11_SYSTEM    | HKEY_LOCAL_MACHINE\SYSTEM | Settings and configuration data for the operating system |
    | HKLM\P11_NTUSER    | HKEY_CURRENT_USER | User-specific registry data, will be applied to new users |


- 📂 **work/updates**

    Place windows update `*.cab` and `*.msu` files in this directory and they will be added to the image.
    Recursive, subfolders allowed.

- 📂 **work/drivers**

    Place device drivers in this directory and they will be added to the image. Recursive, subfolders allowed.
    


</details>

## Usage

<details>

1. Download the repo

2. Open powershell as admin and cd into the directory where you have the Pure11.ps1 script

3. Run the script with the -Init flag to create the required directory structure
    ```powershell
    .\Pure11.ps1 -Init
    ```

4. Use PsExec to open another powershell window as SYSTEM
    ```powershell
    psexec64.exe -nobanner -s -i powershell # for Windows powershell
    # or
    psexec64.exe -nobanner -s -i pwsh # for pwsh
    ```

5. In the freshly opened powershell window, cd into the directory where you have the Pure11.ps1 script
    ```powershell
    .\Pure11.ps1 -BuildIso
    ```

6. A file picker window will open to select your windows iso. 

    **Note:** *A notice window will also complain about not being able to find the desktop folder, that is normal and just click "Ok". SYSTEM does not have a desktop folder.*

7. In the powershell window the script will list the available SKUs (installable images / editions). Pick the one you want to proceed with.

8. The finished ISO will be placed into the iso directory right next to the script.

</details>

## Remarks / Resources

## Disclaimer

    This program is provided "as is" without warranty of any kind.
    The developer takes no responsibility for any damages, data loss, or other issues that may arise from the use of this program.
    
    Use at your own risk. 
    
    Always back up your data before making any modifications.
    Testing in virtual machines are encouraged.

## License

[MIT License](./LICENSE)
 
