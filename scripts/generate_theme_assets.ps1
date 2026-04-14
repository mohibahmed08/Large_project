$ErrorActionPreference = 'Stop'

Add-Type -AssemblyName System.Drawing

function New-Color([string]$hex, [int]$alpha = 255) {
    $clean = $hex.TrimStart('#')
    return [System.Drawing.Color]::FromArgb(
        $alpha,
        [Convert]::ToInt32($clean.Substring(0, 2), 16),
        [Convert]::ToInt32($clean.Substring(2, 2), 16),
        [Convert]::ToInt32($clean.Substring(4, 2), 16)
    )
}

function New-PointF([double]$x, [double]$y) {
    return [System.Drawing.PointF]::new([float]$x, [float]$y)
}

function Draw-Glow($graphics, [double]$x, [double]$y, [double]$radius, [System.Drawing.Color]$color, [int]$layers = 18) {
    for ($layer = $layers; $layer -ge 1; $layer--) {
        $scale = $layer / $layers
        $diameter = $radius * 2 * (0.55 + ($scale * 0.95))
        $alpha = [Math]::Max(4, [Math]::Round($color.A * [Math]::Pow($scale, 2) * 0.12))
        $brush = [System.Drawing.SolidBrush]::new([System.Drawing.Color]::FromArgb($alpha, $color))
        $graphics.FillEllipse(
            $brush,
            [float]($x - ($diameter / 2)),
            [float]($y - ($diameter / 2)),
            [float]$diameter,
            [float]$diameter
        )
        $brush.Dispose()
    }
}

function Fill-VerticalGradient($graphics, $width, $height, [string[]]$stops) {
    $brush = [System.Drawing.Drawing2D.LinearGradientBrush]::new(
        [System.Drawing.RectangleF]::new(0, 0, $width, $height),
        [System.Drawing.Color]::Black,
        [System.Drawing.Color]::White,
        [System.Drawing.Drawing2D.LinearGradientMode]::Vertical
    )
    $blend = [System.Drawing.Drawing2D.ColorBlend]::new()
    $blend.Colors = @(
        (New-Color $stops[0]),
        (New-Color $stops[1]),
        (New-Color $stops[2])
    )
    $blend.Positions = @(0.0, 0.58, 1.0)
    $brush.InterpolationColors = $blend
    $graphics.FillRectangle($brush, 0, 0, $width, $height)
    $brush.Dispose()
}

function Get-SkySourcePath($repoRoot, $scene) {
    $file = switch ($scene.File) {
        'clearDay.png' { 'ClearSky.jpg' }
        'clearSunrise.png' { 'SunsetSunriseClearSky.png' }
        'clearNight.png' { 'NightClear.jpg' }
        'cloudyDay.png' { 'Cloudy.jpg' }
        'cloudySunrise.png' { 'SunsetSunriseCloudy.jpg' }
        'cloudyNight.png' { 'NightCloudy.jpg' }
        'partlyCloudyDay.png' { 'PartlyCloudy.jpg' }
        'partlyCloudySunrise.png' { 'SunsetSunrisePartlyCloudy.jpg' }
        'partlyCloudyNight.png' { 'NightPartlyCloudy.jpg' }
        'clear.png' { 'ClearSky.jpg' }
        'cloudy.png' { 'Cloudy.jpg' }
        'fog.png' { 'Cloudy.jpg' }
        'rain.png' { 'Cloudy.jpg' }
        'snow.png' { 'PartlyCloudy.jpg' }
        'storm.png' { 'NightCloudy.jpg' }
        default { 'ClearSky.jpg' }
    }
    return Join-Path $repoRoot "src/weather_backgrounds/$file"
}

function Draw-CoverImage($graphics, $path, $width, $height) {
    $image = [System.Drawing.Image]::FromFile($path)
    try {
        $scale = [Math]::Max($width / $image.Width, $height / $image.Height)
        $drawWidth = $image.Width * $scale
        $drawHeight = $image.Height * $scale
        $x = ($width - $drawWidth) / 2
        $y = ($height - $drawHeight) / 2
        $graphics.DrawImage($image, [float]$x, [float]$y, [float]$drawWidth, [float]$drawHeight)
    } finally {
        $image.Dispose()
    }
}

function Add-Atmosphere($graphics, $width, $height, [string]$accentHex, [string]$shadowHex, [string]$timeKey) {
    Draw-Glow $graphics ($width * 0.84) ($height * ($(if ($timeKey -eq 'night') { 0.16 } elseif ($timeKey -eq 'sunrise') { 0.28 } else { 0.24 }))) ($width * 0.18) (New-Color $accentHex 180) 9
    Draw-Glow $graphics ($width * 0.16) ($height * 0.88) ($width * 0.36) (New-Color $shadowHex 160) 8

    $mistBrush = [System.Drawing.SolidBrush]::new((New-Color 'FFFFFF' ($(if ($timeKey -eq 'night') { 10 } elseif ($timeKey -eq 'sunrise') { 18 } else { 12 }))))
    $graphics.FillEllipse($mistBrush, [float](-$width * 0.08), [float]($height * 0.58), [float]($width * 0.76), [float]($height * 0.34))
    $graphics.FillEllipse($mistBrush, [float]($width * 0.48), [float]($height * 0.62), [float]($width * 0.72), [float]($height * 0.28))
    $mistBrush.Dispose()
}

function Add-Grain($graphics, $width, $height, [int]$count = 2200) {
    $random = [System.Random]::new(111)
    for ($index = 0; $index -lt $count; $index++) {
        $alpha = 2 + $random.Next(0, 8)
        $size = 1 + ($random.NextDouble() * 1.4)
        $x = $random.NextDouble() * $width
        $y = $random.NextDouble() * $height
        $brush = [System.Drawing.SolidBrush]::new((New-Color 'FFFFFF' $alpha))
        $graphics.FillEllipse($brush, [float]$x, [float]$y, [float]$size, [float]$size)
        $brush.Dispose()
    }
}

function Draw-MountainScene($graphics, $width, $height, [string]$foregroundHex, [string]$midHex, [string]$backHex) {
    $backBrush = [System.Drawing.SolidBrush]::new((New-Color $backHex 220))
    $midBrush = [System.Drawing.SolidBrush]::new((New-Color $midHex 235))
    $frontBrush = [System.Drawing.SolidBrush]::new((New-Color $foregroundHex 245))

    $backPoints = @(
        (New-PointF -40 ($height * 0.66)),
        (New-PointF ($width * 0.12) ($height * 0.52)),
        (New-PointF ($width * 0.26) ($height * 0.58)),
        (New-PointF ($width * 0.44) ($height * 0.42)),
        (New-PointF ($width * 0.60) ($height * 0.60)),
        (New-PointF ($width * 0.80) ($height * 0.47)),
        (New-PointF ($width + 40) ($height * 0.63)),
        (New-PointF ($width + 40) ($height + 20)),
        (New-PointF -40 ($height + 20))
    )
    $midPoints = @(
        (New-PointF -40 ($height * 0.78)),
        (New-PointF ($width * 0.18) ($height * 0.60)),
        (New-PointF ($width * 0.34) ($height * 0.70)),
        (New-PointF ($width * 0.52) ($height * 0.55)),
        (New-PointF ($width * 0.70) ($height * 0.72)),
        (New-PointF ($width * 0.88) ($height * 0.62)),
        (New-PointF ($width + 40) ($height * 0.74)),
        (New-PointF ($width + 40) ($height + 20)),
        (New-PointF -40 ($height + 20))
    )
    $frontPoints = @(
        (New-PointF -40 ($height * 0.88)),
        (New-PointF ($width * 0.14) ($height * 0.74)),
        (New-PointF ($width * 0.30) ($height * 0.84)),
        (New-PointF ($width * 0.48) ($height * 0.68)),
        (New-PointF ($width * 0.66) ($height * 0.82)),
        (New-PointF ($width * 0.84) ($height * 0.72)),
        (New-PointF ($width + 40) ($height * 0.84)),
        (New-PointF ($width + 40) ($height + 20)),
        (New-PointF -40 ($height + 20))
    )

    $graphics.FillPolygon($backBrush, $backPoints)
    $graphics.FillPolygon($midBrush, $midPoints)
    $graphics.FillPolygon($frontBrush, $frontPoints)

    $backBrush.Dispose()
    $midBrush.Dispose()
    $frontBrush.Dispose()
}

function Draw-ForestScene($graphics, $width, $height, [string]$foregroundHex, [string]$midHex, [string]$backHex) {
    $backBrush = [System.Drawing.SolidBrush]::new((New-Color $backHex 220))
    $midBrush = [System.Drawing.SolidBrush]::new((New-Color $midHex 235))
    $frontBrush = [System.Drawing.SolidBrush]::new((New-Color $foregroundHex 245))

    $graphics.FillRectangle($backBrush, 0, [float]($height * 0.62), $width, [float]($height * 0.38))
    foreach ($set in @(
        @{ Brush = $backBrush; Base = 0.66; Width = 0.025; Height = 0.18; Step = 0.055; Jitter = 0.04 },
        @{ Brush = $midBrush; Base = 0.76; Width = 0.022; Height = 0.24; Step = 0.048; Jitter = 0.05 },
        @{ Brush = $frontBrush; Base = 0.86; Width = 0.020; Height = 0.30; Step = 0.043; Jitter = 0.06 }
    )) {
        $i = -2
        while ($i -lt 24) {
            $center = ($i * $width * $set.Step) + ($width * 0.12)
            $treeWidth = $width * $set.Width
            $peakY = $height * ($set.Base - $set.Height - (($i % 4) * $set.Jitter * 0.3))
            $baseY = $height * $set.Base
            $points = @(
                (New-PointF ($center - ($treeWidth * 1.7)) $baseY),
                (New-PointF ($center - ($treeWidth * 0.35)) ($peakY + ($height * 0.11))),
                (New-PointF $center $peakY),
                (New-PointF ($center + ($treeWidth * 0.45)) ($peakY + ($height * 0.10))),
                (New-PointF ($center + ($treeWidth * 1.8)) $baseY)
            )
            $graphics.FillPolygon($set.Brush, $points)
            $i++
        }
    }

    $fogBrush = [System.Drawing.SolidBrush]::new((New-Color 'D8F6E5' 18))
    $graphics.FillEllipse($fogBrush, [float](-$width * 0.10), [float]($height * 0.68), [float]($width * 1.20), [float]($height * 0.16))
    $graphics.FillEllipse($fogBrush, [float]($width * 0.12), [float]($height * 0.58), [float]($width * 0.70), [float]($height * 0.10))
    $fogBrush.Dispose()

    $backBrush.Dispose()
    $midBrush.Dispose()
    $frontBrush.Dispose()
}

function Draw-DesertScene($graphics, $width, $height, [string]$foregroundHex, [string]$midHex, [string]$backHex) {
    $backBrush = [System.Drawing.SolidBrush]::new((New-Color $backHex 235))
    $midBrush = [System.Drawing.SolidBrush]::new((New-Color $midHex 240))
    $frontBrush = [System.Drawing.SolidBrush]::new((New-Color $foregroundHex 245))

    $graphics.FillEllipse($backBrush, [float](-$width * 0.18), [float]($height * 0.54), [float]($width * 1.08), [float]($height * 0.28))
    $graphics.FillEllipse($midBrush, [float]($width * 0.12), [float]($height * 0.60), [float]($width * 1.08), [float]($height * 0.24))
    $graphics.FillEllipse($frontBrush, [float](-$width * 0.10), [float]($height * 0.70), [float]($width * 1.20), [float]($height * 0.34))

    $ridgePen = [System.Drawing.Pen]::new((New-Color 'FFFFFF' 28), 3)
    $graphics.DrawArc($ridgePen, [float]($width * 0.04), [float]($height * 0.64), [float]($width * 0.92), [float]($height * 0.14), 190, 125)
    $graphics.DrawArc($ridgePen, [float](-$width * 0.10), [float]($height * 0.74), [float]($width * 1.12), [float]($height * 0.16), 180, 120)
    $ridgePen.Dispose()

    $backBrush.Dispose()
    $midBrush.Dispose()
    $frontBrush.Dispose()
}

function Draw-OceanScene($graphics, $width, $height, [string]$foregroundHex, [string]$midHex, [string]$backHex) {
    $backBrush = [System.Drawing.SolidBrush]::new((New-Color $backHex 230))
    $midBrush = [System.Drawing.SolidBrush]::new((New-Color $midHex 235))
    $frontBrush = [System.Drawing.SolidBrush]::new((New-Color $foregroundHex 245))

    $graphics.FillRectangle($backBrush, 0, [float]($height * 0.62), $width, [float]($height * 0.38))
    $graphics.FillEllipse($midBrush, [float](-$width * 0.10), [float]($height * 0.69), [float]($width * 1.20), [float]($height * 0.14))
    $graphics.FillEllipse($frontBrush, [float](-$width * 0.06), [float]($height * 0.79), [float]($width * 1.10), [float]($height * 0.18))

    foreach ($offset in @(0.68, 0.75, 0.82)) {
        $pen = [System.Drawing.Pen]::new((New-Color 'FFFFFF' 22), 2)
        $graphics.DrawArc($pen, [float](-$width * 0.10), [float]($height * $offset), [float]($width * 0.56), [float]($height * 0.05), 200, 90)
        $graphics.DrawArc($pen, [float]($width * 0.18), [float]($height * ($offset + 0.01)), [float]($width * 0.56), [float]($height * 0.05), 185, 100)
        $graphics.DrawArc($pen, [float]($width * 0.52), [float]($height * ($offset + 0.005)), [float]($width * 0.52), [float]($height * 0.05), 195, 90)
        $pen.Dispose()
    }

    $backBrush.Dispose()
    $midBrush.Dispose()
    $frontBrush.Dispose()
}

function Draw-CloudCover($graphics, $width, $height, [int]$alpha, [double]$density, [string]$tintHex = 'FFFFFF') {
    $brush = [System.Drawing.SolidBrush]::new((New-Color $tintHex $alpha))
    $count = [Math]::Round(7 + (4 * $density))
    for ($index = 0; $index -lt $count; $index++) {
        $w = $width * (0.42 + (0.18 * ($index % 3)))
        $h = $height * (0.05 + (0.02 * ($index % 2)))
        $x = -($width * 0.16) + (($index % 4) * $width * 0.20)
        $y = $height * (0.12 + ($index * 0.05))
        $graphics.FillEllipse($brush, [float]$x, [float]$y, [float]$w, [float]$h)
    }
    $brush.Dispose()
}

function Draw-Fog($graphics, $width, $height) {
    $brush = [System.Drawing.SolidBrush]::new((New-Color 'FFFFFF' 26))
    foreach ($row in @(0.42, 0.52, 0.62, 0.72)) {
        $graphics.FillEllipse($brush, [float](-$width * 0.1), [float]($height * $row), [float]($width * 1.24), [float]($height * 0.10))
    }
    $brush.Dispose()
}

function Draw-Rain($graphics, $width, $height, [string]$accentHex, [int]$count = 42) {
    $random = [System.Random]::new(27)
    $pen = [System.Drawing.Pen]::new((New-Color $accentHex 46), 2)
    for ($index = 0; $index -lt $count; $index++) {
        $x = $random.NextDouble() * $width
        $y = ($random.NextDouble() * $height * 0.68) + ($height * 0.18)
        $length = ($height * 0.035) + ($random.NextDouble() * $height * 0.03)
        $graphics.DrawLine($pen, [float]$x, [float]$y, [float]($x + ($width * 0.04)), [float]($y + $length))
    }
    $pen.Dispose()
}

function Draw-Snow($graphics, $width, $height) {
    $random = [System.Random]::new(81)
    foreach ($index in 0..55) {
        $size = 2 + ($random.NextDouble() * 6)
        $alpha = 60 + [Math]::Round($random.NextDouble() * 80)
        $brush = [System.Drawing.SolidBrush]::new((New-Color 'FFFFFF' $alpha))
        $x = $random.NextDouble() * ($width - $size)
        $y = ($random.NextDouble() * $height * 0.70) + ($height * 0.12)
        $graphics.FillEllipse($brush, [float]$x, [float]$y, [float]$size, [float]$size)
        $brush.Dispose()
    }
}

function Draw-Storm($graphics, $width, $height, [string]$accentHex) {
    Draw-Glow $graphics ($width * 0.58) ($height * 0.30) ($width * 0.18) (New-Color $accentHex 96) 10
    $pen = [System.Drawing.Pen]::new((New-Color $accentHex 48), 2)
    $graphics.DrawLine($pen, [float]($width * 0.34), [float]($height * 0.26), [float]($width * 0.52), [float]($height * 0.58))
    $graphics.DrawLine($pen, [float]($width * 0.66), [float]($height * 0.20), [float]($width * 0.54), [float]($height * 0.48))
    $pen.Dispose()
}

function Get-WebScenes() {
    return @(
        @{ File = 'clearDay.png'; Weather = 'clear'; Time = 'day' },
        @{ File = 'clearSunrise.png'; Weather = 'clear'; Time = 'sunrise' },
        @{ File = 'clearNight.png'; Weather = 'clear'; Time = 'night' },
        @{ File = 'cloudyDay.png'; Weather = 'cloudy'; Time = 'day' },
        @{ File = 'cloudySunrise.png'; Weather = 'cloudy'; Time = 'sunrise' },
        @{ File = 'cloudyNight.png'; Weather = 'cloudy'; Time = 'night' },
        @{ File = 'partlyCloudyDay.png'; Weather = 'partly'; Time = 'day' },
        @{ File = 'partlyCloudySunrise.png'; Weather = 'partly'; Time = 'sunrise' },
        @{ File = 'partlyCloudyNight.png'; Weather = 'partly'; Time = 'night' }
    )
}

function Get-MobileScenes() {
    return @(
        @{ File = 'clear.png'; Weather = 'clear'; Time = 'day' },
        @{ File = 'cloudy.png'; Weather = 'cloudy'; Time = 'day' },
        @{ File = 'fog.png'; Weather = 'fog'; Time = 'day' },
        @{ File = 'rain.png'; Weather = 'rain'; Time = 'day' },
        @{ File = 'snow.png'; Weather = 'snow'; Time = 'day' },
        @{ File = 'storm.png'; Weather = 'storm'; Time = 'night' }
    )
}

function Render-ThemeImage($path, $theme, $scene, $width, $height) {
    $bitmap = [System.Drawing.Bitmap]::new($width, $height)
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic

    $timeStops = switch ($scene.Time) {
        'sunrise' { $theme.sunriseStops }
        'night' { $theme.nightStops }
        default { $theme.dayStops }
    }
    Fill-VerticalGradient $graphics $width $height $timeStops
    Draw-CoverImage $graphics (Get-SkySourcePath $repoRoot $scene) $width $height
    $photoTint = [System.Drawing.SolidBrush]::new((New-Color $timeStops[1] 92))
    $graphics.FillRectangle($photoTint, 0, 0, $width, $height)
    $photoTint.Dispose()
    Add-Atmosphere $graphics $width $height $theme.glow $theme.shadow $scene.Time

    switch ($theme.landscape) {
        'mountain' { Draw-MountainScene $graphics $width $height $theme.foreground $theme.midground $theme.backgroundShape }
        'forest' { Draw-ForestScene $graphics $width $height $theme.foreground $theme.midground $theme.backgroundShape }
        'desert' { Draw-DesertScene $graphics $width $height $theme.foreground $theme.midground $theme.backgroundShape }
        'ocean' { Draw-OceanScene $graphics $width $height $theme.foreground $theme.midground $theme.backgroundShape }
    }

    switch ($scene.Weather) {
        'partly' {
            Draw-CloudCover $graphics $width $height 28 0.8 $theme.cloudTint
        }
        'cloudy' {
            Draw-CloudCover $graphics $width $height 44 1.4 $theme.cloudTint
        }
        'fog' {
            Draw-CloudCover $graphics $width $height 34 1.2 $theme.cloudTint
            Draw-Fog $graphics $width $height
        }
        'rain' {
            Draw-CloudCover $graphics $width $height 40 1.3 $theme.cloudTint
            Draw-Rain $graphics $width $height $theme.weatherAccent
        }
        'snow' {
            Draw-CloudCover $graphics $width $height 32 1.0 $theme.cloudTint
            Draw-Snow $graphics $width $height
        }
        'storm' {
            Draw-CloudCover $graphics $width $height 52 1.5 $theme.cloudTint
            Draw-Rain $graphics $width $height $theme.weatherAccent 54
            Draw-Storm $graphics $width $height $theme.weatherAccent
        }
        default { }
    }

    Add-Grain $graphics $width $height

    $vignetteBrush = [System.Drawing.SolidBrush]::new((New-Color '000000' ($(if ($scene.Time -eq 'night') { 44 } else { 22 }))))
    $graphics.FillEllipse($vignetteBrush, [float](-$width * 0.14), [float](-$height * 0.12), [float]($width * 1.28), [float]($height * 1.20))
    $vignetteBrush.Dispose()

    [System.IO.Directory]::CreateDirectory([System.IO.Path]::GetDirectoryName($path)) | Out-Null
    $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)

    $graphics.Dispose()
    $bitmap.Dispose()
}

$repoRoot = Split-Path -Parent $PSScriptRoot

$themes = @(
    @{
        id = 'default'
        landscape = 'mountain'
        dayStops = @('#0f1c2e', '#355f95', '#8ec8ff')
        sunriseStops = @('#26161b', '#8e4f4d', '#ebb07a')
        nightStops = @('#050912', '#18233f', '#374c8c')
        foreground = '#213148'
        midground = '#405870'
        backgroundShape = '#7089a4'
        glow = '#fff0bf'
        shadow = '#6fb8ff'
        weatherAccent = '#b8d7ff'
        cloudTint = 'F3F6FB'
    },
    @{
        id = 'aurora'
        landscape = 'mountain'
        dayStops = @('#0e1330', '#2f2f7e', '#7246d8')
        sunriseStops = @('#1d1327', '#6742a8', '#c67ce8')
        nightStops = @('#040612', '#161341', '#402b7a')
        foreground = '#1f1940'
        midground = '#3a3370'
        backgroundShape = '#6656a6'
        glow = '#9df7dc'
        shadow = '#8d6dff'
        weatherAccent = '#c7f0ff'
        cloudTint = 'EEE7FF'
    },
    @{
        id = 'forest'
        landscape = 'forest'
        dayStops = @('#0a1d17', '#1f5b47', '#7bc18a')
        sunriseStops = @('#1f1813', '#5d4b2e', '#b18a58')
        nightStops = @('#06110e', '#15322b', '#2f5b4b')
        foreground = '#0b251b'
        midground = '#194333'
        backgroundShape = '#3f755c'
        glow = '#d8f4c2'
        shadow = '#6de2a8'
        weatherAccent = '#cfe8ff'
        cloudTint = 'EFF7F1'
    },
    @{
        id = 'desert'
        landscape = 'desert'
        dayStops = @('#2a1808', '#a05620', '#f0c27f')
        sunriseStops = @('#31140f', '#a34a2d', '#f2a66a')
        nightStops = @('#120b08', '#43302a', '#7a5d4d')
        foreground = '#8c5427'
        midground = '#bf7b3a'
        backgroundShape = '#e2ac69'
        glow = '#fff1c7'
        shadow = '#f3b06a'
        weatherAccent = '#ffe4bf'
        cloudTint = 'FFF2E3'
    },
    @{
        id = 'ocean'
        landscape = 'ocean'
        dayStops = @('#071b2a', '#0c4f68', '#7fcdd7')
        sunriseStops = @('#191826', '#5a4765', '#f1a17c')
        nightStops = @('#030a12', '#0c2338', '#1e4d5f')
        foreground = '#0a3442'
        midground = '#116275'
        backgroundShape = '#4ea2a8'
        glow = '#d7fbff'
        shadow = '#72d5e4'
        weatherAccent = '#d1f1ff'
        cloudTint = 'EAF8FF'
    },
    @{
        id = 'midnight'
        landscape = 'mountain'
        dayStops = @('#0b1020', '#26334e', '#7b8ba4')
        sunriseStops = @('#1d1420', '#614a5f', '#b89aaa')
        nightStops = @('#02040b', '#111827', '#344052')
        foreground = '#0d1522'
        midground = '#263242'
        backgroundShape = '#4a5b71'
        glow = '#eff6ff'
        shadow = '#96a8d2'
        weatherAccent = '#d5e6ff'
        cloudTint = 'F4F6FB'
    }
)

foreach ($theme in $themes) {
    foreach ($scene in (Get-WebScenes)) {
        $path = Join-Path $repoRoot "public/theme_packages/$($theme.id)/$($scene.File)"
        Render-ThemeImage $path $theme $scene 720 1280
    }

    foreach ($scene in (Get-MobileScenes)) {
        $path = Join-Path $repoRoot "mobile/assets/theme_packages/$($theme.id)/$($scene.File)"
        Render-ThemeImage $path $theme $scene 432 768
    }
}
