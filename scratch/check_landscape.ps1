Add-Type -AssemblyName System.Drawing

$bmp = New-Object System.Drawing.Bitmap("Getmye-main/Getmye-main/assets/banner_biryani_65_landscape.jpg")
$rect = New-Object System.Drawing.Rectangle 1180, 630, 180, 130
$crop = $bmp.Clone($rect, $bmp.PixelFormat)
$crop.Save("temp_landscape_corner.png", [System.Drawing.Imaging.ImageFormat]::Png)
$bmp.Dispose()
$crop.Dispose()
Write-Host "Saved temp_landscape_corner.png"

