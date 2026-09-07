Add-Type -AssemblyName System.Drawing
$bmp = [System.Drawing.Bitmap]::FromFile("c:\Users\Taka\Downloads\Compressed\guitar_lyrics_player\assets\images\me_vazo_logo.jpg")

$left = 0
for ($x = 0; $x -lt 300; $x += 2) {
    $c = $bmp.GetPixel($x, 512)
    if ($c.R -gt 60 -or $c.G -gt 40) {
        $left = $x
        break
    }
}

$right = $bmp.Width
for ($x = $bmp.Width - 1; $x -gt $bmp.Width - 300; $x -= 2) {
    $c = $bmp.GetPixel($x, 512)
    if ($c.R -gt 60 -or $c.G -gt 40) {
        $right = $x
        break
    }
}

$top = 0
for ($y = 0; $y -lt 300; $y += 2) {
    $c = $bmp.GetPixel(512, $y)
    if ($c.R -gt 60 -or $c.G -gt 40) {
        $top = $y
        break
    }
}

$bottom = $bmp.Height
for ($y = $bmp.Height - 1; $y -gt $bmp.Height - 300; $y -= 2) {
    $c = $bmp.GetPixel(512, $y)
    if ($c.R -gt 60 -or $c.G -gt 40) {
        $bottom = $y
        break
    }
}

Write-Host "Left=$left, Top=$top, Right=$right, Bottom=$bottom"
Write-Host "Width=$($right - $left), Height=$($bottom - $top)"
$bmp.Dispose()
