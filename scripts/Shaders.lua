-- deus0ww - 2023-12-09

local mp      = require 'mp'
local msg     = require 'mp.msg'
local opt     = require 'mp.options'
local utils   = require 'mp.utils'


local opts = {
    enabled               = false,      -- Master switch to enable/disable shaders
    always_fs_scale       = true,       -- Always set scale relative to fullscreen resolution
    set_timer             = 0,

    auto_switch           = true,       -- Auto switch shader preset base on path
    default_index         = 2,          -- Default shader set

    hifps_threshold       = 29,
    lowfps_threshold      = 15,

    preset_1_enabled      = true,
    preset_1_path         = 'rendered',
    preset_1_index        = 2,

    preset_2_enabled      = true,       -- Enable this preset
    preset_2_path         = 'anime',    -- Path search string (Lua pattern)
    preset_2_index        = 2,          -- Shader set index to enable

    preset_3_enabled      = true,
    preset_3_path         = 'cartoon',
    preset_3_index        = 2,

    preset_4_enabled      = false,
    preset_4_path         = '%[.+%]',
    preset_4_index        = 2,

    preset_hifps_enabled  = true,       -- Target frame time: 15ms
    preset_hifps_index    = 3,

    preset_lowfps_enabled = true,       -- Target frame time: 90ms
    preset_lowfps_index   = 4,

    preset_rgb_enabled    = true,
    preset_rgb_index      = 4,
}

local current_index, enabled = opts.default_index, opts.enabled
local function on_opts_update()
    enabled = opts.enabled
end
opt.read_options(opts, mp.get_script_name(), on_opts_update)
on_opts_update()



------------------
--- Properties ---
------------------
local props, last_shaders
local function reset()
    props = {
        ['dwidth']                   = -1,
        ['dheight']                  = -1,

        ['display-width']            = -1,
        ['display-height']           = -1,

        ['osd-dimensions/w']         = -1,
        ['osd-dimensions/h']         = -1,
        ['osd-dimensions/mt']        = -1,
        ['osd-dimensions/mb']        = -1,
        ['osd-dimensions/ml']        = -1,
        ['osd-dimensions/mr']        = -1,

        ['container-fps']            = -1,
        ['video-params/rotate']      = -1,
        ['video-params/colormatrix'] = '',
    }
end
reset()

local function is_initialized()
    return ((props['dwidth']                         >   0) and
            (props['dheight']                        >   0) and

            (props['display-width']                  >   0) and
            (props['display-height']                 >   0) and

            (props['osd-dimensions/w']               >   0) and
            (props['osd-dimensions/h']               >   0) and
            (props['osd-dimensions/mt']              >=  0) and
            (props['osd-dimensions/mb']              >=  0) and
            (props['osd-dimensions/ml']              >=  0) and
            (props['osd-dimensions/mr']              >=  0) and

            (props['container-fps']                  >   0) and
            (props['video-params/rotate']            >=  0) and

            (type(props['video-params/colormatrix']) == 'string') and
            (props['video-params/colormatrix']       ~= '') and
            true)
end



--------------------
--- Shader Utils ---
--------------------
local function is_high_fps() return props['container-fps'] >= opts.hifps_threshold  end
local function is_low_fps()  return props['container-fps'] <= opts.lowfps_threshold end
local function is_hdr()      return props['video-params/colormatrix']:find('bt.2020') ~= nil end
local function is_rgb()      return props['video-params/colormatrix']:find('rgb')     ~= nil end

local function get_scale()
    local rotated = (props['video-params/rotate'] % 180 ~= 0)
    local video_width  = rotated and props['dheight'] or props['dwidth']
    local video_height = rotated and props['dwidth']  or props['dheight']
    local scaled_width, scaled_height
    if opts.always_fs_scale then
        scaled_width  = props['display-width']
        scaled_height = props['display-height']
    else
        scaled_width  = props['osd-dimensions/w'] - props['osd-dimensions/ml'] - props['osd-dimensions/mr']
        scaled_height = props['osd-dimensions/h'] - props['osd-dimensions/mt'] - props['osd-dimensions/mb']
    end
    return math.min(scaled_width/video_width, scaled_height/video_height)
end

local function minmax(v, min, max)    return math.min(math.max(v, min), max) end
local function minmax_scale(min, max) return math.floor(minmax(get_scale(), min, max) + 0.11) end

local function format_status()
    local temp = (opts.always_fs_scale and 'FS ' or '') .. ('Scale: %.3f'):format(get_scale())
    if is_high_fps() then temp = temp .. ' HighFPS' end
    if is_low_fps()  then temp = temp .. ' LowFPS'  end
    if is_hdr()      then temp = temp .. ' HDR'     end
    if is_rgb()      then temp = temp .. ' RGB'     end
    return temp
end

local function set_scaler (o, scale, k) o[scale] = k end
local function set_scalers(o, scale, cscale, dscale)
    set_scaler (o, 'scale',  scale)
    set_scaler (o, 'cscale', cscale)
    set_scaler (o, 'dscale', dscale)
    return o
end
local function set_params(o, p)
    o['glsl-shader-opts'] = (utils.to_string(p):gsub('[^%w_.,=]', ''))
    return o;
end



--------------------
--- Shader Files ---
--------------------
local shaders_path = '~~/shaders/'

-- ArtCNN by Artoriuz - https://github.com/Artoriuz/ArtCNN
local art_y_path   = shaders_path .. 'artcnn/Luma/'
local art_uv_path  = shaders_path .. 'artcnn/Chroma/'
local art_yuv_path = shaders_path .. 'artcnn/YCbCr/'
local artcnn   = {
    y32        = art_y_path   .. 'ArtCNN_C4F32.glsl',
    y32ll      = art_y_path   .. 'ArtCNN_C4F32_LL.glsl',
    y32sh      = art_y_path   .. 'ArtCNN_C4F32_SH.glsl',
    y32dn      = art_y_path   .. 'ArtCNN_C4F32_DN.glsl',
    y32ds      = art_y_path   .. 'ArtCNN_C4F32_DS.glsl',
    y16        = art_y_path   .. 'ArtCNN_C4F16.glsl',
    y16x       = art_y_path   .. 'ArtCNN_C4F16_DIV2K.glsl',
    y16ll      = art_y_path   .. 'ArtCNN_C4F16_LL.glsl',
    y16sh      = art_y_path   .. 'ArtCNN_C4F16_SH.glsl',
    y16dn      = art_y_path   .. 'ArtCNN_C4F16_DN.glsl',
    y16ds      = art_y_path   .. 'ArtCNN_C4F16_DS.glsl',
    y8         = art_y_path   .. 'ArtCNN_C4F8.glsl',
    y8ll       = art_y_path   .. 'ArtCNN_C4F8_LL.glsl',
    y8sh       = art_y_path   .. 'ArtCNN_C4F8_SH.glsl',
    y8dn       = art_y_path   .. 'ArtCNN_C4F8_DN.glsl',
    y8ds       = art_y_path   .. 'ArtCNN_C4F8_DS.glsl',
    
    uv32       = art_uv_path  .. 'ArtCNN_C4F32_Chroma.glsl',
    uv32dn     = art_uv_path  .. 'ArtCNN_C4F32_DN_Chroma.glsl',
    uv32ds     = art_uv_path  .. 'ArtCNN_C4F32_DS_Chroma.glsl',
    uv32sh     = art_uv_path  .. 'ArtCNN_C4F32_SH_Chroma.glsl',
    uv16       = art_uv_path  .. 'ArtCNN_C4F16_Chroma.glsl',
    uv16dn     = art_uv_path  .. 'ArtCNN_C4F16_DN_Chroma.glsl',
    uv16ds     = art_uv_path  .. 'ArtCNN_C4F16_DS_Chroma.glsl',
    uv16sh     = art_uv_path  .. 'ArtCNN_C4F16_SH_Chroma.glsl',
    uv8        = art_uv_path  .. 'ArtCNN_C4F8_Chroma.glsl',
    uv8sh      = art_uv_path  .. 'ArtCNN_C4F8_SH_Chroma.glsl',

    yuv32      = art_yuv_path .. 'ArtCNN_C4F32_YCbCr.glsl',
    yuv32dn    = art_yuv_path .. 'ArtCNN_C4F32_DN_YCbCr.glsl',
    yuv32ds    = art_yuv_path .. 'ArtCNN_C4F32_DS_YCbCr.glsl',
    yuv32sh    = art_yuv_path .. 'ArtCNN_C4F32_SH_YCbCr.glsl',
    yuv16      = art_yuv_path .. 'ArtCNN_C4F16_YCbCr.glsl',
    yuv16dn    = art_yuv_path .. 'ArtCNN_C4F16_DN_YCbCr.glsl',
    yuv16ds    = art_yuv_path .. 'ArtCNN_C4F16_DS_YCbCr.glsl',
    yuv16sh    = art_yuv_path .. 'ArtCNN_C4F16_SH_YCbCr.glsl',
}

-- CuNNy by funnyplanter - https://github.com/funnyplanter/CuNNy
local cunny_ds_path   = shaders_path .. 'cunny/ds/'
local cunny_soft_path = shaders_path .. 'cunny/soft/'
local cunny    = {
    dsfaster   = cunny_ds_path  .. 'CuNNy-faster-DS.glsl',
    dsfast     = cunny_ds_path  .. 'CuNNy-fast-DS.glsl',
    ds2x12     = cunny_ds_path  .. 'CuNNy-2x12-DS.glsl',
    ds3x12     = cunny_ds_path  .. 'CuNNy-3x12-DS.glsl',
    ds4x12     = cunny_ds_path  .. 'CuNNy-4x12-DS.glsl',
    ds4x16     = cunny_ds_path  .. 'CuNNy-4x16-DS.glsl',
    ds4x24     = cunny_ds_path  .. 'CuNNy-4x24-DS.glsl',
    ds4x32     = cunny_ds_path  .. 'CuNNy-4x32-DS.glsl',
    ds8x32     = cunny_ds_path  .. 'CuNNy-8x32-DS.glsl',

    sfastest   = cunny_soft_path .. 'CuNNy-veryfast-SOFT.glsl',
    sfaster    = cunny_soft_path .. 'CuNNy-faster-SOFT.glsl',
    sfast      = cunny_soft_path .. 'CuNNy-fast-SOFT.glsl',
    s2x12      = cunny_soft_path .. 'CuNNy-2x12-SOFT.glsl',
    s3x12      = cunny_soft_path .. 'CuNNy-3x12-SOFT.glsl',
    s4x12      = cunny_soft_path .. 'CuNNy-4x12-SOFT.glsl',
    s4x16      = cunny_soft_path .. 'CuNNy-4x16-SOFT.glsl',
    s4x24      = cunny_soft_path .. 'CuNNy-4x24-SOFT.glsl',
    s4x32      = cunny_soft_path .. 'CuNNy-4x32-SOFT.glsl',
}

-- FSR by agyild - https://gist.github.com/agyild
local fsr_path = shaders_path .. 'fsr/'
local fsr      = {
    full       = fsr_path .. 'FSR.glsl',
    y_easu     = fsr_path .. 'FSR_EASU.glsl',
    y_rcas     = fsr_path .. 'FSR_RCAS.glsl',
    uv_easu    = fsr_path .. 'FSR_EASU_Chroma.glsl',
    uv_rcas    = fsr_path .. 'FSR_RCAS_Chroma.glsl',
    rgb_easu   = fsr_path .. 'FSR_EASU_RGB.glsl',
    rgb_rcas   = fsr_path .. 'FSR_RCAS_RGB.glsl',
    
}

-- FSRCNNX by igv        - https://github.com/igv/FSRCNN-TensorFlow
-- FSRCNNX by HelpSeeker - https://github.com/HelpSeeker/FSRCNN-TensorFlow/
local fsrcnnx_path = shaders_path .. 'fsrcnnx/'
local fsrcnnx1 = {
    r16e       = fsrcnnx_path .. 'FSRCNNX_x1_16-0-4-1_distort.glsl',
    r16l       = fsrcnnx_path .. 'FSRCNNX_x1_16-0-4-1_anime_distort.glsl',
}
local fsrcnnx2 = {
    r8         = fsrcnnx_path .. 'FSRCNNX_x2_8-0-4-1.glsl',
    r8l        = fsrcnnx_path .. 'FSRCNNX_x2_8-0-4-1_LineArt.glsl',
    r16        = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1.glsl',
    r16e       = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1_distort.glsl',
    r16l       = fsrcnnx_path .. 'FSRCNNX_x2_16-0-4-1_anime_distort.glsl',
}

-- RAVU by bjin - https://github.com/bjin/mpv-prescalers
local ravu_zoom_path = shaders_path .. 'ravu/zoom/'
local ravu_lite_path = shaders_path .. 'ravu/lite/'
local ravu     = {
    lite       = {
        r3     = ravu_lite_path .. 'ravu-lite-ar-r3.hook',
        r3c    = ravu_lite_path .. 'ravu-lite-ar-r3.compute',
        r4     = ravu_lite_path .. 'ravu-lite-ar-r4.hook',
        r4c    = ravu_lite_path .. 'ravu-lite-ar-r4.compute',
    },
    zoom       = {
        r2     = ravu_zoom_path .. 'ravu-zoom-ar-r2.hook',
        r3     = ravu_zoom_path .. 'ravu-zoom-ar-r3.hook',
        uv_r2  = ravu_zoom_path .. 'ravu-zoom-ar-r2-chroma.hook',
        uv_r3  = ravu_zoom_path .. 'ravu-zoom-ar-r3-chroma.hook',
        uv_r2x = ravu_zoom_path .. 'ravu-zoom-ar-r2x-chroma.hook',
        uv_r3x = ravu_zoom_path .. 'ravu-zoom-ar-r3x-chroma.hook',
        rgb_r2 = ravu_zoom_path .. 'ravu-zoom-ar-r2-rgb.hook',
        rgb_r3 = ravu_zoom_path .. 'ravu-zoom-ar-r3-rgb.hook',
    },
}

-- igv's - https://gist.github.com/igv
local igv_path = shaders_path .. 'igv/'
local igv      = {
    sssr       = igv_path .. 'SSimSuperRes.glsl',
    ssds       = igv_path .. 'SSimDownscaler.glsl',
}
local as       = {
    rgb        = igv_path .. 'adaptive-sharpen.glsl',
    luma       = igv_path .. 'adaptive-sharpen-luma.glsl',
}

-- CfL by Artoriuz - https://github.com/Artoriuz/glsl-chroma-from-luma-prediction
local cfl_path = shaders_path .. 'cfl/'
local cfl      = {
    b          = cfl_path .. 'CfL_Prediction.glsl',
    l          = cfl_path .. 'CfL_Prediction_Lite.glsl',
    s          = cfl_path .. 'CfL_Prediction_Smooth.glsl',

    fsr        = cfl_path .. 'CfL_Prediction_FSR.glsl',
    fsr_bi     = cfl_path .. 'CfL_Prediction_FSR_Bilinear.glsl',  

    x          = cfl_path .. 'CfL_Prediction_Test.glsl',
}

-- FilmGrain by Haasn - https://raw.githubusercontent.com/haasn/gentoo-conf/xor/home/nand/.mpv/shaders/filmgrain.glsl
local grain_path = shaders_path .. 'filmgrain/'
local grain    = {
    g          = grain_path .. 'filmgrain.glsl',
    s          = grain_path .. 'filmgrain-smooth.glsl',
}

-- Shaders by Garamond13 - https://github.com/garamond13
local g13      = shaders_path .. 'g13/'
local g13      = {
    blur       = g13 .. 'gaussianBlur.glsl',
}



-------------------
--- Shader Sets ---
-------------------
local default_antiring = 0.8 -- For scalers/shaders using libplacebo-based antiring filter

local function default_shaders()
    local s = {}
    s[#s+1] = ({[3]=artcnn.y8,     [4]=artcnn.y16                       })[minmax_scale(3, 4)]
    s[#s+1] = ({[3]=ravu.zoom.r3,  [4]=ravu.lite.r4c, [5]=ravu.zoom.r3  })[minmax_scale(3, 5)]
    s[#s+1] = fsr.easu
    s[#s+1] = get_scale() <= 1.1 and cfl.fsr_bi or cfl.fsr
    return s
end

local function default_options()
    local o = {
        ['linear-downscaling'] = 'no', 
        ['scale-antiring']     = default_antiring,
        ['cscale-antiring']    = default_antiring,
        ['dscale-antiring']    = default_antiring,
     }
    if (get_scale() <= 1.1) or not enabled then
        return set_scalers(o, 'ewa_lanczos4sharpest', 'ewa_lanczos4sharpest', 'lanczos')
    else
        return set_scalers(o, 'lanczos', 'lanczos', 'lanczos')
    end
end

local function default_params()
    return {
        as_sharpness   = 0.4,

        blur_radius    = 1.0,
        blur_sigma     = 0.5,

        fg_intensity   = math.min(0.08, 0.02 + scale / 100),
        fgs_intensity  = math.min(0.09, 0.03 + scale / 100),
        fgs_taps       = 1,

        fsr_pq         = 0,
        fsr_sharpness  = math.max(0.20, 0.60 - scale / 10),

        ravu_antiring  = default_antiring,
        ravu_chroma_ar = default_antiring,
    }
end

local sets = {}

sets[#sets+1] = function()
    local s, o, p = default_shaders(), default_options(), default_params()
    s[#s+1] = get_scale() <= 1.1 and as.luma or nil
    return { shaders = s, options = set_params(o, p), label = 'Default'   }
end

sets[#sets+1] = function()
    local s, o, p = default_shaders(), default_options(), default_params()
    s[1]    = ({[3]=artcnn.y8ds,   [4]=artcnn.y16ds                     })[minmax_scale(3, 4)]
    s[#s+1] = get_scale() <= 1.1 and as.luma or nil
    return { shaders = s, options = set_params(o, p), label = 'Denoise & Sharpen' }
end

sets[#sets+1] = function()
    local s, o, p = {}, default_options(), default_params()
    s[#s+1] = ({                                                         [4]=artcnn.y8ds                      })[minmax_scale(1, 4)]
    s[#s+1] = ({[1]=ravu.zoom.r3,  [2]=ravu.lite.r4c, [3]=ravu.zoom.r3,  [4]=ravu.lite.r4c, [5]=ravu.zoom.r3  })[minmax_scale(1, 5)]
    s[#s+1] = fsr.easu
    s[#s+1] = get_scale() <= 1.1 and cfl.fsr_bi or cfl.fsr
    return { shaders = s, options = set_params(o, p), label = 'High FPS' }
end

sets[#sets+1] = function()
    local s, o, p = {}, default_options(), default_params()
    s[#s+1] = artcnn.y16ds
    s[#s+1] = ravu.zoom.r3
    s[#s+1] = get_scale() <= 1.1 and as.luma or nil
    s[#s+1] = get_scale() <= 1.1 and cfl.fsr_bi or cfl.fsr
    s[#s+1] = ravu.zoom.rgb_r3
    s[#s+1] = igv.ssds
    o['linear-downscaling'] = 'no'  -- for ssds
    set_scalers(o, 'ewa_lanczossharp', 'ewa_lanczossharp', 'lanczos')
    return { shaders = s, options = set_params(o, p), label = 'Low FPS & RGB' }
end



--------------------
--- MPV Commands ---
--------------------
local function show_osd(no_osd, label)
    if no_osd then return end
    mp.osd_message(('%s Shaders Set %d: %s'):format(enabled and '■' or '□', current_index, (label or 'n/a') .. ' [' .. format_status() .. ']'), 6)
end

local function mpv_set_options(options)
    msg.debug('Setting Options:', utils.to_string(options))
    for name, value in pairs(options) do
        mp.commandv('set', name, value)
    end
end

local function mpv_clear_options()
    mpv_set_options(default_options())
end

local function mpv_clear_shaders()
    msg.debug('Clearing Shaders.')
    mp.commandv('change-list', 'glsl-shaders', 'clr', '')
end

local function mpv_set_shaders(shaders)
    --msg.debug(format_status())
    msg.debug('Setting Shaders:', utils.to_string(shaders))
    mp.commandv('change-list', 'glsl-shaders', 'set', table.concat(shaders, ':'))
end

local function clear_shaders(no_osd)
    if not is_initialized() then
        msg.debug('Setting Shaders: skipped - properties not available.')
        return
    end
    local shaders = sets[current_index]()
    show_osd(no_osd, shaders.label)
    if last_shaders == nil then
        msg.debug('Clearing Shaders: skipped - no shader found.')
        return
    end
    last_shaders = nil
--  mpv_clear_options()
    mpv_clear_shaders()
end

local function set_shaders(no_osd)
    if not is_initialized() then
        msg.debug('Setting Shaders: skipped - properties not available.')
        return
    end
    local shaders = sets[current_index]()
    show_osd(no_osd, shaders.label)
    if not enabled then
        msg.debug('Setting Shaders: skipped - disabled.')
        return
    end
    local s, _ = utils.to_string(shaders)
    if last_shaders == s then
        msg.debug('Setting Shaders: skipped - shaders unchanged.')
        return
    end
    last_shaders = s
    mpv_set_options(shaders.options)
    mpv_set_shaders(shaders.shaders)
end



--------------------------
--- Observers & Events ---
--------------------------
local function set_default_index()
    if not opts.auto_switch then return end
    local path = mp.get_property_native('path', ''):lower()
    current_index = opts.default_index
    if opts.preset_4_enabled and path:find(opts.preset_4_path) ~= nil then current_index = opts.preset_4_index end
    if opts.preset_3_enabled and path:find(opts.preset_3_path) ~= nil then current_index = opts.preset_3_index end
    if opts.preset_2_enabled and path:find(opts.preset_2_path) ~= nil then current_index = opts.preset_2_index end
    if opts.preset_1_enabled and path:find(opts.preset_1_path) ~= nil then current_index = opts.preset_1_index end
    if opts.preset_rgb_enabled    and is_rgb()      then current_index = opts.preset_rgb_index    end
    if opts.preset_lowfps_enabled and is_low_fps()  then current_index = opts.preset_lowfps_index end
    if opts.preset_hifps_enabled  and is_high_fps() then current_index = opts.preset_hifps_index  end
    msg.debug("Default Index:", current_index)
end

local timer = mp.add_timeout(opts.set_timer, function() set_shaders(true) end)
timer:kill()
local firstrun = true
local function observe_prop(k, v)
    -- msg.debug(k, props[k], '->', utils.to_string(v))
    props[k] = v or -1

    if is_initialized() then
        if firstrun then set_default_index(); firstrun = false end
        msg.debug('Resetting Timer')
        timer:kill()
        timer:resume()
    end
end


local function start()
    reset()
    firstrun = true
    for prop, _ in pairs(props) do
        mp.observe_property(prop, 'native', observe_prop)
    end
end
mp.register_event('file-loaded', start)



----------------
--- Bindings ---
----------------
local function cycle_set_up(no_osd)
    msg.debug('Shader - Up:', current_index)
    if not is_initialized() then return end
    current_index = (current_index % #sets) + 1
    set_shaders(no_osd)
end

local function cycle_set_dn(no_osd)
    msg.debug('Shader - Down:', current_index)
    if not is_initialized() then return end
    current_index = ((current_index - 2) % #sets) + 1
    set_shaders(no_osd)
end

local function toggle_set(no_osd)
    msg.debug('Shader - Toggling:', current_index)
    if not is_initialized() then return end
    enabled = not enabled
    --set_default_index()
    if enabled then set_shaders(no_osd) else clear_shaders(no_osd) end
end

local function enable_set(no_osd)
    msg.debug('Shader - Enabling:', current_index)
    if not is_initialized() then return end
    enabled = true
    --set_default_index()
    set_shaders(no_osd)
end

local function disable_set(no_osd)
    msg.debug('Shader - Disabling:', current_index)
    if not is_initialized() then return end
    enabled = false
    clear_shaders(no_osd)
end

local function show_set(no_osd)
    msg.debug('Shader - Showing:', current_index)
    if not is_initialized() then return end
    show_osd(no_osd, sets[current_index]().label)
end

mp.register_script_message('Shaders-cycle+',  function(no_osd) cycle_set_up(no_osd == 'yes') end)
mp.register_script_message('Shaders-cycle-',  function(no_osd) cycle_set_dn(no_osd == 'yes') end)
mp.register_script_message('Shaders-toggle',  function(no_osd) toggle_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-enable',  function(no_osd) enable_set(no_osd   == 'yes') end)
mp.register_script_message('Shaders-disable', function(no_osd) disable_set(no_osd  == 'yes') end)
mp.register_script_message('Shaders-show',    function(no_osd) show_set(no_osd     == 'yes') end)
