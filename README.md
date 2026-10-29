<div align="center">
 <img width="256" alt="SoM_Discord" src="https://github.com/user-attachments/assets/217b9285-00f6-4d6f-8bf9-bf34ea01fa60" />
</div>

# **SoM MPV Config Info**
SoM MPV is a preconfigured, MPV bundle that includes lua scripts, configuration files, and supporting utilities such as OptiPNG. It can be used as a portable bundle or installed.

The config is designed as a polished baseline for users who want excellent video quality, proper SDR colors and HDR tone mapping, 
smooth playback and useful interface enhancements without manual tweaking. It works out of the box while adapting to different content, colorspaces, and hardware.

It is not meant to be the perfect configuration; there is no such thing.

This repository hosts the files and provides a place to submit issues or pull requests for improvements.

## **Quick Summary of Features:**

- [GPU Next](https://github.com/mpv-player/mpv/wiki/GPU-Next-vs-GPU) + d3d11 Windows playback with hardware decoding
- Automatic SDR/HDR/DV color management and tonemapping profiles
- Polar scaling and aspect ratio aware scaling with source specific tuning
- Automatic debanding and dithering profiles for WEB-DL and other source types
- Advanced subtitle styling for SRT, ASS/SSA (8-Bit WEB only), VOBSUB, and PGS subtitles
- Subtitle cleanup for long SRT blocks
- Greyed VOBSUB styling and soft blur PGS subtitle treatment
- On the fly center channel volume adjustment for multi channel audio (ctrl+scroll-wheel)
- Bundled Gandhi Sans font
- Custom OSC and right click context menu
- Thumbfast thumbnail previews
- Auto playlist loading and next file navigation
- Persistent player state across sessions
- Smart screenshot system with detailed naming, custom save path, and OptiPNG optimization
- Custom GUI WebP/GIF export with subtitle support (ctrl+g)
- Extensive custom input bindings for playback, video, audio
- Windows installer, updater, and uninstaller support
- Bundled ffmpeg, ffprobe, and OptiPNG utilities (Windows only)

*Note: We encourage everyone who downloads it to experiment with settings, key binds, and customization.  
Refer to the MPV manual for changing specific settings.*
## **Important Notes:**
- **HDR Passthrough:** This config does NOT enable HDR passthrough. It is strictly for SDR tonemapping.
- **Screenshots:** Defaults to the Desktop. To change this edit `/script-opts/smart-native-screenshot.conf`.     
  Note: If using OneDrive, you may need to set a custom save location outside of your synced Desktop folder.
### **SoM MPV Config is only available for:**
- Windows
- [Linux](https://github.com/JySzE/SoM-MPV-Config/tree/main-linux-wip?tab=readme-ov-file#som-mpv-download-for-linux)
### **Unsupported systems:**
- macOS
- Windows ARM CPUs
- Intel based macOS
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
     - Rerun to update
   - **Installer Mode** (SoM_MPV_Installer):
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
     - Rerun to update
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
     - Rerun to update
   - **Installer Mode** [[SoM_MPV_Installer.bat](https://gist.githubusercontent.com/JySzE/07e04bc5f01c5d30850a494e7297db42/raw/SoM_MPV_Installer.bat)]:
     - Installs MPV in `Program Files`
     - Creates proper shortcuts and file associations
     - Rerun to update
   - **Uninstaller Mode** [[SoM_MPV_Uninstaller.bat](https://gist.githubusercontent.com/JySzE/9f99789bc42710fba2fde19f8255b292/raw/SoM_MPV_Uninstaller.bat)]:
     - Removes existing SoM MPV installation, does not affect portable
3. Press CTRL + S on the download page, set "Save as type" to `All Files (*.*)` to save as .bat
5. [Run the bat and enjoy](https://pastebin.com/raw/hTZP2hi1)

*Restrictions apply. Option 1 recommended for most users.*

## **MPV Build Guide (macOS Apple Silicon)**
- [Guide](https://gist.github.com/JySzE/d25c7b7abf1b689739d51a6a6a6e0e29)
- *No longer maintained, Fork and fix if needed. Do not ask for support.*
