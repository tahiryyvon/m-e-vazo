Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile("c:\Users\Taka\Downloads\Compressed\guitar_lyrics_player\assets\images\me_vazo_logo.jpg")
Write-Host "Width: $($bmp.Width), Height: $($bmp.Height)"

# Find the bounding box of the squircle
# The squircle border has bright golden/amber pixels (e.g. R > 60 or G > 40)
# Let's find minX, maxX, minY, maxY
$minX = $bmp.Width
$maxX = 0
$minY = $bmp.Height
$maxY = 0

for ($y = 0; $y -lt $bmp.Height; $y += 4) {
    for ($x = 0; $x -lt $bmp.Width; $x += 4) {
        $c = $bmp.GetPixel($x, $y)
        # Check if pixel is part of the icon (glow or border or content, not pure black background)
        if ($c.R -gt 35 -or $c.G -gt 30 -or $c.B -gt 30) {
            if ($x -lt $minX) { $minX = $x }
            if ($x -gt $maxX) { $maxX = $x }
            if ($y -lt $minY) { $minY = $y }
            if ($y -gt $maxY) { $maxY = $y }
        }
    }
}

Write-Host "Bounding box: Left=$minX, Top=$minY, Right=$maxX, Bottom=$maxY"
Write-Host "Icon width: $($maxX - $minX), Icon height: $($maxY - $minY)"
$bmp.Dispose()
