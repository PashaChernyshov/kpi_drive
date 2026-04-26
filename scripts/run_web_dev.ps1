[CmdletBinding()]
param()

$ErrorActionPreference = "Stop"

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$projectRoot = Split-Path -Parent $scriptDir
$proxyUrl = "http://127.0.0.1:8787"
$proxyPath = "/_api/indicators/get_mo_indicators"
$pidFile = Join-Path $projectRoot ".dart_tool\kpi_drive_proxy.pid"
$proxyStdoutLog = Join-Path $projectRoot ".dart_tool\kpi_drive_proxy.stdout.log"
$proxyStderrLog = Join-Path $projectRoot ".dart_tool\kpi_drive_proxy.stderr.log"
$dartCommand = Get-Command dart -ErrorAction Stop
$proxyProcess = $null
$startedByScript = $false

function Read-TokenFromEnvLocal {
    param([string]$FilePath)

    if (-not (Test-Path $FilePath)) {
        throw ".env.local not found. Create .env.local from .env.example."
    }

    $line = Get-Content $FilePath | Where-Object { $_ -match '^KPI_DRIVE_TOKEN=' } | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($line)) {
        throw "KPI_DRIVE_TOKEN is missing in .env.local."
    }

    return $line.Substring("KPI_DRIVE_TOKEN=".Length).Trim()
}

function Test-ProxyReady {
    try {
        $response = Invoke-WebRequest -Uri "$proxyUrl$proxyPath" -Method Options -UseBasicParsing -TimeoutSec 2
        return $response.StatusCode -eq 204
    }
    catch {
        return $false
    }
}

function Get-PortOwner {
    $connection = Get-NetTCPConnection -LocalPort 8787 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $connection) {
        return $null
    }

    $process = Get-Process -Id $connection.OwningProcess -ErrorAction SilentlyContinue
    return [PSCustomObject]@{
        ProcessId   = $connection.OwningProcess
        ProcessName = if ($null -ne $process) { $process.ProcessName } else { "unknown" }
    }
}

function Stop-KnownProxyIfAny {
    if (-not (Test-Path $pidFile)) {
        return
    }

    $knownPid = Get-Content $pidFile | Select-Object -First 1
    if ([string]::IsNullOrWhiteSpace($knownPid)) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
        return
    }

    $process = Get-Process -Id ([int]$knownPid) -ErrorAction SilentlyContinue
    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 600
    }

    Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
}

$token = Read-TokenFromEnvLocal -FilePath (Join-Path $projectRoot ".env.local")

try {
    Stop-KnownProxyIfAny

    $portOwner = Get-PortOwner
    if ($null -ne $portOwner) {
        if ($portOwner.ProcessName -in @("dart", "dartvm", "dartaotruntime")) {
            Write-Host "Найден старый dev-proxy на 8787, PID $($portOwner.ProcessId)"
            Stop-Process -Id $portOwner.ProcessId -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 2

            $portOwner = Get-PortOwner
            if ($null -ne $portOwner) {
                throw "Порт 8787 не освободился после остановки старого dev-proxy. PID $($portOwner.ProcessId)."
            }

            Write-Host "Старый dev-proxy остановлен"
        }
        else {
            throw "Порт 8787 занят другим процессом: $($portOwner.ProcessName) PID $($portOwner.ProcessId). Остановите его вручную."
        }
    }

    if (-not (Test-ProxyReady)) {
        Write-Host "Запускаю dev-proxy..."

        New-Item -ItemType Directory -Path (Split-Path $pidFile -Parent) -Force | Out-Null
        Remove-Item $proxyStdoutLog, $proxyStderrLog -Force -ErrorAction SilentlyContinue

        $proxyProcess = Start-Process `
            -FilePath $dartCommand.Source `
            -ArgumentList @("run", "bin/dev_proxy.dart", "--token", $token) `
            -WorkingDirectory $projectRoot `
            -WindowStyle Hidden `
            -RedirectStandardOutput $proxyStdoutLog `
            -RedirectStandardError $proxyStderrLog `
            -PassThru

        $startedByScript = $true
        Set-Content -Path $pidFile -Value $proxyProcess.Id

        for ($i = 0; $i -lt 20; $i++) {
            Start-Sleep -Milliseconds 500
            if (Test-ProxyReady) {
                break
            }
            if ($proxyProcess.HasExited) {
                $stderr = if (Test-Path $proxyStderrLog) { Get-Content $proxyStderrLog -Raw } else { "" }
                $stdout = if (Test-Path $proxyStdoutLog) { Get-Content $proxyStdoutLog -Raw } else { "" }
                throw "Proxy exited during startup. $stderr $stdout"
            }
        }

        if (-not (Test-ProxyReady)) {
            throw "Proxy did not become ready at $proxyUrl"
        }
    }

    Write-Host "Запускаю Flutter Web..."
    Write-Host "Логи proxy: $proxyStdoutLog"
    flutter run -d chrome --dart-define=KPI_DRIVE_API_BASE_URL=$proxyUrl
}
finally {
    if ($startedByScript -and $null -ne $proxyProcess -and -not $proxyProcess.HasExited) {
        Write-Host "Stopping local proxy"
        Stop-Process -Id $proxyProcess.Id -Force
    }
    if ($startedByScript -and (Test-Path $pidFile)) {
        Remove-Item $pidFile -Force -ErrorAction SilentlyContinue
    }
}
