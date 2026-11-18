Add-Type -AssemblyName System.Drawing

$srcPath = "Getmye-main/Getmye-main/assets/banner_biryani_65_4x5.jpg"
$bmp = New-Object System.Drawing.Bitmap($srcPath)
Write-Host "Width: $($bmp.Width), Height: $($bmp.Height)"

# Crop bottom right corner
$rect = New-Object System.Drawing.Rectangle 824, 824, 200, 200
$crop = $bmp.Clone($rect, $bmp.PixelFormat)
$crop.Save("temp_corner.png", [System.Drawing.Imaging.ImageFormat]::Png)

$bmp.Dispose()
$crop.Dispose()
Write-Host "Done"

