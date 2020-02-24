$ErrorActionPreference = "Stop";
trap { $host.SetShouldExit(1) }

$ScriptPath = $MyInvocation.MyCommand.Path
$ScriptDirectory = Split-Path $ScriptPath -Parent


$ZlibDir = Join-Path $ScriptDirectory "zlib"
if (-Not (Test-Path $ZlibDir)) {
    Write-Error "Missing zlib"
}

$LibarchiveDir = Join-Path $ScriptDirectory "libarchive"
if (-Not (Test-Path $LibarchiveDir)) {
    Write-Error "Missing libarchive"
}

$LocalDir = Join-Path $ScriptDirectory "local"
if (Test-Path $LocalDir) {
    Remove-Item -Path $LocalDir -Recurse -Force
}

New-Item -Path $LocalDir -ItemType directory
foreach ($name in @("bin", "lib", "include")) {
    New-Item -Path (Join-Path $LocalDir $name) -ItemType directory
}

$LibDir = Join-Path $LocalDir "lib"
$IncludeDir = Join-Path $LocalDir "include"
Push-Location $ZlibDir
    C:\\var\\vcap\\packages\\mingw64\\mingw64\\bin\\mingw32-make.exe -f win32/Makefile.gcc
    if ($LASTEXITCODE -ne 0) {
        Write-Error "non-zero exit code (mingw32-make.exe -f win32/Makefile.gcc): ${LASTEXITCODE}"
    }
    # Copy header files to include dir
    foreach ($name in @("zconf.h", "zlib.h")) {
        Copy-Item -Path $name -Destination (Join-Path $IncludeDir $name)
    }
    # Copy library and DLL files to lib dir
    foreach ($name in @("libz.a", "libz.dll.a", "zlib1.dll")) {
        Copy-Item -Path $name -Destination (Join-Path $LibDir $name)
    }
    # Copy zlib1.dll to zlib.dll
    Copy-Item -Path "zlib1.dll" -Destination (Join-Path $LibDir "zlib.dll")
    Copy-Item -Path (Join-Path "win32" "zlib.def") -Destination (Join-Path $LibDir "zlib.def")
Pop-Location

# Tests will be tee'd to this log file
$LogFile = Join-Path $ScriptDirectory "test-log.txt"

$BuildDir = Join-Path $ScriptDirectory "build-libarchive"
New-Item -Path $BuildDir -ItemType directory
Push-Location $BuildDir
    # Configure
    C:\var\vcap\packages\cmake\bin\cmake.exe -G "MinGW Makefiles" -DENABLE_CAT:BOOL="0" -DENABLE_BZip2:BOOL="0" -DENABLE_CNG:BOOL="0" -DENABLE_CPIO:BOOL="0" `
        -DZLIB_INCLUDE_DIR:PATH="$IncludeDir" -DZLIB_LIBRARY_RELEASE:FILEPATH="$LibDir/libz.a" "$LibarchiveDir"
    if ($LASTEXITCODE -ne 0) {
        Write-Error "cmake: non-zero exit code: ${LASTEXITCODE}"
        Exit $LASTEXITCODE
    }

    # Build
    C:\\var\\vcap\\packages\\mingw64\\mingw64\\bin\\mingw32-make.exe -j 4
    if ($LASTEXITCODE -ne 0) {
        Write-Error "mingw32-make.exe: non-zero exit code: ${LASTEXITCODE}"
        Exit $LASTEXITCODE
    }

    # Test
    C:\\var\\vcap\\packages\\mingw64\\mingw64\\bin\\mingw32-make.exe -j 4 test | Tee-Object -FilePath $LogFile
Pop-Location

# We're able to pass every test. So we don't need this anymore
# Expected failures
# [hashtable]$expErrors = [ordered]@{
#     "*libarchive_test_entry (Failed)*" = $false
# }
#
# foreach ($line in Get-Content -Path $LogFile) {
#     foreach ($h in $expErrors.GetEnumerator()) {
#         if ($line -like $h.Key) {
#             $expErrors[$h.Key] = $true
#             break
#         }
#     }
# }
#
# foreach ($h in $expErrors.GetEnumerator()) {
#     if ($h.Value -eq $false) {
#         $err = ("Tests failed: {0}" -f $h.Key)
#         Write-Error $err
#     }
# }

$bsdTar = [System.IO.Path]::Combine($BuildDir, "bin", "bsdtar.exe")
$tarball = ("tar-{0}.exe" -f ([int][double]::Parse((Get-Date -UFormat %s))))
$outputTar = [System.IO.Path]::Combine("tar-output", $tarball)

# Capture the output in Concourse
Move-Item $bsdTar $outputTar

Exit 0
