@echo off
setlocal enabledelayedexpansion

echo ==========================================
echo   WireGuard Client Creator (Windows)
echo ==========================================
echo.

:: Request data from user.
set /p TUNNEL_NAME="1. Name of the new tunnel connection: "
set /p SERVER_PUBLICKEY="2. Public Key of the Server: "
set /p CLIENT_IP="3. Private IP for this client (ex. 10.0.0.2/24): "
set /p SERVER_PUBLIC_IP="4. Server public IP: "

:: Verify that the WireGuard tool exists.
set WIREGUARD_EXE="C:\Program Files\WireGuard\wg.exe"
if not exist %WIREGUARD_EXE% (
    echo.
    echo ERROR: 'wg.exe' not found in C:\Program Files\WireGuard\
    echo Ensure that WireGuard is installed ^(in the default path^).
    :: This will literally shows "Press any key to continue . . .".
    pause
    exit /b
)

:: Generate private and public keys.
%WIREGUARD_EXE% genkey > temp_private.key
%WIREGUARD_EXE% pubkey < temp_private.key > temp_public.key

:: Read the variables keys.
set /p PRIVATE_CLIENT_KEY=<temp_private.key
set /p PUBLIC_CLIENT_KEY=<temp_public.key

:: Create WireGuard configuration file .conf.
set CONF_FILE=%TUNNEL_NAME%.conf

echo [Interface] > "%CONF_FILE%"
echo PrivateKey = %PRIVATE_CLIENT_KEY% >> "%CONF_FILE%"
echo Address = %CLIENT_IP% >> "%CONF_FILE%"
echo DNS = 1.1.1.1 >> "%CONF_FILE%"
echo. >> "%CONF_FILE%"
echo [Peer] >> "%CONF_FILE%"
echo PublicKey = %SERVER_PUBLICKEY% >> "%CONF_FILE%"
echo AllowedIPs = 10.0.0.0/24 >> "%CONF_FILE%"
echo Endpoint = %SERVER_PUBLIC_IP%:51820 >> "%CONF_FILE%"

:: Clean the temporal files.
del temp_private.key
del temp_public.key

:: Show the final result.
echo.
echo ==========================================
echo %CONF_FILE% file created successfully!
echo ==========================================
echo.
echo The public key of the client is:
echo %PUBLIC_CLIENT_KEY%
echo.
echo 1. Create a file in 'keys_inbox' and put in there the public client^( '%PUBLIC_CLIENT_KEY%' ^) to register the client/peer in server ^(FileBrowser^).
echo 2. In WireGuard select 'Import tunnel from file' and select %CONF_FILE%.
echo.
pause