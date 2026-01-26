param(
  [string]$DbUrl = $env:SUPABASE_DB_URL,
  [string]$SchemaPath = (Join-Path $PSScriptRoot "..\supabase\schema.sql"),
  [string]$SeedPath = (Join-Path $PSScriptRoot "..\supabase\seed.sql")
)

$ErrorActionPreference = "Stop"

if (-not (Test-Path $SchemaPath)) {
  Write-Error "Schema file not found: $SchemaPath"
  exit 1
}

if (-not (Test-Path $SeedPath)) {
  Write-Error "Seed file not found: $SeedPath"
  exit 1
}

$SchemaPath = (Resolve-Path $SchemaPath).Path
$SeedPath = (Resolve-Path $SeedPath).Path

$ConfigPath = (Join-Path $PSScriptRoot "..\supabase\config.toml")
$ProjectRefPath = (Join-Path $PSScriptRoot "..\supabase\.temp\project-ref")
$MigrationsPath = (Join-Path $PSScriptRoot "..\supabase\migrations")
$HasConfig = Test-Path $ConfigPath
$HasLinkedProject = Test-Path $ProjectRefPath

$Supabase = Get-Command supabase -ErrorAction SilentlyContinue
if ($Supabase) {
  $SupportsExecute = $false
  $SupportsDbUrl = $false
  $SupportsPush = $false

  $DbHelp = & $Supabase.Path db --help 2>&1
  if ($LASTEXITCODE -eq 0) {
    if ($DbHelp -match "(?m)^\s*execute\b") {
      $SupportsExecute = $true
    }
    if ($DbHelp -match "(?m)^\s*push\b") {
      $SupportsPush = $true
    }
  }

  if ($SupportsExecute) {
    $ExecuteHelp = & $Supabase.Path db execute --help 2>&1
    if ($LASTEXITCODE -eq 0 -and $ExecuteHelp -match "--db-url") {
      $SupportsDbUrl = $true
    }
  }

  if ($SupportsExecute) {
    if ($SupportsDbUrl -and $DbUrl) {
      & $Supabase.Path db execute --db-url $DbUrl --file $SchemaPath
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & $Supabase.Path db execute --db-url $DbUrl --file $SeedPath
      exit $LASTEXITCODE
    }

    if ($HasConfig -or $HasLinkedProject) {
      & $Supabase.Path db execute --file $SchemaPath
      if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
      & $Supabase.Path db execute --file $SeedPath
      exit $LASTEXITCODE
    }
  }

  if ($SupportsPush -and ($HasConfig -or $HasLinkedProject) -and (Test-Path $MigrationsPath)) {
    & $Supabase.Path db push
    exit $LASTEXITCODE
  }

  if (-not $DbUrl -and -not $HasConfig -and -not $HasLinkedProject) {
    Write-Error "SUPABASE_DB_URL is required unless the project is linked. Run: supabase link --project-ref YOUR_REF"
    exit 1
  }
}

$Psql = Get-Command psql -ErrorAction SilentlyContinue
if (-not $Psql) {
  Write-Error "psql not found. Install PostgreSQL client tools or Supabase CLI."
  exit 1
}

& $Psql.Path $DbUrl -v ON_ERROR_STOP=1 -f $SchemaPath -f $SeedPath
exit $LASTEXITCODE
