Add-Type -AssemblyName System.Drawing

$srcPath = "c:\Users\Taka\Downloads\Compressed\guitar_lyrics_player\assets\images\me_vazo_logo.jpg"
if (-not (Test-Path $srcPath)) {
    Write-Error "Source image not found at $srcPath"
    exit 1
}

$srcImage = [System.Drawing.Image]::FromFile($srcPath)

function Resize-Image($image, $width, $height) {
    $destRect = New-Object System.Drawing.Rectangle(0, 0, $width, $height)
    $destImage = New-Object System.Drawing.Bitmap($width, $height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
    $destImage.SetResolution($image.HorizontalResolution, $image.VerticalResolution)
    
    $graphics = [System.Drawing.Graphics]::FromImage($destImage)
    $graphics.CompositingMode = [System.Drawing.Drawing2D.CompositingMode]::SourceOver
    $graphics.CompositingQuality = [System.Drawing.Drawing2D.CompositingQuality]::HighQuality
    $graphics.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::HighQuality
    $graphics.PixelOffsetMode = [System.Drawing.Drawing2D.PixelOffsetMode]::HighQuality
    
    $wrapMode = New-Object System.Drawing.Imaging.ImageAttributes
    $wrapMode.SetWrapMode([System.Drawing.Drawing2D.WrapMode]::TileFlipXY)
    $graphics.DrawImage($image, $destRect, 0, 0, $image.Width, $image.Height, [System.Drawing.GraphicsUnit]::Pixel, $wrapMode)
    $graphics.Dispose()
    
    return $destImage
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
    Write-Host "Generating Android icon ($size x $size): $targetPath"
    $resized = Resize-Image $srcImage $size $size
    $dir = Split-Path $targetPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $resized.Save($targetPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $resized.Dispose()
}

# 512x512 Store icon
$storeIcon = Resize-Image $srcImage 512 512
$storeIcon.Save("assets/images/app_icon.png", [System.Drawing.Imaging.ImageFormat]::Png)
$storeIcon.Dispose()

# Windows .ico generation
Write-Host "Generating Windows .ico at windows/runner/resources/app_icon.ico"
$icoSizes = @(256, 128, 64, 48, 32, 16)
$pngStreams = @()

foreach ($sz in $icoSizes) {
    $bmp = Resize-Image $srcImage $sz $sz
    $ms = New-Object System.IO.MemoryStream
    $bmp.Save($ms, [System.Drawing.Imaging.ImageFormat]::Png)
    $pngStreams += @{ Size = $sz; Bytes = $ms.ToArray() }
    $ms.Dispose()
    $bmp.Dispose()
}

$srcImage.Dispose()

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

Write-Host "Successfully generated all icons for Android and Windows!"
