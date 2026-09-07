Add-Type -AssemblyName System.Drawing

$srcPath = "c:\Users\Taka\.gemini\antigravity-ide\brain\5ff5a0fd-fec2-447a-ad75-6e917d8e6d16\me_vazo_logo_1788437883271.jpg"
if (-not (Test-Path $srcPath)) {
    $srcPath = "c:\Users\Taka\Downloads\Compressed\guitar_lyrics_player\assets\images\me_vazo_logo.jpg"
}

$origImage = [System.Drawing.Bitmap]::FromFile($srcPath)

# Tight crop of squircle (Left: 58, Top: 54, Width: 910, Height: 910)
$cropRect = New-Object System.Drawing.Rectangle(58, 54, 910, 910)
$croppedBmp = New-Object System.Drawing.Bitmap(910, 910, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
$gCrop = [System.Drawing.Graphics]::FromImage($croppedBmp)
$gCrop.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
$gCrop.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
$gCrop.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
$gCrop.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality

$destRect = New-Object System.Drawing.Rectangle(0, 0, 910, 910)
$gCrop.DrawImage($origImage, $destRect, $cropRect, [System.Drawing.GraphicsUnit]::Pixel)
$gCrop.Dispose()
$origImage.Dispose()

# Save tightly cropped base image
$croppedBmp.Save("assets/images/me_vazo_logo.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
$croppedBmp.Save("assets/images/acoustic_guitar_logo.jpg", [System.Drawing.Imaging.ImageFormat]::Jpeg)
Write-Host "Saved tightly cropped base images (910x910) without border surplus!"

function Resize-Image($image, $width, $height) {
    $dRect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $dImage = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $dImage.SetResolution($image.HorizontalResolution, $image.VerticalResolution)
    
    $g = [System.Drawing.Graphics]::FromImage($dImage)
    $g.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $g.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $g.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    
    $g.DrawImage($image, $dRect, 0, 0, $image.Width, $image.Height, [System.Drawing.GraphicsUnit]::Pixel)
    $g.Dispose()
    
    return $dImage
}

# Android mipmaps
$androidSizes = @{
    "android/app/src/main/res/mipmap-mdpi/ic_launcher.png" = 48
    "android/app/src/main/res/mipmap-hdpi/ic_launcher.png" = 72
    "android/app/src/main/res/mipmap-xhdpi/ic_launcher.png" = 96
    "android/app/src/main/res/mipmap-xxhdpi/ic_launcher.png" = 144
    "android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png" = 192
}

foreach ($entry in $androidSizes.GetEnumerator()) {
    $targetPath = $entry.Key
    $size = $entry.Value
    Write-Host "Generating tightly-cropped Android icon ($size x $size): $targetPath"
    $resized = Resize-Image $croppedBmp $size $size
    $dir = Split-Path $targetPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $resized.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Dispose()
}

# 512x512 Store icon
$storeIcon = Resize-Image $croppedBmp 512 512
$storeIcon.Save("assets/images/app_icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$storeIcon.Dispose()

# Windows .ico generation
Write-Host "Generating Windows .ico at windows/runner/resources/app_icon.ico"
$icoSizes = @(256, 128, 64, 48, 32, 16)
$pngStreams = @()

foreach ($sz in $icoSizes) {
    $bmp = Resize-Image $croppedBmp $sz $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngStreams += @{ Size = $sz; Bytes = $ms.ToArray() }
    $ms.Dispose()
    $bmp.Dispose()
}

$croppedBmp.Dispose()

# Create .ico file binary structure
$icoStream = New-Object System.IO.MemoryStream
$bw = New-Object System.IO.BinaryWriter($icoStream)

# ICONDIR header: Reserved (0), Type (1 = ICO), ImageCount
$bw.Write([UInt16]0)
$bw.Write([UInt16]1)
$bw.Write([UInt16]$pngStreams.Count)

$offset = 6 + ($pngStreams.Count * 16)

foreach ($entry in $pngStreams) {
    $widthByte = if ($entry.Size -ge 256) { [byte]0 } else { [byte]$entry.Size }
    $heightByte = if ($entry.Size -ge 256) { [byte]0 } else { [byte]$entry.Size }
    
    $bw.Write($widthByte)       # Width
    $bw.Write($heightByte)      # Height
    $bw.Write([byte]0)          # ColorCount
    $bw.Write([byte]0)          # Reserved
    $bw.Write([UInt16]1)        # ColorPlanes
    $bw.Write([UInt16]32)       # BitsPerPixel
    $bw.Write([UInt32]$entry.Bytes.Length) # ImageSize
    $bw.Write([UInt32]$offset)  # ImageOffset
    
    $offset += $entry.Bytes.Length
}

foreach ($entry in $pngStreams) {
    $bw.Write($entry.Bytes)
}

$bw.Flush()
[System.IO.File]::WriteAllBytes("windows/runner/resources/app_icon.ico", $icoStream.ToArray())
$bw.Dispose()
$icoStream.Dispose()

Write-Host "Successfully generated all tightly cropped icons for Android and Windows!"
