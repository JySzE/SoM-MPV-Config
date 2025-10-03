-- Version 1.3
-- 09/08/2025

local mp = require 'mp'
local msg = require 'mp.msg'
local utils = require 'mp.utils'

local options = {
    save_path = ""
}

require 'mp.options'.read_options(options, "smart-native-screenshot")

local function get_desktop_path()
    local home = os.getenv("USERPROFILE") or os.getenv("HOME")
    if not home then return "." end
    return utils.join_path(home, "Desktop")
end

local function get_config_save_path()
    if options.save_path == "" or options.save_path == nil then
        return get_desktop_path()
    end

    local test_file = utils.join_path(options.save_path, "test_write_" .. os.time() .. ".tmp")
    local handle = io.open(test_file, "w")
    if handle then
        handle:close()
        os.remove(test_file)
        return options.save_path
    else
        msg.warn("Invalid save path in config: " .. options.save_path .. ", using desktop instead")
        return get_desktop_path()
    end
end

local function get_tmp_dir()
    local scripts_path = mp.find_config_file("scripts")
    if not scripts_path then return nil end
    local base = utils.split_path(scripts_path)
    return utils.join_path(base, "tmp")
end

local function tmp_dir_exists()
    local tmp_dir = get_tmp_dir()
    if not tmp_dir then return false end
    
    local test_file = utils.join_path(tmp_dir, "test_write_" .. os.time() .. ".tmp")
    local handle = io.open(test_file, "w")
    if handle then
        handle:close()
        os.remove(test_file)
        return true
    end
    return false
end

local function get_optipng_path()
    local scripts_path = mp.find_config_file("scripts")
    if not scripts_path then return nil end
    local base = utils.split_path(scripts_path)
    local exec_dir = utils.join_path(base, "exec")
    local exe_name = package.config:sub(1,1) == "\\" and "optipng.exe" or "optipng"
    return utils.join_path(exec_dir, exe_name)
end

local function timestamp_string()
    local time_pos = mp.get_property_number("time-pos")
    if not time_pos then return "unknown_time" end
    return string.format("H%02d_M%02d_S%02d_MS.%03d",
        math.floor(time_pos / 3600),
        math.floor(time_pos / 60) % 60,
        math.floor(time_pos) % 60,
        math.floor((time_pos * 1000 + 0.5) % 1000)
    )
end

local function save_with_optional_optipng(temp_path, final_path)
    local optipng_path = get_optipng_path()
    if not optipng_path or not utils.file_info(optipng_path) then
        os.remove(temp_path)
        msg.error("optipng not found - screenshot cancelled")
        mp.osd_message("Screenshot failed: optipng not found")
        return
    end
    
    local result = utils.subprocess({
        args = { optipng_path, "-strip", "all", "-quiet", "-o0", "-out", final_path, temp_path },
        cancellable = false
    })
    if result.status == 0 then
        os.remove(temp_path)
        mp.osd_message("Screenshot saved: " .. final_path)
    else
        os.remove(temp_path)
        msg.error("optipng optimization failed - screenshot cancelled")
        mp.osd_message("Screenshot failed: optipng error")
    end
end

local function process_screenshot_after_delay(temp_path, final_path)
    mp.add_timeout(0.2, function()
        if utils.file_info(temp_path) then
            save_with_optional_optipng(temp_path, final_path)
        else
            msg.warn("Screenshot file not found: " .. temp_path)
        end
    end)
end

local function smart_native_screenshot(mode)
    local filename = mp.get_property("filename") or "screenshot"
    local frame_num = mp.get_property_number("estimated-frame-number") or 0
    local timestamp = timestamp_string()
    local base_name = string.format("%s_%s_F%d", filename, timestamp, frame_num)
    local final_path = utils.join_path(get_config_save_path(), base_name .. ".png")

    if tmp_dir_exists() then
        local tmp_dir = get_tmp_dir()
        local temp_path = utils.join_path(tmp_dir, base_name .. ".png")
        mp.commandv("screenshot-to-file", temp_path, mode)
        process_screenshot_after_delay(temp_path, final_path)
    else

        msg.info("tmp directory doesn't exist, using root dir method")
        local temp_path = base_name .. "_raw.png"
        mp.commandv("screenshot-to-file", temp_path, mode)
        process_screenshot_after_delay(temp_path, final_path)
    end
end

mp.add_key_binding("", "smart-native-screenshot-nosubs", function() smart_native_screenshot("video") end)
mp.add_key_binding("", "smart-native-screenshot-subs", function() smart_native_screenshot("subtitles") end)