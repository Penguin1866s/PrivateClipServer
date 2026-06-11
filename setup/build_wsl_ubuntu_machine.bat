@echo off
setlocal enabledelayedexpansion

REM To commente the lines I use the 'REM' command and not the '::' because the '::' command is not a real comment, it is a label that is used to jump to other parts of the script, and if I use it in the middle of the script, it can cause problems with the flow of the script.

REM Change the directory to the directory where the script is located.
cd /d "%~dp0"

REM Check if the script is running with administrator privileges
REM Search the administrator code in the current group user's
whoami /groups | find "S-1-16-12288" >nul
REM The goto is to jump to the :isAdmin label in the script.
if %errorlevel% == 0 goto :isAdmin

echo [WARNING] You are not an Administrator.
echo [INFO] Requesting administrator privileges...
powershell -Command "Start-Process -FilePath '%~s0' -Verb RunAs"
REM pause
exit /b

:isAdmin
echo [OK] Running with administrator privileges.

echo.
echo ==========================================
echo CHANGE THE IP OF THE PHYSICAL MACHINE
echo ==========================================
REM change the ip of your fisical machine to 192.168.1.50/24 with dns server 1.1.1.1 and with gateway 192.168.1.1
echo.
REM View what interfaces are active, choose you one
netsh interface show interface
set /p INTERFACE_TO_CHANGE="View what interfaces are active, choose you one(Ethernet or Wi-Fi): "

REM Change the values of the interface selected
REM The "/I" in the if statement is to ignore the case sensitivity(not distinguish between uppercase and lowercase letters).
if /i "%INTERFACE_TO_CHANGE%"=="Ethernet" (
    set "INTERFACE_TO_CHANGE_modified=Ethernet Ethernet:"
) else if /i "%INTERFACE_TO_CHANGE%"=="Wi-Fi" (
    set "INTERFACE_TO_CHANGE_modified=Wi-Fi"
)
echo.
echo View the interface configuration.
for /f "tokens=1 delims=[]" %%A in ('ipconfig ^| find /n "%INTERFACE_TO_CHANGE_modified%"') do set "NUMBER_LINE_IPCONFIG_INTERFACE=%%A"
REM 'delimits=[]', the characters that use to delimit what is searching.
REM the '^' of 'ipconfig ^' is to say that the command is 'ipconfig' and the '|', is to continue with the next command(this is necessary in the for loop).
REM 'ipconfig ^| find /n "Ethernet Ethernet:"' to obtain the line where it coincides the "Ethernet Ethernet:" text, with the value of line number.

REM the use of '!!' instead of '%%' is for force the evaluation of the variable in the moment of the execution of that line(is necessary in windows batch scripts).
set /a NUMBER_LINE_IPCONFIG_INTERFACE_minus_one=!NUMBER_LINE_IPCONFIG_INTERFACE!-1
ipconfig | more +!NUMBER_LINE_IPCONFIG_INTERFACE_minus_one! | findstr /n "^" | findstr "^[1-8]:"

REM 1 Search line of ipv4
for /f "tokens=1 delims=:" %%A in ('ipconfig ^| more +!NUMBER_LINE_IPCONFIG_INTERFACE_minus_one! ^| findstr /n "^^" ^| findstr "^^[1-8]:" ^| findstr /i "IPv4"') do set "REL_IPV4_LINE=%%A"

REM 2 Assign the values of the lines where there are the values that we will search in the next for loop, to grep the searched values.
REM The /a is for make arithmetic operations.
set /a REL_MASK_LINE=!REL_IPV4_LINE! + 1
set /a REL_GW_LINE=!REL_IPV4_LINE! + 2

REM Obtains the values of what is after the ":" character, the results they are divided between 1 2 and * tokens(A%%,B%%,C%%).
for /f "tokens=1,2,* delims=:" %%A in ('ipconfig ^| more +!NUMBER_LINE_IPCONFIG_INTERFACE_minus_one! ^| findstr /n "^^"') do (
    if "%%A"=="!REL_IPV4_LINE!" set "ipv4_address=%%C"
    if "%%A"=="!REL_MASK_LINE!" set "subnet_mask=%%C"
    if "%%A"=="!REL_GW_LINE!" set "default_gateway=%%C"
)

REM Clean the spaces, substitute the " "(space character), for what is between the = and the !, in the end of the line, in this case, substiute, for nothing.
if not "!ipv4_address!"=="" set "ipv4_address=!ipv4_address: =!"
if not "!subnet_mask!"=="" set "subnet_mask=!subnet_mask: =!"
if not "!default_gateway!"=="" set "default_gateway=!default_gateway: =!"

echo.
echo Extracted values
echo ----------------------------------------
echo Value IPv4 address: !ipv4_address!
echo Value network mask: !subnet_mask!
echo Value gateway: !default_gateway!
echo ----------------------------------------
echo.
if "!ipv4_address!"=="192.168.1.50" if "!subnet_mask!"=="255.255.255.0" if "!default_gateway!"=="192.168.1.1" (
    echo [INFO]: The interface %INTERFACE_TO_CHANGE% already has the 192.168.1.50 ipv4 address, the 255.255.255.0 mask and the 192.168.1.1 gateway.
) else (
    echo Change the ip of the interface selected
    netsh interface ipv4 set address name="%INTERFACE_TO_CHANGE%" static 192.168.1.50 255.255.255.0 192.168.1.1
    REM The "validate=no" is for avoid Windows testing the DNS connection and throwing a warning.
    netsh interface ipv4 set dnsservers name="%INTERFACE_TO_CHANGE%" static 1.1.1.1 primary validate=no
)
echo [INFO]This pause is to give time to configure the network.
pause
echo.
echo ===============================================
echo CREATE A WSL MACHINE FOR THE PRIVATECLIPSERVER
echo ===============================================

echo To run this in a wsl machine:
echo.
echo (1) download the ubuntu image machine
echo [IMPORTANT] AN Ubuntu-22.04 wsl machine will be installed. A new window will open.
echo (1.1) Wait until it asks you to create a UNIX username and password.
echo (1.2) After that, write "exit" in the terminal
echo.
wsl --install -d Ubuntu-22.04
echo.

echo (2)  see actual machines wsl
wsl -l -v
echo.

echo (3) stop wsl machines
wsl --shutdown
wsl -l -v
echo.

echo (4) for security export wsl machine to a .tar file in "%USERPROFILE%\Documents\Snapshot_ubuntu_22_04.tar".
wsl --export Ubuntu-22.04 "%USERPROFILE%\Documents\Snapshot_ubuntu_22_04.tar"

REM Additional:delete wsl machine
REM wsl --unregister Ubuntu-22.04

REM Additional: import wsl machine from a .tar file
REM wsl --import Ubuntu-22.04 "%USERPROFILE%\Documents\Snapshot_ubuntu_22_04.tar"

REM for forwarding the requests of the main machine ip to the wsl machine.
echo.
echo (5) Create the .wslconfig file to forward the requests of the main machine ip to the wsl machine.
echo [wsl2] > "%USERPROFILE%\.wslconfig"
echo networkingMode=mirrored >> "%USERPROFILE%\.wslconfig"
echo. >> "%USERPROFILE%\.wslconfig"
echo [experimental] >> "%USERPROFILE%\.wslconfig"
echo hostAddressLoopback=true >> "%USERPROFILE%\.wslconfig"
echo.

echo (6) Add rules in the firewall to allow the traffic from the main machine to the wsl machine.
powershell -Command "New-NetFirewallRule -DisplayName 'PrivateClipServer_Web' -Direction Inbound -LocalPort 8080 -Protocol TCP -Action Allow -Profile Any"
powershell -Command "New-NetFirewallRule -DisplayName 'PrivateClipServer_VPN' -Direction Inbound -LocalPort 51820 -Protocol UDP -Action Allow -Profile Any"
REM Additional: To delete the rules in the firewall, you can use the following commands:
REM powershell -Command "Remove-NetFirewallRule -DisplayName 'PrivateClipServer_Web'"
REM powershell -Command "Remove-NetFirewallRule -DisplayName 'PrivateClipServer_VPN'"
echo.

echo (7) Start the wsl machine.
wsl -d Ubuntu-22.04 -- bash -c "sudo apt update && sudo apt install -y docker-compose-v2"
echo.

echo And here, is where you can continue with the instructions of the README.md file to install the privateclipserver in the wsl machine.
echo Thanks for using the script, if is useful for you, please consider to give a star to the project in github.
pause

REM Additional: To clean the wsl machine, you can use the following command:
REM wsl --unregister Ubuntu-22.04
REM to delete the .wslconfig file and the .tar file, you can use the following commands:
REM del "%USERPROFILE%\.wslconfig"
REM del "%USERPROFILE%\Documents\Snapshot_ubuntu_22_04.tar"

REM Additional: To change the configuration of your phisical machine to the original configuration, you can use the following commands:
REM (%INTERFACE_TO_CHANGE% = 'Ethernet' or 'Wi-Fi')
REM netsh interface ipv4 set address name="%INTERFACE_TO_CHANGE%" dhcp
REM netsh interface ipv4 set dnsservers name="%INTERFACE_TO_CHANGE%" dhcp primary