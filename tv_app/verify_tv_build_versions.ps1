$ErrorActionPreference = "Stop"
Write-Host "=== settings.gradle.kts ==="
Select-String -Path ".\android\settings.gradle.kts" -Pattern 'com.android.application'
Write-Host ""
Write-Host "=== gradle-wrapper.properties ==="
Select-String -Path ".\android\gradle\wrapper\gradle-wrapper.properties" -Pattern 'distributionUrl'
Write-Host ""
Write-Host "=== gradle.properties ==="
Select-String -Path ".\android\gradle.properties" -Pattern 'kotlin.compiler.execution.strategy|android.newDsl|android.builtInKotlin'
