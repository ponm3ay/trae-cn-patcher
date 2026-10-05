@echo off
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\trae-patcher.ps1" apply
pause
