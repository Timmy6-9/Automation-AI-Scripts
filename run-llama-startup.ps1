# Check time and day of week to make up for task scheduler's lack of options 
$now = Get-Date

if ($now.DayOfWeek -in 'Monday','Tuesday','Wednesday','Thursday' -and $now.Hour -ge 8 -and $now.Hour -lt 17) {
    Write-Host "Within allowed window - continuing."
}
else {
    Write-Host "Outside allowed window (Mon-Thu, 8am-5pm) - exiting."
    Stop-Process -Id $PID
}

Set-Location $PSScriptRoot

# Parse all values in .env
$env_vars = Get-Content .env |
    Where-Object { $_ -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$' } |
    ForEach-Object {
        $name = $Matches[1]
        $value = $Matches[2].Trim('""''')   # strip surrounding quotes
        [PSCustomObject]@{ Name = $name; Value = $value }
        Set-Item -Path "env:$($name)" -Value $value
    }
    
$env_vars | Format-Table -AutoSize

# Start docker if not already running (For open webui as extensible frontend & searxng as web search)
$docker = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
if (-not $docker) {

    Start-Process -FilePath $env:DOCKER_EXECUTABLE

    # Wait for docker to be ready
    $waited = 0
    $timeout = 60

    while (-not $docker -and $waited -lt $timeout) {
        Start-Sleep -Seconds 10
        $waited++
        Write-Output "Waited $waited Seconds"
        $docker = Get-Process -Name "Docker Desktop" -ErrorAction SilentlyContinue
    }

    if (-not $docker) {
        Write-Error "Docker Desktop did not start within $timeout seconds"
        exit 1
    }

}

# If docker does load, run compose.yaml
docker compose up -d

Set-Location -LiteralPath $env:FF_EXECUTABLE
# Firefox will automatically open these in the same window on different tabs so no need for anything fancy
./firefox.exe http://127.0.0.1:3333
./firefox.exe https://mail.google.com/mail/u/1/#inbox
./firefox.exe https://calendar.google.com/calendar/u/1/r
./firefox.exe $env:WORK_GH_REPO
./firefox.exe $env:WORK_JIRA

# Start llama server, check that it needs starting first | We want it running on terminal so that output is printed
$llamaScript = @'
$llama = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue
if (-not $llama) {
    Set-Location -Path $env:LLAMA_BIN_DIR
    ./llama-server.exe --no-ui --port 42069 --host 127.0.0.1 --model ./Models/27B/Qwen3.8-27B-UD-Q4_K_S.gguf --alias "Qwen 3.8 27B" `
        --ctx-size 120000 --gpu-layers all --load-mode mmap+mlock --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --kv-unified --flash-attn on --reasoning-budget 16000 --reasoning-preserve `
            --spec-type draft-mtp,ngram-simple --gpu-layers-draft 0 --spec-draft-n-max 2 --spec-ngram-mod-n-match 24 --spec-ngram-mod-n-min 48 --spec-ngram-mod-n-max 64 --cache-type-k-draft f16 --cache-type-v-draft f16 `
                --mmproj ./Models/Vision/mmproj-BF16.gguf --no-mmproj-offload
}
'@

$llamaScriptPath = Join-Path $env:TEMP 'llama_server.ps1'

Set-Content -Path $llamaScriptPath -Value $llamaScript -Encoding UTF8

wt.exe -w 0 new-tab --title "Llama Server" powershell -NoExit -File "$llamaScriptPath"

Exit-PSSession