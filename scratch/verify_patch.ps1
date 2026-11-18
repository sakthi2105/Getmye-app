Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap("Getmye-main/Getmye-main/assets/banner_biryani_65_4x5.jpg")
$rect = New-Object System.Drawing.Rectangle 917, 916, 100, 100
$crop = $bmp.Clone($rect, $bmp.PixelFormat)
$crop.Save("patched_corner_preview.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$crop.Dispose()
Write-Host "Saved patched_corner_preview.png"

