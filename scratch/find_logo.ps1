Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap("temp_corner.png")
Write-Host "Analyzing temp_corner (200x200, representing x=824..1024, y=824..1024)"

for ($y = 0; $y -lt $bmp.Height; $y += 5) {
    for ($x = 0; $x -lt $bmp.Width; $x += 5) {
        $pixel = $bmp.GetPixel($x, $y)
        # Check for whitish / grayish pixels that stand out from wood
        # Grayish pixels have R, G, B close to each other or relatively high brightness
        $diff = [Math]::Abs($pixel.R - $pixel.G) + [Math]::Abs($pixel.G - $pixel.B)
        if ($pixel.R -gt 130 -and $diff -lt 30) {
            Write-Host "Possible logo pixel at local ($x, $y) -> global ($($x+824), $($y+824)): R=$($pixel.R), G=$($pixel.G), B=$($pixel.B)"
        }
    }
}
$bmp.Dispose()

