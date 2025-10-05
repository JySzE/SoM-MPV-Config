<div align="center">
  <img width="128" height="128" alt="9da9e0c1c699ec1d6fb12e044c74b2ef" src="https://github.com/user-attachments/assets/c639a895-0bcd-467f-80dc-24331c8c753a" />
</div>

# **SoM MPV Config Info**
SoM MPV is a preconfigured MPV bundle of lua scripts and config files etc, which can be used in a portable or installed manner.

It is not meant to be the perfect configuration, there is no such thing.

This repo is made for hosting of said files and to offer a place to submit issues and pull requests for any improvements you may offer.

## **Quick Summary of Features:**
- Custom font for subtitles with no declared fonts (e.g., .srt files)
- Better video scaling
- Improved screenshot naming
- Auto Profiles
- And more

SoM MPV Config is designed as a gateway/baseline for new users to get a high quality experience right away, or for users who just want something that works well without experimenting.

*Note: We encourage everyone who downloads it to experiment with settings, key binds, and customization.  
Refer to the MPV manual for changing specific settings.*
## **Important Notes:**
- **HDR Passthrough:** This config does NOT enable HDR passthrough.  
  It is strictly for HDR/DV → SDR tonemapping.  
## **SoM MPV Config is only available for:**
- Windows
## **Unsupported systems:**
- macOS
- Windows ARM CPUs
- Intel-based macOS
- Linux
- ChromeOS
# **SoM MPV Download**

## **Option 1: PowerShell (Recommended)**
1. Turn off your VPN to avoid Cloudflare bot protection
2. Open Powershell and [change your current directory](https://powershellfaqs.com/change-directory-in-powershell/) to a user folder
3. Run: `irm https://tinyurl.com/sommpv | iex`
4. Choose your setup method:
   - **Portable Mode** (SoM_MPV_Builder):
     - Must be in a non protected folders like  `Documents`, `Downloads`, `Desktop`, etc
     - Will not work in `Program Files` or other protected folders
   - **Installer Mode** (SoM_MPV_Installer):
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
   - **Uninstaller Mode** (SoM_MPV_Uninstaller):
     - Removes existing SoM MPV installation, no affect on portable

*If you have issues, try disabling Anti-Virus first before asking for help.*
*If you use a PowerShell profile and encounter an error, try running PowerShell from `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` instead.*

## **Option 2: Batch File**
1. Turn off your VPN to avoid Cloudflare bot protection
2. Download one of the following bat files:
   - **Portable Mode** [[SoM_MPV_Builder.bat](https://gist.githubusercontent.com/JySzE/0d6417c84deceda8326e38804d31015b/raw/SoM_MPV_Builder.bat)]:
     - Must be in a non protected folders like  `Documents`, `Downloads`, `Desktop`, etc 
     - Will not work in `Program Files` or other protected folders
   - **Installer Mode** [[SoM_MPV_Installer.bat](https://gist.githubusercontent.com/JySzE/07e04bc5f01c5d30850a494e7297db42/raw/SoM_MPV_Installer.bat)]:
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
   - **Uninstaller Mode** [[SoM_MPV_Uninstaller.bat](https://gist.githubusercontent.com/JySzE/9f99789bc42710fba2fde19f8255b292/raw/SoM_MPV_Uninstaller.bat)]:
     - Removes existing SoM MPV installation, no affect on portable
3. Press CTRL + S on the download page, set "Save as type" to `All Files (*.*)` to save as .bat
5. [Run the bat and enjoy](https://pastebin.com/raw/hTZP2hi1)

*Restrictions apply. Option 1 recommended for most users.*

## **MPV Build Guide (macOS Apple Silicon)**
- [Guide](https://gist.github.com/JySzE/d25c7b7abf1b689739d51a6a6a6e0e29)
- *No longer maintained, Fork and fix if needed. Do not ask for support.*
