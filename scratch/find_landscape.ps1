Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap("temp_landscape_corner.png")
for ($y = 0; $y -lt $bmp.Height; $y += 5) {
    for ($x = 0; $x -lt $bmp.Width; $x += 5) {
        $p = $bmp.GetPixel($x, $y)
        $diff = [Math]::Abs($p.R - $p.G) + [Math]::Abs($p.G - $p.B)
        if ($p.R -gt 135 -and $diff -lt 28) {
            Write-Host "Local ($x, $y) -> Global ($($x+1180), $($y+630)): R=$($p.R), G=$($p.G), B=$($p.B)"
        }
    }
}
$bmp.Dispose()

