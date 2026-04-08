<div align="center">
  <img width="128" height="128" alt="9da9e0c1c699ec1d6fb12e044c74b2ef" src="https://github.com/user-attachments/assets/c639a895-0bcd-467f-80dc-24331c8c753a" />
</div>

# **SoM MPV Config Info**
SoM MPV is a preconfigured, MPV bundle that includes lua scripts, configuration files. It can be used as a portable bundle or installed.

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

# **SoM MPV Download FOR LINUX**

## **Manual Download**
1. Dependencies: MPV, OptiPNG, Git
2. Open terminal and run `git clone -b main-linux-wip --depth 1 https://github.com/JySzE/SoM-MPV-Config ~/.config/mpv/`
3. Open MPV and enjoy.

## **Manual Update**
1. Open terminal and run `find ~/.config/mpv -mindepth 1 -exec rm -rf {} +; git clone -b main-linux-wip --depth 1 https://github.com/JySzE/SoM-MPV-Config ~/.config/mpv`
2. Open MPV and enjoy.
