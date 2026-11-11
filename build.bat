@echo off
echo ========================================================
echo Building Hermes Agent (Ultra-Lean Native Nim Edition)
echo Target: bin/hermes.exe (Memory Limit: < 50MB RAM)
echo ========================================================

if not exist "bin" mkdir "bin"

nim c -d:release -d:ssl --mm:orc --opt:speed -o:bin\hermes.exe src\main.nim
if %ERRORLEVEL% EQU 0 (
    echo.
    echo [SUCCESS] Compiled to bin\hermes.exe
    echo Run with: bin\hermes.exe
) else (
    echo.
    echo [ERROR] Build failed.
)
