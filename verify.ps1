$content = [System.IO.File]::ReadAllText('world.gd', [System.Text.Encoding]::UTF8)
$lines = $content -split "`n"

Write-Host "=== Apex logic (L800-835) ==="
for ($i = 799; $i -lt 835; $i++) {
    $line = $lines[$i]
    $tabs = ($line -replace '[^\t].*', '').Length
    Write-Host "L$($i+1) [$tabs]: $line"
}

Write-Host "`n=== Predator logic (L659-725) ==="
for ($i = 658; $i -lt 725; $i++) {
    $line = $lines[$i]
    $tabs = ($line -replace '[^\t].*', '').Length
    Write-Host "L$($i+1) [$tabs]: $line"
}

# Check no duplicate bare 'var diff' or 'var step' remain
$diffCount = ($content -split "`n" | Where-Object { $_ -match '^\s+var diff[^_]' }).Count
$stepCount = ($content -split "`n" | Where-Object { $_ -match '^\s+var step[^_]' }).Count
Write-Host "`nBare 'var diff' count: $diffCount"
Write-Host "Bare 'var step' count: $stepCount"
