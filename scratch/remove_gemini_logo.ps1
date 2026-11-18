Add-Type -AssemblyName System.Drawing

function Remove-GeminiLogo([string]$filePath) {
    Write-Host "Processing: $filePath"
    $bytes = [System.IO.File]::ReadAllBytes($filePath)
    $ms = New-Object System.IO.MemoryStream($bytes, 0, $bytes.Length)
    $bmp = [System.Drawing.Bitmap]::FromStream($ms)
    
    $w = $bmp.Width
    $h = $bmp.Height
    
    # Locate center of the watermark in bottom right
    $minX = [int]($w * 0.88)
    $minY = [int]($h * 0.88)
    
    $sumX = 0
    $sumY = 0
    $count = 0
    
    for ($y = $minY; $y -lt $h; $y++) {
        for ($x = $minX; $x -lt $w; $x++) {
            $p = $bmp.GetPixel($x, $y)
            $diff = [Math]::Abs($p.R - $p.G) + [Math]::Abs($p.G - $p.B)
            # Watermark pixels are grayish
            if ($p.R -gt 130 -and $diff -lt 28) {
                $sumX += $x
                $sumY += $y
                $count++
            }
        }
    }
    
    if ($count -eq 0) {
        Write-Host "  No logo found in $filePath"
        $bmp.Dispose()
        $ms.Dispose()
        return
    }
    
    $centerX = [int]($sumX / $count)
    $centerY = [int]($sumY / $count)
    Write-Host "  Logo center detected at ($centerX, $centerY), count=$count"
    
    # We patch a box around (centerX, centerY)
    $radius = 42
    $left = [Math]::Max(0, $centerX - $radius)
    $right = [Math]::Min($w - 1, $centerX + $radius)
    $top = [Math]::Max(0, $centerY - $radius)
    $bottom = [Math]::Min($h - 1, $centerY + $radius)
    
    # Source wood patch: horizontally shifted to the left by (2 * radius + 15)
    $offsetX = -($radius * 2 + 25)
    
    for ($y = $top; $y -le $bottom; $y++) {
        for ($x = $left; $x -le $right; $x++) {
            $dist = [Math]::Sqrt([Math]::Pow($x - $centerX, 2) + [Math]::Pow($y - $centerY, 2))
            if ($dist -lt $radius) {
                $srcX = $x + $offsetX
                $srcY = $y
                if ($srcX -ge 0 -and $srcX -lt $w) {
                    $srcPixel = $bmp.GetPixel($srcX, $srcY)
                    $origPixel = $bmp.GetPixel($x, $y)
                    
                    # Feather the blend at the edges of the circle
                    $featherStart = $radius - 10
                    $alpha = 1.0
                    if ($dist -gt $featherStart) {
                        $alpha = ($radius - $dist) / 10.0
                    }
                    
                    $newR = [int](($srcPixel.R * $alpha) + ($origPixel.R * (1.0 - $alpha)))
                    $newG = [int](($srcPixel.G * $alpha) + ($origPixel.G * (1.0 - $alpha)))
                    $newB = [int](($srcPixel.B * $alpha) + ($origPixel.B * (1.0 - $alpha)))
                    
                    $bmp.SetPixel($x, $y, [System.Drawing.Color]::FromArgb(255, $newR, $newG, $newB))
                }
            }
        }
    }
    
    # Save back with high quality JPEG
    $encoder = [System.Drawing.Imaging.ImageCodecInfo]::GetImageEncoders() | Where-Object { $_.FormatDescription -eq "JPEG" }
    $encoderParams = New-Object System.Drawing.Imaging.EncoderParameters(1)
    $encoderParams.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter([System.Drawing.Imaging.Encoder]::Quality, [long]95)
    
    $ms.Dispose()
    $bmp.Save($filePath, $encoder, $encoderParams)
    $bmp.Dispose()
    Write-Host "  Successfully patched $filePath"
}

$targetFiles = @(
    "Getmye-main/Getmye-main/assets/banner_biryani_65_4x5.jpg",
    "Getmye-main/Getmye-main/assets/banner_biryani_65.jpg",
    "Getmye-main/Getmye-main/assets/banner_biryani_65_landscape.jpg",
    "Getmye-main/Getmye-main/assets/banner_biryani_65_portrait.jpg"
)

foreach ($tf in $targetFiles) {
    if (Test-Path $tf) {
        Remove-GeminiLogo $tf
    }
}

