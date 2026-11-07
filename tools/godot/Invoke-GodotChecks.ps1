<#
.SYNOPSIS
  Gate di qualita del progetto Godot: validazione statica, test automatici, smoke test headless.

.DESCRIPTION
  1. --check-only su ogni script .gd del progetto (esclusi gli addon di terze parti in
     godot/addons: usano il nome globale dei propri autoload, che in --check-only non esiste);
  2. tutte le suite in godot/tests a 60 fps fissi;
  3. avvio headless dal menu iniziale con `-- --autostart` (passa subito al livello)
     e verifica dei marker attesi.
  Con -Executable verifica invece una build esportata (stessi marker, senza 1-2).
  Exit code 0 solo se tutto passa.
  Il seme delle run e fisso (-Seed, variabile PROTOTYPE01_SEED): un rosso si riproduce
  rilanciando con lo stesso seme; il log completo delle suite fallite resta in output/gate/.
  Una suite che stampa PASS senza errori ma non si chiude entro il timeout (blocco all'uscita
  di Godot) viene rilanciata una volta e giudicata sul secondo run; il primo log resta in
  output/gate/<suite>.exit-hang.log.
  Un passo con finestra (320x200) rilancia restyle_tests con Terrain3D vero e avvia il gioco
  contando anche gli errori degli shader; -NoWindow lo salta.

.EXAMPLE
  powershell -ExecutionPolicy Bypass -File tools/godot/Invoke-GodotChecks.ps1
  powershell -ExecutionPolicy Bypass -File tools/godot/Invoke-GodotChecks.ps1 -Executable LocalBuilds/Prototype01-Godot-Win64/Prototype01.exe
#>
param(
    [string]$Executable = "",
    # Seme delle run in tutte le suite (audit K-01): stesso seme, stesso esito.
    [int]$Seed = 20261014,
    # Salta il passo con finestra (macchina senza schermo).
    [switch]$NoWindow
)

$ErrorActionPreference = "Stop"
$repo = Resolve-Path (Join-Path $PSScriptRoot "..\..")
$project = Join-Path $repo "godot"
$godot = (Get-Command godot_console -ErrorAction Stop).Source
$env:PROTOTYPE01_SEED = "$Seed"
$failedLogs = Join-Path $repo "output\gate"
$failures = 0

$expectedMarkers = @(
    "PROTOTYPE01_MENU_READY",
    "PROTOTYPE01_SMOKE_TEST_OK",
    "PROTOTYPE01_INPUT_READY",
    "PROTOTYPE01_EXPOSURE_READY",
    "PROTOTYPE01_ARENA_READY",
    "PROTOTYPE01_TERRAIN_FIELD_READY",
    "PROTOTYPE01_CHARACTER_READY",
    "PROTOTYPE01_TERRAIN_MODE Dig",
    "PROTOTYPE01_CAMERA_READY",
    "PROTOTYPE01_CARAVAN_READY",
    "PROTOTYPE01_RUN_START",
    "PROTOTYPE01_PATH_FIELD_READY"
)

# Righe di errore runtime di Godot che non fanno fallire il gate, **per suite** (audit del
# 14 ottobre 2026, K-05): ogni voce vale solo nella suite che la provoca apposta, e negli
# smoke test non vale nulla. Aggiungerne una solo con il motivo accanto.
$allowedErrorPatterns = @{
    # P-09 (review 9 ottobre 2026): il renderer fittizio di --headless stampa
    # `Parameter "material" is null` quando la suite cambia preset grafico su mesh generate
    # senza materiale. Con finestra reale non compare.
    "settings_tests.gd" = @('Parameter "material" is null', 'ConfigFile parse error at user://settings_test_')
    # Audit S-02: la suite scrive apposta un profilo illeggibile per provarne il recupero.
    "workshop_tests.gd" = @('ConfigFile parse error at user://test_profile_recovery.cfg')
}

# Righe `SCRIPT ERROR` o `ERROR:` nell'output, tolte quelle ammesse per [suite] (U-03).
function Get-RuntimeErrors([string]$text, [string]$suite = "") {
    $allowed = @()
    if ($suite -and $allowedErrorPatterns.ContainsKey($suite)) { $allowed = $allowedErrorPatterns[$suite] }
    $lines = @($text -split "`n" | Where-Object { $_ -match "SCRIPT ERROR|SHADER ERROR|^ERROR:" })
    return @($lines | Where-Object {
        $line = $_
        -not ($allowed | Where-Object { $line -match [regex]::Escape($_) })
    })
}

function Invoke-Captured([string]$file, [string[]]$arguments, [int]$timeoutSeconds = 300) {
    # Processo separato con timeout: un test che non chiama quit() non deve
    # bloccare il gate per sempre (successo davvero, vedi GODOT_WORKFLOW.md).
    $outFile = [System.IO.Path]::GetTempFileName()
    $errFile = [System.IO.Path]::GetTempFileName()
    $quoted = $arguments | ForEach-Object { if ($_ -match '\s') { '"' + $_ + '"' } else { $_ } }
    $process = Start-Process -FilePath $file -ArgumentList $quoted -NoNewWindow -PassThru `
        -RedirectStandardOutput $outFile -RedirectStandardError $errFile
    # PowerShell 5.1: senza aprire subito l'handle, ExitCode resta vuoto dopo l'uscita.
    $null = $process.Handle
    $finished = $process.WaitForExit($timeoutSeconds * 1000)
    if (-not $finished) {
        # Il launcher godot_console avvia un processo figlio: chiudere l'albero intero.
        # Niente redirezione di stderr: con $ErrorActionPreference = "Stop" un
        # processo gia uscito farebbe abortire il gate invece di riportare TIMEOUT (U-15).
        try { & taskkill /F /T /PID $process.Id | Out-Null } catch { }
    }
    $text = ((Get-Content $outFile -Raw) + "`n" + (Get-Content $errFile -Raw))
    Remove-Item $outFile, $errFile -ErrorAction SilentlyContinue
    if (-not $finished) {
        return @{ Code = 124; Text = "TIMEOUT dopo $timeoutSeconds s`n$text" }
    }
    return @{ Code = $process.ExitCode; Text = $text }
}

function Test-Markers([string]$text) {
    $missing = @($expectedMarkers | Where-Object { $marker = $_; -not ($marker -split '\|' | Where-Object { $text.Contains($_) }) })
    $errors = Get-RuntimeErrors $text
    if ($missing.Count -gt 0) { Write-Host "  FAIL marker mancanti: $($missing -join ', ')" }
    if ($errors.Count -gt 0) { Write-Host "  FAIL errori runtime:`n$($errors -join "`n")" }
    return ($missing.Count -eq 0 -and $errors.Count -eq 0)
}

if ($Executable) {
    Write-Host "== smoke test build: $Executable"
    $run = Invoke-Captured (Resolve-Path $Executable) @("--headless", "--quit-after", "180", "--", "--autostart")
    if (Test-Markers $run.Text) { Write-Host "  ok   tutti i marker presenti" } else { $failures++ }
    # Audit K-06: un crash all'uscita o un blocco dopo i marker non e un verde.
    if ($run.Code -ne 0) { Write-Host "  FAIL codice d'uscita $($run.Code)"; $failures++ }
    if ($failures -eq 0) { Write-Host "GODOT_CHECKS PASS" } else { Write-Host "GODOT_CHECKS FAIL" }
    exit [int]($failures -gt 0)
}

Write-Host "== check-only"
Get-ChildItem -Path $project -Recurse -Filter *.gd | Where-Object { $_.FullName -notmatch "\\\.godot\\|\\addons\\" } | ForEach-Object {
    $resPath = "res://" + $_.FullName.Substring($project.Length + 1).Replace("\", "/")
    $result = Invoke-Captured $godot @("--headless", "--path", "$project", "--check-only", "--script", $resPath)
    if ($result.Code -ne 0) {
        $failures++
        Write-Host "  FAIL $resPath`n$($result.Text)"
    } else {
        Write-Host "  ok   $resPath"
    }
}

Write-Host "== test suites"
$exitHangLogs = @()
Get-ChildItem -Path (Join-Path $project "tests") -Filter *.gd | ForEach-Object {
    $resPath = "res://tests/" + $_.Name
    $suiteArgs = @("--headless", "--path", "$project", "--fixed-fps", "60", "--script", $resPath)
    $result = Invoke-Captured $godot $suiteArgs
    # Una suite verde che scatena un errore runtime non asserito e comunque FAIL (U-03).
    $errors = Get-RuntimeErrors $result.Text $_.Name
    # Blocco all'uscita di Godot (GODOT_WORKFLOW.md, trappola del 16 ottobre 2026): PASS
    # stampato, nessun errore runtime, ma il processo non si chiude entro il timeout. Solo
    # in questo caso la suite si rilancia, una volta, e conta il secondo run.
    $hangLog = ""
    if ($result.Code -eq 124 -and $result.Text.Contains("PROTOTYPE01_TESTS PASS") -and $errors.Count -eq 0) {
        New-Item -ItemType Directory -Force $failedLogs | Out-Null
        $hangLog = Join-Path $failedLogs ($_.BaseName + ".exit-hang.log")
        Set-Content -Path $hangLog -Value $result.Text -Encoding utf8
        $exitHangLogs += $hangLog
        Write-Host "  RETRY $resPath ha stampato PASS ma non si e chiusa entro il timeout: la rilancio una volta"
        $result = Invoke-Captured $godot $suiteArgs
        $errors = Get-RuntimeErrors $result.Text $_.Name
    }
    $summary = ($result.Text -split "`n" | Where-Object { $_ -match "PROTOTYPE01_TESTS" }) -join ""
    if ($result.Code -ne 0 -or -not $summary.Contains("PASS") -or $errors.Count -gt 0) {
        $failures++
        Write-Host "  FAIL $resPath (exit $($result.Code), errori runtime $($errors.Count))"
        $result.Text -split "`n" | Where-Object { $_ -match "FAIL|TIMEOUT|PROTOTYPE01_RUN_START" } | ForEach-Object { Write-Host "       $_" }
        $errors | ForEach-Object { Write-Host "       $_" }
        # Audit K-02: il log intero resta per riprodurre il rosso.
        New-Item -ItemType Directory -Force $failedLogs | Out-Null
        $logFile = Join-Path $failedLogs ($_.BaseName + ".log")
        Set-Content -Path $logFile -Value $result.Text -Encoding utf8
        Write-Host "       log completo: $logFile (seme $Seed)"
        if ($hangLog) { Write-Host "       il primo run si era bloccato all'uscita dopo PASS: $hangLog" }
    } else {
        $note = ""
        if ($hangLog) { $note = " (verde al rilancio dopo un blocco all'uscita)" }
        Write-Host "  ok   $resPath $summary$note"
    }
}

# Audit K-03: in headless Terrain3D non esiste e gli shader non si compilano; qui la suite
# con i controlli su Terrain3D e un avvio vero, a finestra piccola.
if (-not $NoWindow) {
    Write-Host "== con finestra (Terrain3D e shader)"
    $win = Invoke-Captured $godot @("--path", "$project", "--resolution", "320x200", "--fixed-fps", "60", "--script", "res://tests/restyle_tests.gd")
    $winErrors = Get-RuntimeErrors $win.Text
    if ($win.Code -ne 0 -or -not $win.Text.Contains("PROTOTYPE01_TESTS PASS") -or $win.Text.Contains("skip controlli Terrain3D") -or $winErrors.Count -gt 0) {
        $failures++
        Write-Host "  FAIL restyle_tests con finestra (exit $($win.Code), errori $($winErrors.Count))"
        $win.Text -split "`n" | Where-Object { $_ -match "FAIL|skip" } | ForEach-Object { Write-Host "       $_" }
        $winErrors | ForEach-Object { Write-Host "       $_" }
    } else {
        Write-Host "  ok   restyle_tests con finestra"
    }
    $start = Invoke-Captured $godot @("--path", "$project", "--resolution", "320x200", "--quit-after", "300", "--", "--autostart")
    if (Test-Markers $start.Text) { Write-Host "  ok   avvio con finestra: marker presenti, nessun errore" } else { $failures++ }
    if ($start.Code -ne 0) { Write-Host "  FAIL codice d'uscita $($start.Code)"; $failures++ }
}

Write-Host "== smoke test headless"
$run = Invoke-Captured $godot @("--headless", "--path", "$project", "--quit-after", "180", "--", "--autostart")
if (Test-Markers $run.Text) { Write-Host "  ok   tutti i marker presenti" } else { $failures++ }
if ($run.Code -ne 0) { Write-Host "  FAIL codice d'uscita $($run.Code)"; $failures++ }

if ($exitHangLogs.Count -gt 0) {
    # Solo i log di questo giro: quelli dei giri precedenti restano nella cartella.
    Write-Host "NOTA suite rilanciate dopo un blocco all'uscita: $($exitHangLogs.Count); log del primo run: $($exitHangLogs -join ', ')"
}
if ($failures -eq 0) { Write-Host "GODOT_CHECKS PASS" } else { Write-Host "GODOT_CHECKS FAIL ($failures)" }
exit [int]($failures -gt 0)
