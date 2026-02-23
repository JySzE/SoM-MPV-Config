<div align="center">
  <img width="128" height="128" alt="9da9e0c1c699ec1d6fb12e044c74b2ef" src="https://github.com/user-attachments/assets/c639a895-0bcd-467f-80dc-24331c8c753a" />
</div>

# **SoM MPV Config Info**
SoM MPV is a preconfigured, MPV bundle that includes lua scripts, configuration files, and supporting utilities such as OptiPNG. It can be used as a portable bundle or installed.

The config is designed as a polished baseline for users who want excellent video quality, proper SDR colors and HDR tone mapping, 
smooth playback and useful interface enhancements without manual tweaking. It works out of the box while adapting to different content, colorspaces, and hardware.

It is not meant to be the perfect configuration; there is no such thing.

This repository hosts the files and provides a place to submit issues or pull requests for improvements.

## **Quick Summary of Features:**

- High quality [GPU Next](https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU) video scaling
- SDR colorspace auto profiles for consistent and proper playback using GPU Next
- HDR & Dolby Vision to SDR auto tone mapping profiles
- Custom subtitle styling for files without embedded fonts (e.g., .srt)
- Auto profiles for scaling control and weaker hardware
- Improved screenshot output with detailed naming and correct colors
- Built in right click context menu
- Minor UI changes

*Note: We encourage everyone who downloads it to experiment with settings, key binds, and customization.  
Refer to the MPV manual for changing specific settings.*
## **Important Notes:**
- **HDR Passthrough:** This config does NOT enable HDR passthrough. It is strictly for HDR & Dolby Vision to SDR tonemapping.  
### **SoM MPV Config is only available for:**
- Windows
### **Unsupported systems:**
- macOS
- Windows ARM CPUs
- Intel based macOS
- Linux
- ChromeOS
# **SoM MPV Download**

## **Option 1: PowerShell (Recommended)**
1. Turn off your VPN to avoid Cloudflare bot protection
2. Open Powershell and [change your current directory](https://powershellfaqs.com/change-directory-in-powershell/) to a user folder
3. Run: `irm https://tinyurl.com/sommpv | iex`
4. Choose your setup method:
   - **Portable Mode** (SoM_MPV_Builder):
     - Must be in a non protected folders such as  `Documents`, `Downloads`, `Desktop`, etc
     - Will not work in `Program Files` or other protected folders
   - **Installer Mode** (SoM_MPV_Installer):
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
   - **Uninstaller Mode** (SoM_MPV_Uninstaller):
     - Removes existing SoM MPV installation, does not affect portable

*If you have issues, try disabling Anti-Virus first before asking for help.*
*If you use a PowerShell profile and encounter an error, try running PowerShell from `%SystemRoot%\System32\WindowsPowerShell\v1.0\powershell.exe` instead.*

## **Option 2: Batch File**
1. Turn off your VPN to avoid Cloudflare bot protection
2. Download one of the following bat files:
   - **Portable Mode** [[SoM_MPV_Builder.bat](https://gist.githubusercontent.com/JySzE/0d6417c84deceda8326e38804d31015b/raw/SoM_MPV_Builder.bat)]:
     - Must be placed in a non protected folders such as  `Documents`, `Downloads`, `Desktop`, etc 
     - Will not work in `Program Files` or other protected folders
   - **Installer Mode** [[SoM_MPV_Installer.bat](https://gist.githubusercontent.com/JySzE/07e04bc5f01c5d30850a494e7297db42/raw/SoM_MPV_Installer.bat)]:
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
   - **Uninstaller Mode** [[SoM_MPV_Uninstaller.bat](https://gist.githubusercontent.com/JySzE/9f99789bc42710fba2fde19f8255b292/raw/SoM_MPV_Uninstaller.bat)]:
     - Removes existing SoM MPV installation, does not affect portable
3. Press CTRL + S on the download page, set "Save as type" to `All Files (*.*)` to save as .bat
5. [Run the bat and enjoy](https://pastebin.com/raw/hTZP2hi1)

*Restrictions apply. Option 1 recommended for most users.*

## **MPV Build Guide (macOS Apple Silicon)**
- [Guide](https://gist.github.com/JySzE/d25c7b7abf1b689739d51a6a6a6e0e29)
- *No longer maintained, Fork and fix if needed. Do not ask for support.*
