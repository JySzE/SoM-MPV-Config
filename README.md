<div align="center">
 <img width="256" alt="SoM_Discord" src="https://github.com/user-attachments/assets/217b9285-00f6-4d6f-8bf9-bf34ea01fa60" />
</div>

# **SoM MPV Config Info**
SoM MPV is a preconfigured, MPV bundle that includes lua scripts, configuration files. It can be used as a portable bundle or installed.

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

*Note: We encourage everyone who downloads it to experiment with settings, key binds, and customization.  
Refer to the MPV manual for changing specific settings.*
## **Important Notes:**
- **HDR Passthrough:** This config does NOT enable HDR passthrough. It is strictly for SDR tonemapping.
- **Screenshots:** Defaults to the Desktop. To change this edit `/script-opts/smart-native-screenshot.conf`.     
# **SoM MPV Download FOR LINUX**

## **Manual Download**
1. Dependencies: MPV, OptiPNG, Git, FFmpeg, FFprobe
2. Open terminal and run `git clone -b main-linux-wip --depth 1 https://github.com/JySzE/SoM-MPV-Config ~/.config/mpv/`
3. Open MPV and enjoy.

## **Manual Update**
1. Open terminal and run `find ~/.config/mpv -mindepth 1 -exec rm -rf {} +; git clone -b main-linux-wip --depth 1 https://github.com/JySzE/SoM-MPV-Config ~/.config/mpv`
2. Open MPV and enjoy.
