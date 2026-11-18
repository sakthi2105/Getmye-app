Add-Type -AssemblyName System.Drawing

$files = Get-ChildItem "Getmye-main/Getmye-main/assets/banner_biryani_65*.jpg"
foreach ($f in $files) {
    $bmp = New-Object System.Drawing.Bitmap($f.FullName)
    Write-Host "$($f.Name) size: $($bmp.Width)x$($bmp.Height)"
    
    # Check bottom-right region (last 10% of width and height)
    $minX = [int]($bmp.Width * 0.88)
    $minY = [int]($bmp.Height * 0.88)
    
    $found = 0
    for ($y = $minY; $y -lt $bmp.Height; $y += 3) {
        for ($x = $minX; $x -lt $bmp.Width; $x += 3) {
            $p = $bmp.GetPixel($x, $y)
            $diff = [Math]::Abs($p.R - $p.G) + [Math]::Abs($p.G - $p.B)
            if ($p.R -gt 135 -and $diff -lt 28) {
                $found++
            }
        }
    }
    Write-Host "  Found $found bright grayish pixels in $($f.Name)"
    $bmp.Dispose()
}

