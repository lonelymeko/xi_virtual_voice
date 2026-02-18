# All-in-One Windows Dependencies Installer
# Installs FFmpeg, NirCmd, and configures environment
# Encoding: UTF-8 without BOM

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter()]
    [string]$InstallPath = "$env:USERPROFILE\TTS_Tools",
    
    [Parameter()]
    [switch]$SystemWide,
    
    [Parameter()]
    [switch]$SkipFFmpeg,
    
    [Parameter()]
    [switch]$SkipNirCmd
)

# Set error handling
$ErrorActionPreference = "Stop"

# Color output functions
function Write-Info {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Green
}

function Write-Warning {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host $Message -ForegroundColor Red
}

# Title
Clear-Host
Write-Host ""
Write-Info "=============================================="
Write-Info "   TTS Virtual Voice - Windows Setup"
Write-Info "   All-in-One Dependencies Installer"
Write-Info "=============================================="
Write-Host ""

# Check admin rights
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

if ($SystemWide -and -not $isAdmin) {
    Write-Error "[ERROR] System-wide installation requires administrator rights"
    Write-Warning "[HINT] Right-click PowerShell and select 'Run as Administrator'"
    Write-Host ""
    Read-Host "Press Enter to exit"
    exit 1
}

if ($SystemWide) {
    $InstallPath = "C:\TTS_Tools"
}

Write-Host "Installation Plan:" -ForegroundColor White
Write-Host "  [Location] $InstallPath" -ForegroundColor Gray
Write-Host "  [Scope]    $(if ($SystemWide) {'System-wide (All Users)'} else {'Current User Only'})" -ForegroundColor Gray
Write-Host "  [FFmpeg]   $(if ($SkipFFmpeg) {'Skip'} else {'Install'})" -ForegroundColor Gray
Write-Host "  [NirCmd]   $(if ($SkipNirCmd) {'Skip'} else {'Install'})" -ForegroundColor Gray
Write-Host ""

$confirm = Read-Host "Continue? (y/n)"
if ($confirm -ne 'y') {
    Write-Warning "Installation cancelled"
    exit 0
}

# Create main installation directory
Write-Info "`n[Setup] Creating installation directory..."
if (-not (Test-Path $InstallPath)) {
    New-Item -ItemType Directory -Path $InstallPath -Force | Out-Null
    Write-Success "[OK] Directory created: $InstallPath"
} else {
    Write-Success "[OK] Directory exists: $InstallPath"
}

# Install FFmpeg
if (-not $SkipFFmpeg) {
    Write-Host ""
    Write-Info "=============================================="
    Write-Info "   Installing FFmpeg"
    Write-Info "=============================================="
    
    $ffmpegPath = Join-Path $InstallPath "ffmpeg"
    
    try {
        # Download FFmpeg
        Write-Info "[1/3] Downloading FFmpeg..."
        $downloadUrl = "https://github.com/BtbN/FFmpeg-Builds/releases/download/latest/ffmpeg-master-latest-win64-gpl.zip"
        $zipFile = "$env:TEMP\ffmpeg_setup.zip"
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $progressPreference = 'SilentlyContinue'
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
        
        Write-Success "[OK] Downloaded"
        
        # Extract
        Write-Info "[2/3] Extracting FFmpeg..."
        $tempExtract = "$ffmpegPath\temp"
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
        
        Expand-Archive -Path $zipFile -DestinationPath $tempExtract -Force
        
        $ffmpegFolder = Get-ChildItem -Path $tempExtract -Directory | Where-Object { $_.Name -like "ffmpeg-*" } | Select-Object -First 1
        
        if ($ffmpegFolder) {
            $binSource = Join-Path $ffmpegFolder.FullName "bin"
            $binDest = Join-Path $ffmpegPath "bin"
            
            if (Test-Path $binDest) {
                Remove-Item $binDest -Recurse -Force
            }
            Copy-Item $binSource -Destination $binDest -Recurse -Force
            
            Write-Success "[OK] Extracted"
        }
        
        # Cleanup
        if (Test-Path $tempExtract) {
            Remove-Item $tempExtract -Recurse -Force
        }
        if (Test-Path $zipFile) {
            Remove-Item $zipFile -Force
        }
        
        # Verify
        Write-Info "[3/3] Verifying FFmpeg..."
        $ffmpegExe = Join-Path $binDest "ffmpeg.exe"
        if (Test-Path $ffmpegExe) {
            $version = & $ffmpegExe -version 2>&1 | Select-Object -First 1
            Write-Success "[OK] FFmpeg installed: $version"
        } else {
            throw "ffmpeg.exe not found"
        }
        
    } catch {
        Write-Error "[FAIL] FFmpeg installation failed: $($_.Exception.Message)"
        Write-Warning "You may need to install FFmpeg manually"
    }
}

# Install NirCmd
if (-not $SkipNirCmd) {
    Write-Host ""
    Write-Info "=============================================="
    Write-Info "   Installing NirCmd"
    Write-Info "=============================================="
    
    $nircmdPath = Join-Path $InstallPath "nircmd"
    
    try {
        # Create directory
        if (-not (Test-Path $nircmdPath)) {
            New-Item -ItemType Directory -Path $nircmdPath -Force | Out-Null
        }
        
        # Download NirCmd
        Write-Info "[1/2] Downloading NirCmd..."
        
        if ([Environment]::Is64BitOperatingSystem) {
            $downloadUrl = "https://www.nirsoft.net/utils/nircmd-x64.zip"
        } else {
            $downloadUrl = "https://www.nirsoft.net/utils/nircmd.zip"
        }
        
        $zipFile = "$env:TEMP\nircmd_setup.zip"
        
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $downloadUrl -OutFile $zipFile -UseBasicParsing
        
        Write-Success "[OK] Downloaded"
        
        # Extract
        Write-Info "[2/2] Extracting NirCmd..."
        Expand-Archive -Path $zipFile -DestinationPath $nircmdPath -Force
        
        if (Test-Path $zipFile) {
            Remove-Item $zipFile -Force
        }
        
        # Verify
        $nircmdExe = Join-Path $nircmdPath "nircmd.exe"
        if (Test-Path $nircmdExe) {
            Write-Success "[OK] NirCmd installed"
        } else {
            throw "nircmd.exe not found"
        }
        
    } catch {
        Write-Error "[FAIL] NirCmd installation failed: $($_.Exception.Message)"
        Write-Warning "You may need to install NirCmd manually"
    }
}

# Configure Environment Variables
Write-Host ""
Write-Info "=============================================="
Write-Info "   Configuring Environment Variables"
Write-Info "=============================================="

if ($SystemWide) {
    $scope = "Machine"
} else {
    $scope = "User"
}

$currentPath = [Environment]::GetEnvironmentVariable("Path", $scope)
$pathsToAdd = @()

# Add FFmpeg to PATH
if (-not $SkipFFmpeg) {
    $ffmpegBin = Join-Path $InstallPath "ffmpeg\bin"
    if ($currentPath -notlike "*$ffmpegBin*") {
        $pathsToAdd += $ffmpegBin
        Write-Info "[+] Will add FFmpeg to PATH"
    } else {
        Write-Success "[OK] FFmpeg already in PATH"
    }
}

# Add NirCmd to PATH
if (-not $SkipNirCmd) {
    $nircmdPath = Join-Path $InstallPath "nircmd"
    if ($currentPath -notlike "*$nircmdPath*") {
        $pathsToAdd += $nircmdPath
        Write-Info "[+] Will add NirCmd to PATH"
    } else {
        Write-Success "[OK] NirCmd already in PATH"
    }
}

# Update PATH if needed
if ($pathsToAdd.Count -gt 0) {
    $newPath = $currentPath.TrimEnd(';')
    foreach ($path in $pathsToAdd) {
        $newPath += ";" + $path
    }
    
    [Environment]::SetEnvironmentVariable("Path", $newPath, $scope)
    
    # Update current session
    $machinePath = [Environment]::GetEnvironmentVariable("Path", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($machinePath -and $userPath) {
        $env:Path = $machinePath + ";" + $userPath
    } elseif ($machinePath) {
        $env:Path = $machinePath
    } else {
        $env:Path = $userPath
    }
    
    Write-Success "[OK] Environment variables updated"
} else {
    Write-Success "[OK] No PATH changes needed"
}

# Create .env template
Write-Host ""
Write-Info "=============================================="
Write-Info "   Creating Configuration Template"
Write-Info "=============================================="

$envTemplate = @"
# Aliyun TTS Configuration
# Get your credentials from: https://dashscope.console.aliyun.com/

# Required: Your Aliyun API Key
DASHSCOPE_API_KEY=your_api_key_here

# Optional: Model selection (default: cosyvoice-v1)
# Available models: cosyvoice-v1, sambert-zhichu-v1, etc.
# TTS_MODEL=cosyvoice-v1

# Optional: Voice selection (default: Cherry)
# Available voices: Cherry, Alex, William, Luna, etc.
# TTS_VOICE=Cherry

# Optional: Audio format (default: wav)
# Available formats: wav, mp3, pcm
# TTS_FORMAT=wav

# WebSocket Server Configuration (optional)
# Host address (default: localhost)
WS_HOST=localhost

# Port number (default: 7878)
WS_PORT=7878

# Path (default: /ws)
WS_PATH=/ws

# HTTP API Server Configuration (optional)
# Port number (default: 9091)
HTTP_PORT=9091

# Path (default: /api/tts)
HTTP_PATH=/api/tts
"@

$envFile = Join-Path (Get-Location) ".env"
if (-not (Test-Path $envFile)) {
    $envTemplate | Out-File -FilePath $envFile -Encoding UTF8
    Write-Success "[OK] Created .env template: $envFile"
    Write-Warning "[ACTION REQUIRED] Please edit .env and add your Aliyun API key"
} else {
    Write-Success "[OK] .env file already exists"
}

# Summary
Write-Host ""
Write-Info "=============================================="
Write-Success "   Installation Complete!"
Write-Info "=============================================="
Write-Host ""
Write-Host "[Install Location]" -ForegroundColor White
Write-Host "  $InstallPath" -ForegroundColor Gray
Write-Host ""
Write-Host "[Environment]" -ForegroundColor White
Write-Host "  Scope: $scope" -ForegroundColor Gray
Write-Host "  PATH: Updated" -ForegroundColor Gray
Write-Host ""

if (-not $SkipFFmpeg) {
    Write-Host "[FFmpeg]" -ForegroundColor White
    Write-Host "  Location: $InstallPath\ffmpeg\bin\ffmpeg.exe" -ForegroundColor Gray
    Write-Host "  Test: ffmpeg -version" -ForegroundColor Gray
    Write-Host ""
}

if (-not $SkipNirCmd) {
    Write-Host "[NirCmd]" -ForegroundColor White
    Write-Host "  Location: $InstallPath\nircmd\nircmd.exe" -ForegroundColor Gray
    Write-Host "  Test: nircmd speak text `"Hello`"" -ForegroundColor Gray
    Write-Host ""
}

Write-Host "[Configuration]" -ForegroundColor White
Write-Host "  .env file: $envFile" -ForegroundColor Gray
Write-Host ""
Write-Warning "[IMPORTANT]"
Write-Host "  1. Edit .env and add your Aliyun API key" -ForegroundColor Yellow
Write-Host "  2. Restart PowerShell/Terminal for PATH changes" -ForegroundColor Yellow
Write-Host "  3. Restart xi_virtual_voice application" -ForegroundColor Yellow
Write-Host ""

$openEnv = Read-Host "Open .env file in notepad now? (y/n)"
if ($openEnv -eq 'y') {
    Start-Process notepad $envFile
}

Write-Host ""
Write-Success "Setup completed successfully!"
Write-Host ""
Write-Host "Press Enter to exit..." -ForegroundColor Gray
Read-Host
