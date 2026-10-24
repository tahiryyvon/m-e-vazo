$ErrorActionPreference = 'Stop'
$projectRoot = Split-Path -Parent $PSScriptRoot
$runtimePath = Join-Path $PSScriptRoot 'chordino-runtime'
$downloadPath = Join-Path $projectRoot 'build/chordino-downloads'
New-Item -ItemType Directory -Force $downloadPath, (Join-Path $runtimePath 'plugins') | Out-Null

function Get-VerifiedAsset($url, $destination, $sha256) {
  if (-not (Test-Path -LiteralPath $destination) -or
      (Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sha256) {
    Invoke-WebRequest -Uri $url -OutFile $destination
  }
  if ((Get-FileHash -LiteralPath $destination -Algorithm SHA256).Hash -ne $sha256) {
    throw "Checksum mismatch: $destination"
  }
}

$archive = Join-Path $downloadPath 'sonic-annotator-1.7-win64.zip'
Get-VerifiedAsset 'https://github.com/sonic-visualiser/sonic-annotator/releases/download/sonic-annotator-1.7/sonic-annotator-1.7-win64.zip' $archive 'C40717E029210CF1E1C97BC7DADEA00CF4386327E67FDF9CA66027A91EA26693'
Expand-Archive -LiteralPath $archive -DestinationPath $downloadPath -Force
New-Item -ItemType Directory -Force (Join-Path $runtimePath 'host') | Out-Null
Get-ChildItem -LiteralPath (Join-Path $downloadPath 'sonic-annotator-win64') | Copy-Item -Destination (Join-Path $runtimePath 'host') -Recurse -Force

$hashes = @{
  'nnls-chroma.dll' = 'BA0F3B35DCC77D5D48B65D72794E37A0DC1F97AA953E9E1DFDCCA7BC27D22AD9'
  'nnls-chroma.cat' = '10E53533341C68C372ECEF69FA542FE8530BAD1EE49C38295CC3E12721A64A17'
  'nnls-chroma.n3' = '71F6229C997058EA302E207241059E0753E4B42BE9F97429F34CEBD796421DE6'
  'COPYING' = '67F82E045CF7ACFEF853EA0F426575A8359161A0A325E19F02B529A87C4B6C34'
}
foreach ($name in $hashes.Keys) {
  Get-VerifiedAsset "https://github.com/jotapemj/nnls-chroma-win64/releases/download/v1.1-win64/$name" (Join-Path $runtimePath "plugins/$name") $hashes[$name]
}
Write-Output "Chordino installed locally: $runtimePath"
