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

# Once docker is starting, start llama-server
$llama = Get-Process -Name "llama-server" -ErrorAction SilentlyContinue
if (-not $llama) {
    Set-Location $env:LLAMA_BIN_DIR
    ./llama-server.exe --no-ui --port 42069 --host 127.0.0.1 --model ./Models/27B/Qwen3.8-27B-UD-Q4_K_S.gguf --alias "Qwen 3.8 27B (Small Context)" `
        --ctx-size 120000 --gpu-layers all --load-mode mmap+mlock --cache-type-k q8_0 --cache-type-v q8_0 --parallel 1 --kv-unified --flash-attn on --reasoning-budget 16000 --reasoning-preserve `
            --spec-type draft-mtp,ngram-simple --gpu-layers-draft 0 --spec-draft-n-max 2 --spec-ngram-mod-n-match 24 --spec-ngram-mod-n-min 48 --spec-ngram-mod-n-max 64 --cache-type-k-draft f16 --cache-type-v-draft f16 `
                --mmproj ./Models/Vision/mmproj-BF16.gguf --no-mmproj-offload
}