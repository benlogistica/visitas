# ===================================================================
# validate-index.ps1
# Valida integridade do index.html antes de commit/push.
# Detecta truncagem (final do arquivo perdido), tags desbalanceadas, etc.
#
# Uso direto:
#   powershell -ExecutionPolicy Bypass -File scripts\validate-index.ps1
#
# Exit codes:
#   0 = OK (pode commitar)
#   1 = Falha (NAO commite - arquivo corrompido)
# ===================================================================

$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$file = Join-Path $repoRoot 'index.html'
$problems = New-Object System.Collections.ArrayList

function Add-Problem($msg) {
    [void]$problems.Add($msg)
}

# ---- 1. Existe e nao esta vazio --------------------------------------
if (-not (Test-Path $file)) {
    Write-Host "[ERRO] index.html nao existe!" -ForegroundColor Red
    exit 1
}
$info = Get-Item $file
if ($info.Length -lt 1MB) {
    Add-Problem ("Arquivo suspeitamente pequeno (" + [math]::Round($info.Length/1KB) + " KB) - esperado mais de 2 MB")
}

$content = Get-Content $file -Raw -Encoding UTF8

# ---- 2. Termina corretamente -----------------------------------------
$trimmed = $content.TrimEnd()
$endsOk = $trimmed.EndsWith('</html>')
if (-not $endsOk) {
    Add-Problem 'Arquivo NAO termina com tag de fechamento html - provavel truncagem!'
    $startIdx = [Math]::Max(0, $trimmed.Length - 80)
    $lastChars = $trimmed.Substring($startIdx)
    Add-Problem ('  Final atual: ...' + $lastChars)
}

# ---- 3. Tags de fechamento principais --------------------------------
if (-not $content.Contains('</body>')) { Add-Problem 'Faltando tag de fechamento body' }
if (-not $content.Contains('</html>')) { Add-Problem 'Faltando tag de fechamento html' }
if (-not $content.Contains('</script>')) { Add-Problem 'Faltando tag de fechamento script' }

# ---- 4. Pares de script abrindo/fechando balanceados -----------------
$opens  = ([regex]::Matches($content, '<script(\s[^>]*)?>')).Count
$closes = ([regex]::Matches($content, '</script>')).Count
if ($opens -ne $closes) {
    Add-Problem ('Tags script desbalanceadas: ' + $opens + ' abrem, ' + $closes + ' fecham')
}

# ---- 5. Funcoes criticas presentes -----------------------------------
if (-not ($content -match 'async\s+function\s+boot\s*\(')) {
    Add-Problem 'Funcao boot() nao encontrada (provavel truncagem)'
}
if (-not ($content -match "addEventListener\(['""]DOMContentLoaded['""]")) {
    Add-Problem 'Listener DOMContentLoaded nao encontrado (provavel truncagem)'
}

# ---- 6. APP_VERSION presente -----------------------------------------
$ver = [regex]::Match($content, "APP_VERSION:\s*'([^']+)'")
if (-not $ver.Success) {
    Add-Problem 'APP_VERSION nao encontrado em CONFIG'
}

# ---- 7. Tamanho nao encolheu drasticamente vs ultimo commit ----------
try {
    $headSizeStr = git -C $repoRoot cat-file -s "HEAD:index.html" 2>$null
    if ($LASTEXITCODE -eq 0 -and $headSizeStr) {
        $headSize = [int]$headSizeStr
        if ($headSize -gt 0) {
            $shrink = $headSize - $info.Length
            $shrinkPct = [math]::Round(100 * $shrink / $headSize, 1)
            if ($shrinkPct -gt 5) {
                Add-Problem ('Arquivo encolheu ' + $shrinkPct + '% vs ultimo commit (' + [math]::Round($info.Length/1KB) + ' KB vs ' + [math]::Round($headSize/1KB) + ' KB) - possivel truncagem')
            }
        }
    }
} catch {
    # Se git nao disponivel ou outro erro, pula essa checagem
}

# ---- Resultado --------------------------------------------------------
if ($problems.Count -eq 0) {
    Write-Host ''
    Write-Host '  [OK] index.html validado com sucesso' -ForegroundColor Green
    Write-Host ('       Tamanho: ' + [math]::Round($info.Length/1KB) + ' KB') -ForegroundColor DarkGray
    if ($ver.Success) {
        Write-Host ('       Versao:  ' + $ver.Groups[1].Value) -ForegroundColor DarkGray
    }
    Write-Host ''
    exit 0
}

Write-Host ''
Write-Host ('  [FALHA] index.html tem ' + $problems.Count + ' problema(s):') -ForegroundColor Red
Write-Host ''
foreach ($p in $problems) {
    Write-Host ('    - ' + $p) -ForegroundColor Yellow
}
Write-Host ''
Write-Host '  COMMIT BLOQUEADO. Corrija o arquivo antes de prosseguir.' -ForegroundColor Red
Write-Host '  Dica: para restaurar do ultimo commit, rode:' -ForegroundColor DarkGray
Write-Host '        git checkout HEAD -- index.html' -ForegroundColor DarkGray
Write-Host ''
exit 1
