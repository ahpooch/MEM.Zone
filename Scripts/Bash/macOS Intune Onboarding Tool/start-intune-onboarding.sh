#!/bin/bash
#set -x

#.SYNOPSIS
#    Starts Intune onboarding.
#.DESCRIPTION
#    Starts Intune onboarding, converting mobile accounts, removing AD binding and JAMF management
#    and setting admin rights.
#.EXAMPLE
#    start-intune-onboarding.sh
#.NOTES
#    Created by Ioan Popovici
#    Company Portal needs to be installed as a pre-requisite.
#    Return Codes:
#    0   - Success
#    10  - OS version not supported
#    11  - Company Portal application not installed
#    120 - Failed to display notification
#    130 - Failed to display dialog
#    131 - User cancelled dialog
#    140 - Failed to display alert
#    141 - User cancelled alert
#    150 - OS version not supported
#    160 - Invalid FileVault action
#    161 - Unauthorized FileVault user
#    162 - FileVault is already enabled
#    163 - FileVault is not enabled
#    164 - User cancelled FileVault action
#    165 - Failed to perform FileVault action
#    190 - Failed to convert mobile account
#    200 - Failed to get JAMF API token
#    201 - Failed to invalidate JAMF API token
#    202 - Invalid JAMF API token action
#    210 - Failed to perform JAMF send command action
#    211 - Invalid JAMF device id
#    220 - Failed to remove JAMF management profile
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/macOS-Intune-Onboarding-Tool
#.LINK
#    https://MEM.Zone/macOS-Intune-Onboarding-Tool-CHANGELOG
#.LINK
#    https://MEM.Zone/macOS-Intune-Onboarding-Tool-GIT
#.LINK
#    https://MEM.Zone/ISSUES

##*=============================================
##* VARIABLE DECLARATION
##*=============================================
#region VariableDeclaration

## User Defined variables
COMPANY_NAME='MEM.Zone IT'
DISPLAY_NAME='Intune Onboarding Tool'
SUPPORT_LINK='https://google.com'
DOCUMENTATION_LINK='https://google.com'
COMPANY_PORTAL_PATH='/Applications/Company Portal.app/'
CONVERT_MOBILE_ACCOUNTS='YES'
REMOVE_FROM_AD='YES'
SET_ADMIN_RIGHTS='YES'
JAMF_OFFBOARD='YES'
#  Specify last supported OS major version
SUPPORTED_OS_MAJOR_VERSION=12
#  JAMF API MDM Removal
JAMF_API_URL=''
JAMF_API_USER=''
JAMF_API_PASSWORD=''

## Script variables
#  Version
SCRIPT_VERSION=5.0.1
OS_VERSION=$(sw_vers -productVersion)
#  Author
AUTHOR='Ioan Popovici'
#  Script Name
SCRIPT_NAME=$(/usr/bin/basename "$0")
FULL_SCRIPT_NAME="$(realpath "$(dirname "${BASH_SOURCE[0]}")")/${SCRIPT_NAME}"
SCRIPT_NAME_WITHOUT_EXTENSION=$(basename "$0" | sed 's/\(.*\)\..*/\1/')
#  Set JAMF variables
if [[ -n "$JAMF_API_USER" ]] && [[ -n "$JAMF_API_PASSWORD" ]] && [[ -n "$JAMF_API_URL" ]] ; then
    JAMF_API_ENABLED='YES'
fi
BEARER_TOKEN=''
TOKEN_EXPIRATION_EPOCH=0
#  Messages
MESSAGE_TITLE=$COMPANY_NAME
MESSAGE_SUBTITLE=$DISPLAY_NAME
#  Logging
LOG_NAME=$SCRIPT_NAME_WITHOUT_EXTENSION
LOG_DIR="/Library/Logs/${COMPANY_NAME}/${DISPLAY_NAME}"
LOG_HEADER="Script Version: $SCRIPT_VERSION \n# Author: $AUTHOR \n# OS Version: $OS_VERSION \n"

#endregion
##*=============================================
##* END VARIABLE DECLARATION
##*=============================================

##*=============================================
##* FUNCTION LISTINGS
##*=============================================
#region FunctionListings

#region Function runAsRoot
#Assigned Error Codes: 100 - 109
function runAsRoot() {
#.SYNOPSIS
#    Checks for root privileges.
#.DESCRIPTION
#    Checks for root privileges and asks for elevation.
#.EXAMPLE
#    runAsRoot
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local scriptPath="$1"

    ## Check if the script is run as root
    if [[ $EUID -ne 0 ]]; then
        displayNotification 'This application must be run as root. Please authenticate!'
        if [[ -t 1 ]]; then
            sudo "$scriptPath"
        else
            gksu "$scriptPath"
        fi
        exit 0
    fi
}
#endregion

#region Function startLogging
#Assigned Error Codes: 110 - 119
function startLogging() {
#.SYNOPSIS
#    Starts logging.
#.DESCRIPTION
#    Starts loggign to to log file and STDOUT.
#.PARAMETER logName
#    Specifies the name of the log file.
#.PARAMETER logDir
#    Specifies the folder of the log file.
#.PARAMETER logHeader
#    Specifies additional header information to be added to the log file.
#.EXAMPLE
#    startLogging "logName" "logDir" "logHeader"
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local logName="$1"
    local logDir="$2"
    local logHeader="$3"

    ## Set log file path
    logFullName="${logDir}/${logName}.log"

    ## Creating log directory
    if [[ ! -d "$logDir" ]]; then
        echo "$(date) | Creating '$logDir' to store logs"
        sudo mkdir -p "$logDir"
    fi

    ## Start logging to log file
    exec &> >(sudo tee -a "$logFullName")

    ## Write log header
    echo   ""
    echo   "##*====================================================================================="
    echo   "# $(date) | Logging run of '$logName' to log file"
    echo   "# Log Path: '$logFullName'"
    printf "# ${logHeader}"
    echo   "##*====================================================================================="
    echo   ""
}
#endregion

#region Function displayNotification
#Assigned Error Codes: 120 - 129
function displayNotification() {
#.SYNOPSIS
#    Displays a notification.
#.DESCRIPTION
#    Displays a notification to the user.
#.PARAMETER messageText
#    Specifies the message of the notification.
#.PARAMETER messageTitle
#    Specifies the title of the notification. Defaults to $MESSAGE_TITLE.
#.PARAMETER messageSubtitle
#    Specifies the subtitle of the notification. Defaults to $$MESSAGE_SUBTITLE.
#.PARAMETER notificationDelay
#    Specifies the minimum delay between the notifications in seconds. Defaults to 2.
#.PARAMETER supressNotification
#    Suppresses the notification. Defaults to false.
#.PARAMETER supressTerminal
#    Suppresses the notification in the terminal. Defaults to false.
#.EXAMPLE
#    displayNotification 'message' 'title' 'subtitle' 'duration'
#.EXAMPLE
#    displayNotification 'message' 'title' 'subtitle' '' '' 'suppressTerminal'
#.EXAMPLE
#    displayNotification 'message' 'title' 'subtitle' '' 'suppressNotification' ''
#.EXAMPLE
#    displayNotification 'message'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local messageText
    local messageTitle
    local messageSubtitle
    local notificationDelay
    local supressTerminal
    local supressNotification
    local executionStatus=0
    #  Message
    messageText="${1}"
    #  Title
    if [[ -z "${2}" ]]; then
        messageTitle="${MESSAGE_TITLE}"
    else messageTitle="${2}"
    fi
    #  Subtitle
    if [[ -z "${3}" ]]; then
        messageSubtitle="${MESSAGE_SUBTITLE}"
    else messageSubtitle="${3}"
    fi
    #  Duration
    if [[ -z "${4}" ]]; then
        notificationDelay=2
    else notificationDelay="${4}"
    fi
    #  Supress notification
    if [[ -z "${5}" ]]; then
        supressNotification='false'
    else supressNotification="${5}"
    fi
    #  Supress terminal
    if [[ -z "${6}" ]]; then
        supressTerminal='false'
    else supressTerminal="${6}"
    fi

    ## Debug variables
    #echo "messageText: $messageText; messageTitle: $messageTitle; messageSubtitle: $messageSubtitle; notificationDelay: $notificationDelay ; supressNotification: $supressNotification ; supressTerminal: $supressTerminal"

    ## Display notification
    if [[ "$supressNotification" = 'false' ]]; then
        osascript -e "display notification \"${messageText}\" with title \"${messageTitle}\" subtitle \"${messageSubtitle}\""
        executionStatus=$?
        sleep "$notificationDelay"
    fi

    ## Display notification in terminal
    if [[ "$supressTerminal" = 'false' ]]; then echo "$(date) | $messageText" ; fi

    ## Return execution status
    if [[ "$executionStatus" -ne 0 ]]; then
        echo "$(date) | Failed to display notification. Error: '$executionStatus'"
        return 120
    fi
}
#endregion

#region Function displayDialog
#Assigned Error Codes: 130 - 139
function displayDialog() {
#.SYNOPSIS
#    Displays a dialog box.
#.DESCRIPTION
#    Displays a dialog box with customizable buttons and optional password prompt.
#.PARAMETER messageTitle
#    Specifies the title of the dialog. Defaults to $MESSAGE_TITLE.
#.PARAMETER messageText
#    Specifies the message of the dialog.
#.PARAMETER messageSubtitle
#    Specifies the subtitle of the notification. Defaults to $MESAGE_SUBTITLE.
#.PARAMETER buttonNames
#    Specifies the names of the buttons. Defaults to '{Cancel, Ok}'.
#.PARAMETER defaultButton
#    Specifies the default button. Defaults to '1'.
#.PARAMETER cancelButton
#    Specifies the button to exit on. Defaults to ''.
#.PARAMETER messageIcon
#    Specifies the dialog icon as:
#       * 'stop', 'note', 'caution'
#       * the name of one of the system icons
#       * the resource name or ID of the icon
#       * the icon POSIX file path
#   Defaults to ''.
#.PARAMETER promptType
#    Specifies the type of prompt.
#    Avaliable options:
#        'buttonPrompt'   - Button prompt.
#        'textPrompt'     - Text prompt.
#        'passwordPrompt' - Password prompt.
#    Defaults to 'buttonPrompt'.
#.EXAMPLE
#    displayDialog 'messageTitle' 'messageSubtitle' 'messageText' '{"Ok", "Agree"}' '1' '' '' 'buttonPrompt' 'stop'
#.EXAMPLE
#    displayDialog 'messageTitle' 'messageSubtitle' 'messageText' '{"Ok", "Stop"}' '1' 'Stop' '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FinderIcon.icns' 'textPrompt'
#.EXAMPLE
#    displayDialog 'messageTitle' 'messageSubtitle' 'messageText' "{\"Ok\", \"Don't Continue\"}" '1' "Don't Continue" '/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FinderIcon.icns' 'passwordPrompt'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local messageTitle
    local messageSubtitle
    local messageText
    local buttonNames
    local defaultButton
    local cancelButton
    local messageIcon
    local promptType
    local commandOutput
    local executionStatus=0

    ## Set parameter values
    #  Title
    if [[ -z "${1}" ]] ; then
        messageTitle="${MESSAGE_TITLE}"
    else messageTitle="${1}"
    fi
    #  Subtitle
    if [[ -z "${2}" ]] ; then
        messageSubtitle="${MESSAGE_SUBTITLE}"
    else messageSubtitle="${2}"
    fi
    #  Message
    messageText="${3}"
    #  Button names
    if [[ -z "${4}" ]] ; then
        buttonNames='{"Cancel", "Ok"}'
    else buttonNames="${4}"
    fi
    #  Default button
    if [[ -z "${5}" ]] ; then
        defaultButton='1'
    else defaultButton="${5}"
    fi
    #  Cancel button
    if [[ -z "${6}" ]] ; then
        cancelButton=''
    else cancelButton="cancel button \"${6}\""
    fi
    #  Icon
    if [[ -z "${7}" ]] ; then
        messageIcon=''
    elif [[ "${7}" = *'/'* ]] ; then
        messageIcon="with icon POSIX file \"${7}\""
    else messageIcon="with icon ${7}"
    fi
    #  Prompt type
    case "${8}" in
        'buttonPrompt')
            promptType='buttonPrompt'
        ;;
        'textPrompt')
            promptType='textPrompt'
        ;;
        'passwordPrompt')
            promptType='passwordPrompt'
        ;;
        *)
            promptType='buttonPrompt'
        ;;
    esac

    ## Debug variables
    #echo "messageTitle: $messageTitle; messageSubtitle: $messageSubtitle; messageText: $messageText; buttonNames: $buttonNames; defaultButton: $defaultButton; cancelButton: $cancelButton; messageIcon: $messageIcon; promptType: $promptType"

    ## Display dialog box
    case "$promptType" in
        'buttonPrompt')
            #  Display dialog with no input. Returns button pressed.
            commandOutput=$(osascript -e "
                on run
                    display dialog \"${messageSubtitle}\n${messageText}\" with title \"${messageTitle}\" buttons ${buttonNames} default button ${defaultButton} ${cancelButton} ${messageIcon}
                    set commandOutput to button returned of the result
                    return commandOutput
                end run
            ")
            executionStatus=$?
        ;;
        'textPrompt')
            #  Display dialog with text input. Returns text.
            commandOutput=$(osascript -e "
                on run
                    display dialog \"${messageSubtitle}\n${messageText}\" default answer \"\" with title \"${messageTitle}\" with text and answer buttons ${buttonNames} default button ${defaultButton} ${cancelButton} ${messageIcon}
                    set commandOutput to text returned of the result
                    return commandOutput
                end run
            ")
            executionStatus=$?
        ;;
        'passwordPrompt')
            #  Display dialog with hidden password input. Returns text.
            commandOutput=$(osascript -e "
                on run
                    display dialog \"${messageSubtitle}\n${messageText}\" default answer \"\" with title \"${messageTitle}\" with text and hidden answer buttons ${buttonNames} default button ${defaultButton} ${cancelButton} ${messageIcon}
                    set commandOutput to text returned of the result
                    return commandOutput
                end run
            ")
            executionStatus=$?
        ;;
    esac

    ## Exit on error
    if [[ $commandOutput = *"Error"* ]] ; then
        displayNotification "Failed to display alert. Error: '$commandOutput'" '' '' '' 'suppressNotification'
        return 130
    fi

    ## Return cancel if pressed
    if [[ $executionStatus != 0 ]] ; then
        displayNotification "User cancelled dialog." '' '' '' 'suppressNotification'
        return 131
    fi

    ## Return commandOutput. Remember to assign the result to a variable, if you print it to the terminal, it will be logged.
    echo "$commandOutput"
}
#endregion

#region Function displayAlert
#Assigned Error Codes: 140 - 149
function displayAlert() {
#.SYNOPSIS
#    Displays a alert box.
#.DESCRIPTION
#    Displays a alert box with customizable buttons and icon.
#.PARAMETER alertText
#    Specifies the alert text.
#.PARAMETER messageText
#    Specifies the message text.
#.PARAMETER alertCriticality
#    Specifies the alert criticality.
#    Avaliable options:
#        'informational' - Informational alert.
#        'critical'      - Critical alert.
#        'warning'       - Warning alert.
#    Defaults to 'informational'.
#.PARAMETER buttonNames
#    Specifies the names of the buttons. Defaults to '{Cancel, Ok}'.
#.PARAMETER defaultButton
#    Specifies the default button. Defaults to '1'.
#.PARAMETER cancelButton
#    Specifies the button to exit on. Defaults to ''.
#.PARAMETER givingUpAfter
#    Specifies the number of seconds to wait before dismissing the alert. Defaults to ''.
#.EXAMPLE
#   displayAlert 'alertText' 'messageText' 'critical' "{\"Don't Continue\", \"Dismiss Alert\"}" '1' "Don't Continue" '5'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local alertText
    local messageText
    local alertCriticality
    local buttonNames
    local defaultButton
    local cancelButton
    local givingUpAfter=''
    local commandOutput
    local executionStatus=0

    #  Alert text
    alertText="${1}"
    #  Message text
    messageText="${2}"
    #  Alert criticality
    case "${3}" in
        'informational')
            alertCriticality='as informational'
        ;;
        'critical')
            alertCriticality='as critical'
        ;;
        'warning')
            alertCriticality='as warning'
        ;;
        *)
            alertCriticality='informational'
        ;;
    esac
    #  Button names
    if [[ -z "${4}" ]] ; then
        buttonNames="{'Cance', 'Ok'}"
    else buttonNames="${4}"
    fi
    #  Default button
    if [[ -z "${5}" ]] ; then
        defaultButton='1'
    else defaultButton="${5}"
    fi
    #  Cancel button
    if [[ -z "${6}" ]] ; then
        cancelButton=''
    else cancelButton="cancel button \"${6}\""
    fi
    #  Giving up after
    if [[ -z "${7}" ]] ; then
        givingUpAfter=''
    else givingUpAfter="giving up after ${7}"
    fi

    ## Debug variables
    #echo "alertText: $alertText; messageText: $messageText; alertCriticality: $alertCriticality; buttonNames: $buttonNames; defaultButton: $defaultButton; cancelButton: $cancelButton; givingUpAfter: $givingUpAfter"

    ## Display the alert.
    commandOutput=$(osascript -e "
        on run
            display alert \"${alertText}\" message \"${messageText}\" ${alertCriticality} buttons ${buttonNames} default button ${defaultButton} ${cancelButton} ${givingUpAfter}
            set commandOutput to alert reply of the result
            return commandOutput
        end run
    ")
    executionStatus=$?

    ## Exit on error
    if [[ $commandOutput = *"Error"* ]] ; then
        displayNotification "Failed to display alert. Error: '$commandOutput'" '' '' '' 'suppressNotification'
        return 140
    fi

    ## Return cancel if pressed
    if [[ $executionStatus != 0 ]] ; then
        displayNotification "User cancelled alert." '' '' '' 'suppressNotification'
        return 141
    fi

    ## Return commandOutput. Remember to assign the result to a variable, if you print it to the terminal, it will be logged.
    echo "$commandOutput"
}
#endregion

#region Function checkSupportedOS
#Assigned Error Codes: 150 - 159
function checkSupportedOS() {
#.SYNOPSIS
#    Checks if the OS is supported.
#.DESCRIPTION
#    Checks if the OS is supported and exits if it is not.
#.PARAMETER supportedOSMajorVersion
#    Specify the major version of the OS to check.
#.EXAMPLE
#    checkSupportedOS '13'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local supportedOSMajorVersion="$1"

    ## Variable declaration
    local macOSVersion
    local macOSMajorVersion
    local macOSAllLatestVersions
    local macOSSupportedName
    local macOSName

    ## Set variables
    macOSVersion=$(sw_vers -productVersion)
    macOSMajorVersion=$(echo "$macOSVersion" | cut -d'.' -f1)

    ## Set display notification and alert variables
    #  Get all supported OS versions
    macOSAllLatestVersions=$( (echo "<table>" ; curl -sfLS "https://support.apple.com/en-us/HT201260" \
        | tidy --tidy-mark no --char-encoding utf8 --wrap 0 --show-errors 0 --show-warnings no --clean yes --force-output yes --output-xhtml yes --quiet yes \
        | sed -e '1,/<table/d; /<\/table>/,$d' -e 's#<br />##g' ; echo "</table>" ) \
        | xmllint --html --xpath "//table/tbody/tr/td/text()" - 2>/dev/null
    )
    #  Get supported OS display name
    macOSSupportedName=$(echo "$macOSAllLatestVersions" | awk "/^${supportedOSMajorVersion}/{getline; print}")
    #  Get current installed OS display name
    macOSName=$(echo "$macOSAllLatestVersions" | awk "/^${macOSMajorVersion}/{getline; print}")

    ## Check if OS is supported
    if [[ "$macOSMajorVersion" -lt "$supportedOSMajorVersion" ]] ; then

        #  Display notification and alert
        displayNotification "Unsupported OS '$macOSName ($macOSVersion)', please upgrade. Terminating execution!"
        displayAlert "OS needs to be at least '$macOSSupportedName ($supportedOSMajorVersion)'" 'Please upgrade and try again!' 'critical' '{"Upgrade macOS"}'

        #  Forcefully install latest OS update
        sudo softwareupdate -i -a
        exit 150
    else
        displayNotification "Supported OS version '$macOSName ($macOSVersion)', continuing..."
        return 0
    fi
}
#endregion

#region Function invokeFileVaultAction
#Assigned Error Codes: 160 - 169
function invokeFileVaultAction() {
#.SYNOPSIS
#    Invokes a FileVault action.
#.DESCRIPTION
#    Invokes a FileVault action for the current user by prompting for the password, and populating answers for the fdesetup prompts.
#.PARAMETER action
#    Specify the action to invoke. Valid values are 'enable', 'disable', and 'reissueKey'.
#.EXAMPLE
#    invokeFileVaultAction 'enable'
#.EXAMPLE
#    invokeFileVaultAction 'disable'
#.EXAMPLE
#    invokeFileVaultAction 'reissueKey'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://github.com/jamf/FileVault2_Scripts/blob/master/reissueKey.sh (Original script and copyright notice)
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Variable declaration
    local fileVaultIcon
    local userName
    local userNameUUID
    local isFileVaultUser
    local isFileVaultOn
    local loopCounter=1
    local action
    local actionMessage
    local actionTitle
    local actionSubtitle
    local actionButtons
    local checkFileVaultStatus

    ## Set action
    case "$1" in
        'enable')
            action="$1"
            actionTitle='Enable FileVault'
            actionSubtitle='FileVault needs to be enabled!'
            actionButtons='{"Cancel", "Enable FileVault")'
            checkFileVaultStatus='On'
        ;;
        'disable')
            action="$1"
            actionTitle='Disable FileVault'
            actionSubtitle='FileVault needs to be disabled!'
            actionButtons='{"Cancel", "Disable FileVault"}'
            checkFileVaultStatus='Off'

        ;;
        'reissueKey')
            action='changerecovery -personal'
            actionTitle='Reissue FileVault Key'
            actionSubtitle='FileVault needs to reissue the key!'
            actionButtons='{"Cancel", "Reissue Key"}'
            checkFileVaultStatus='NotNeeded'
        ;;
        *)
            displayNotification "Invalid FileVault action '$1'. Skipping '$actionTitle'..." '' '' '' 'suppressNotification'
            return 160
        ;;
    esac

    ## Set filevault icon
    fileVaultIcon='/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/FileVaultIcon.icns'

    ## Get the logged in user's name
    userName=$(/usr/bin/stat -f%Su /dev/console)

    ## Get the user's UUID
    userNameUUID=$(dscl . -read /Users/"$userName"/ GeneratedUID | awk '{print $2}')

    ## Check if user is an authorized FileVault user
    isFileVaultUser=$(fdesetup list | awk -v usrN="$userNameUUID" -F, 'match($0, usrN) {print $1}')
    if [ "${isFileVaultUser}" != "${userName}" ]; then
        displayNotification "${userName} is not a FileVault authorized user. Skipping '$actionTitle'..."
        return 161
    fi

    ## Check to see if the encryption has finished
    isFileVaultOn=$(fdesetup status | grep "FileVault is On.")

    ## Check FileVault status
    if [ "$checkFileVaultStatus" = 'On' ]; then
        if [ -n "$isFileVaultOn" ]; then
            displayNotification "FileVault is already enabled. Skipping '$actionTitle'..."
            return 162
        fi
    else
        if [ -z "$isFileVaultOn" ]; then
            displayNotification "FileVault is not enabled. Skipping '$actionTitle'..."
            return 163
        fi
    fi

    ## Disable FileVault
    while true; do

        ## Get the logged in user's password via a prompt
        actionMessage="Enter $userName's password:"
        userPassword=$(displayDialog "$actionTitle" "$actionSubtitle" "$actionMessage" "$actionButtons" '2' 'Cancel' "$fileVaultIcon" 'passwordPrompt')

        ## Check if the user cancelled the prompt (return code 131)
        if [ $? = 131 ]; then
            displayNotification "User cancelled '$actionTitle' action!"
            return 164
        fi

        displayNotification "Attempting FileVault action '$actionTitle'..." '' '' '1'

        ## Automatically populate answers for the fdesetup prompts
        output=$(
            expect -c "
            log_user 0
            spawn fdesetup $action
            expect \"Enter the user name:\"
            send {${userName}}
            send \r
            expect \"Enter a password for '/', or the recovery key:\"
            send {${userPassword}}
            send \r
            log_user 1
            expect eof
        ")

        if [[ $output = *'Error'* ]] || [[ $output = *'FileVault was not disabled'* ]] ; then
            displayNotification "Error performing FileVault action '$actionTitle' Attempt (${loopCounter}/3). $output"
            if [ $loopCounter -ge 3 ] ; then
                displayNotification "A maximum of 3 retries has been reached.\nContinuing without performing FileVault action '$action'..."
                return 165
            fi
            ((loopCounter++))
        else
            displayNotification "Sucessfully performed FileVault action '$actionTitle'!"
            return 0
        fi
    done
}
#endregion

#region Function unbindFromAD
#Assigned Error Codes: 170 - 179
function unbindFromAD() {
#.SYNOPSIS
#    Unbinds device from AD.
#.DESCRIPTION
#     Unbinds device from AD and removes search paths.
#.EXAMPLE
#    unbindFromAD
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Variable declaration
    local searchPath
    local isAdJoined
    local executionStatus

    ## Check for AD binding and unbind if found.
    isAdJoined=$(/usr/bin/dscl localhost -list . | grep 'Active Directory')
    if [[ -z "$isAdJoined" ]]; then
        displayNotification 'Not bound to Active Directory. Skipping unbind...'
        #  Return to the pipeline
        return 0
    fi

    ## Display notification
    displayNotification 'Unbinding from Active Directory...'

    ## Set search path
    searchPath=$(/usr/bin/dscl /Search -read . CSPSearchPath | grep Active\ Directory | sed 's/^ //')

    ## Force unbind from Active Directory
    /usr/sbin/dsconfigad -remove -force -u none -p none
    executionStatus=$?

    ## Delete the Active Directory domain from the custom /Search and /Search/Contacts paths
    /usr/bin/dscl /Search/Contacts -delete . CSPSearchPath "$searchPath"
    /usr/bin/dscl /Search -delete . CSPSearchPath "$searchPath"

    ## Change the /Search and /Search/Contacts path type from Custom to Automatic
    /usr/bin/dscl /Search -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath
    /usr/bin/dscl /Search/Contacts -change . SearchPolicy dsAttrTypeStandard:CSPSearchPath dsAttrTypeStandard:NSPSearchPath

    ## Return execution status
    if [[ $executionStatus != 0 ]] ; then
        displayNotification "Failed to unbind from Active Directory. Error: '$executionStatus'" '' '' '' 'suppressNotification'
        return 170
    fi
}
#endregion

#region Function migrateUserPassword
#Assigned Error Codes: 180 - 189
function migrateUserPassword() {
#.SYNOPSIS
#    Migrates the user password to the local account.
#.DESCRIPTION
#    Migrates the user password to the local account by removing the Kerberos and LocalCachedUser user values from the AuthenticationAuthority array.
#.PARAMETER userName
#    Specifies the name of the user.
#.EXAMPLE
#    migrateUserPassword "username"
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable variables
    local userName="${1}"

    # Variable declaration
    local AuthenticationAuthority
    local Kerberosv5
    local localCachedUser

    ## Display notification
    displayNotification "Migrating '$userName' password..."

    # macOS 10.14.4 will remove the the actual ShadowHashData key immediately if the AuthenticationAuthority array value which references the ShadowHash is removed from the AuthenticationAuthority array.
    # To address this, the existing AuthenticationAuthority array will be modified to remove the Kerberos and LocalCachedUser user values.

    ## Get AuthenticationAuthority
    AuthenticationAuthority=$(/usr/bin/dscl -plist . -read /Users/"$userName" AuthenticationAuthority)

    ## Get Kerberosv5 and LocalCachedUser
    Kerberosv5=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"Kerberosv5")])' -)
    localCachedUser=$(echo "${AuthenticationAuthority}" | xmllint --xpath 'string(//string[contains(text(),"LocalCachedUser")])' -)

    ## Remove Kerberosv5 value
    if [[ -n "${Kerberosv5}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/"$userName" AuthenticationAuthority "${Kerberosv5}"
    fi

    ## Remove LocalCachedUser value
    if [[ -n "${localCachedUser}" ]]; then
        /usr/bin/dscl -plist . -delete /Users/"$userName" AuthenticationAuthority "${localCachedUser}"
    fi
}
#endregion

#region Function convertMobileAccount
#Assigned Error Codes: 190 - 199
function convertMobileAccount() {
#.SYNOPSIS
#    Converts mobile account to local account.
#.DESCRIPTION
#    Converts mobile account to local account, by removing mobile account properties and  migrating the user password to the local account.
#.PARAMETER userName
#    Specifies the name of the user.
#.PARAMETER makeAdmin
#    Specifies whether the user should be made a local admin.
#.EXAMPLE
#    convertMobileAccount "username" "YES"
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Set human readable parameters
    local userName="${1}"
    local makeAdmin="${2}"

    ## Variable declaration
    local accountType
    local isMobileUser
    local attributesToRemove
    local attributeToRemove
    local homeDirectory

    ## Set variable values
    attributesToRemove=(
        cached_groups
        cached_auth_policy
        CopyTimestamp
        AltSecurityIdentities
        SMBPrimaryGroupSID
        OriginalAuthenticationAuthority
        OriginalNodeName
        SMBSID
        SMBScriptPath
        SMBPasswordLastSet
        SMBGroupRID
        PrimaryNTDomain
        AppleMetaRecordName
        MCXSettings
        MCXFlags
    )

    ## Get account type
    accountType=$(/usr/bin/dscl . -read /Users/"$userName" AuthenticationAuthority | head -2 | awk -F'/' '{print $2}' | tr -d '\n')

    ## Check if account is a mobile account
    if [[ "$accountType" = "Active Directory" ]]; then
        isMobileUser=$(/usr/bin/dscl . -read /Users/"$userName" AuthenticationAuthority | head -2 | awk -F'/' '{print $1}' | tr -d '\n' | sed 's/^[^:]*: //' | sed s/\;/""/g)
        if [[ "$isMobileUser" = "LocalCachedUser" ]]; then
            displayNotification "Converting $userName to a local account..."
        fi
    else
        displayNotification "The $userName is not a mobile account. Skipping conversion..."
        return
    fi

    ## Remove the account attributes that identify it as an Active Directory mobile account
    for attributeToRemove in "${attributesToRemove[@]}"; do
        if [[ ! $(/usr/bin/dscl . -delete /users/"$userName" "$attributeToRemove") ]]; then
            displayNotification "Failed to remove account attribute '$attributeToRemove'!"
        fi
    done

    ## Migrate password
    migrateUserPassword "$userName"

    ## Refresh Directory Services
    /usr/bin/killall opendirectoryd
    sleep 20

    ## Check if account is a mobile account
    accountType=$(/usr/bin/dscl . -read /Users/"$userName" AuthenticationAuthority | head -2 | awk -F'/' '{print $2}' | tr -d '\n')
    if [[ "$accountType" = "Active Directory" ]]; then
        displayNotification "Error converting the $userName account! Terminating execution..."
        exit 190
    else
        displayNotification "$userName was successfully converted to a local account."
    fi

    ## Update home folder and permissions for the account. This could take a while.
    homeDirectory=$(/usr/bin/dscl . -read /Users/"$userName" NFSHomeDirectory | awk '{print $2}')
    if [[ "$homeDirectory" != "" ]]; then
        displayNotification "Updating $homeDirectory permissions for the $userName account, this could take a while..."
        /usr/sbin/chown -R "$1" "$homeDirectory"
    fi

    ## Add user to the staff group on the Mac
    displayNotification "Adding $userName to the staff group..."
    /usr/sbin/dseditgroup -o edit -a "$userName" -t user staff

    ## Add user to the admin group on the Mac
    if [[ "$makeAdmin" = "YES" ]]; then
        displayNotification "Granting admin rights to $userName..."
        /usr/sbin/dseditgroup -o edit -a "$userName" -t user admin
    fi
}
#endregion

#region Function invokeJamfApiTokenAction
#Assigned Error Codes: 200 - 209
function invokeJamfApiTokenAction() {
#.SYNOPSIS
#    Performs a JAMF API token action.
#.DESCRIPTION
#    Performs a JAMF API token action, such as getting, checking validity or invalidating a token.
#.PARAMETER apiUrl
#    Specifies the JAMF API server url.
#.PARAMETER apiUser
#    Specifies the JAMF API username.
#.PARAMETER apiPassword
#    Specifies the JAMF API password.
#.PARAMETER tokenAction
#    Specifies the action to perform.
#    Possible values: get, check, invalidate
#.EXAMPLE
#    invokeJamfApiTokenAction 'memzone@jamfcloud.com' 'jamf-api-user' 'strongpassword' 'get'
#.NOTES
#    Returns the token and the token expiration epoch in the global variables BEARER_TOKEN and TOKEN_EXPIRATION_EPOCH.
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES
#.LINK
#    https://developer.jamf.com/reference/jamf-pro/

    ## Variable declarations
    local apiUrl
    local apiUser
    local apiPassword
    local tokenAction
    local response
    local responseCode
    local nowEpochUTC

    ## Set variable values
    if [[ -z "${1}" ]] || [[ -z "${2}" ]] || [[ -z "${3}" ]] ; then
        apiUrl="$JAMF_API_URL"
        apiUser="$JAMF_API_USER"
        apiPassword="$JAMF_API_PASSWORD"
    else
        apiUrl="${1}"
        apiUser="${2}"
        apiPassword="${3}"
    fi
    tokenAction="${4}"

    #region Inline Functions
    getBearerToken() {
        response=$(curl -s -u "$apiUser":"$apiPassword" "$apiUrl"/api/v1/auth/token -X POST)
        BEARER_TOKEN=$(echo "$response" | plutil -extract token raw -)
        tokenExpiration=$(echo "$response" | plutil -extract expires raw - | awk -F . '{print $1}')
        TOKEN_EXPIRATION_EPOCH=$(date -j -f "%Y-%m-%dT%T" "$tokenExpiration" +"%s")
        if [[ -z "$BEARER_TOKEN" ]] ; then
            displayNotification "Failed to get a valid API token!" '' '' '' 'suppressNotification'
            return 200
        else
            displayNotification "API token successfully retrieved!" '' '' '' 'suppressNotification'
        fi
    }

    checkTokenExpiration() {
        nowEpochUTC=$(date -j -f "%Y-%m-%dT%T" "$(date -u +"%Y-%m-%dT%T")" +"%s")
        if [[ TOKEN_EXPIRATION_EPOCH -gt nowEpochUTC ]] ; then
            displayNotification "API token valid until the following epoch time: $TOKEN_EXPIRATION_EPOCH" '' '' '' 'suppressNotification'
        else
            displayNotification "No valid API token available..." '' '' '' 'suppressNotification'
            getBearerToken
        fi
    }

    invalidateToken() {
        responseCode=$(curl -w "%{http_code}" -H "Authorization: Bearer ${BEARER_TOKEN}" "$apiUrl"/api/v1/auth/invalidate-token -X POST -s -o /dev/null)
        if [[ ${responseCode} == 204 ]] ; then
            displayNotification "Token successfully invalidated!" '' '' '' 'suppressNotification'
            BEARER_TOKEN=''
            TOKEN_EXPIRATION_EPOCH=0
        elif [[ ${responseCode} == 401 ]] ; then
            displayNotification "Token already invalid!" '' '' '' 'suppressNotification'
        else
            displayNotification "An unknown error occurred invalidating the token!" '' '' '' 'suppressNotification'
            return 201
        fi
    }
    #endregion

    ## Perform token action
    case "$tokenAction" in
        get)
            displayNotification "Getting new token..." '' '' '' 'suppressNotification'
            getBearerToken
            ;;
        check)
            displayNotification "Checking token validity..." '' '' '' 'suppressNotification'
            checkTokenExpiration
            ;;
        invalidate)
            displayNotification "Invalidating token..." '' '' '' 'suppressNotification'
            invalidateToken
            ;;
        *)
            displayNotification "Invalid token action '$tokenAction' specified! Terminating execution..."
            exit 202
            ;;
    esac
}
#endregion

#region Function invokeSendJamfCommand
#Assigned Error Codes: 210 - 219
function invokeSendJamfCommand() {
#.SYNOPSIS
#    Performs a JAMF API send command.
#.DESCRIPTION
#    Performs a JAMF API send command, with the specified command and device serial number.
#.PARAMETER apiUrl
#    Specifies the JAMF API server url.
#.PARAMETER apiUser
#    Specifies the JAMF API username.
#.PARAMETER apiPassword
#    Specifies the JAMF API password.
#.PARAMETER serialNumber
#    Specifies the device serial number.
#.PARAMETER command
#    Specifies the command to perform, keep in mind that you need to specify the command and the parameters in one string.
#.EXAMPLE
#    invokeSendJamfCommand 'memzone@jamfcloud.com' 'jamf-api-user' 'strongpassword' 'FVFHX12QQ6LY' 'UnmanageDevice'
#.EXAMPLE
#    invokeSendJamfCommand 'memzone@jamfcloud.com' 'jamf-api-user' 'strongpassword' 'FVFHX12QQ6LY' 'EraseDevice/passcode/123456'
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES
#.LINK
#    https://developer.jamf.com/reference/jamf-pro/

    ## Variable declarations
    local apiUrl
    local apiUser
    local apiPassword
    local command
    local serialNumber
    local deviceId
    local result

    ## Set variable values
    if [[ -z "${1}" ]] || [[ -z "${2}" ]] || [[ -z "${3}" ]] ; then
        apiUrl="$JAMF_API_URL"
        apiUser="$JAMF_API_USER"
        apiPassword="$JAMF_API_PASSWORD"
    else
        apiUrl="${1}"
        apiUser="${2}"
        apiPassword="${3}"
    fi
    serialNumber="${4}"
    command="${5}"

    ## Get API token
    invokeJamfApiTokenAction "$apiUrl" "$apiUser" "$apiPassword" 'get'

    ## Get JAMF device ID
    deviceId=$(curl --request GET \
        --url "${apiUrl}"/JSSResource/computers/serialnumber/"${serialNumber}"/subset/general \
        --header 'Accept: application/xml' \
        --header "Authorization: Bearer ${BEARER_TOKEN}" \
        --silent --show-error --fail | xmllint --xpath '//computer/general/id/text()' -
    )

    ## Perform action
    if [[ $deviceId -gt 0 ]]; then
       result=$(curl -s -o /dev/null -I -w "%{http_code}" \
            --request POST \
            --url "${apiUrl}"/JSSResource/computercommands/command/"${command}"/id/"${deviceId}" \
            --header 'Content-Type: application/xml' \
            --header "Authorization: Bearer ${BEARER_TOKEN}" \
        )
        ## Check result (201 = Created/Success)
        if [[ $result -eq 201 ]]; then
            displayNotification "Successfully performed command '${command}' on device '${serialNumber} [${deviceId}]'!" '' '' '' 'suppressNotification'
            return 0
        else
            displayNotification "Failed to perform command '${command}' on device '${serialNumber} [${deviceId}]'!" '' '' '' 'suppressNotification'
            return 210
        fi
    else
        displayNotification "Invalid device id '${deviceId} [${serialNumber}]'. Skipping '${command}'..." '' '' '' 'suppressNotification'
        return 211
    fi
}
#endregion

#region Function startJamfOffboarding
#Assigned Error Codes: 220 - 229
function startJamfOffboarding() {
#.SYNOPSIS
#    Starts JAMF offboarding.
#.DESCRIPTION
#    Starts JAMF offboarding, removing certificates, profiles and binaries.
#.EXAMPLE
#    startJamfOffboarding
#.EXAMPLE
#    startJamfOffboarding
#.NOTES
#    This is an internal script function and should typically not be called directly.
#.LINK
#    https://MEM.Zone
#.LINK
#    https://MEM.Zone/ISSUES

    ## Variable declaration
    local hasJamfBinaries
    local isJamfManaged
    local currentUser
    local serialNumber
    local loopCounter=0

    ## Check if JAMF managed
    isJamfManaged=$(/usr/bin/profiles -C | /usr/bin/grep '00000000-0000-0000-A000-4A414D460003')
    hasJamfBinaries=$(which jamf)
    if [[ -z "$isJamfManaged" ]] && [[ -z "$hasJamfBinaries" ]]; then
        displayNotification 'Not JAMF managed. Skipping JAMF offboarding...'
        return 0
    fi

    ## Display notification
    displayNotification 'JAMF offboarding has started...'

    ## Get current user
    currentUser=$(stat -f '%Su' /dev/console)

    ## Quit Self-Service.
    displayNotification 'Stopping self Service Process...'
    killall "Self Service"

    ## Remove JAMF management
    if [[ -n "$isJamfManaged" ]] ; then
        if [[ "$JAMF_API_ENABLED" = 'YES' ]]; then
            displayNotification 'Removing JAMF management trough API...'
            #  Get serial number
            serialNumber=$(system_profiler SPHardwareDataType | grep Serial | awk '{print $NF}')
            #  Remove JAMF management
            invokeSendJamfCommand '' '' '' "$serialNumber" 'UnmanageDevice'
        else
            #  Remove JAMF management without API
            displayNotification 'Removing JAMF management profile...'
            sudo jamf removeMdmProfile
        fi
        #  Check if management profile was removed
        isJamfManaged=$(/usr/bin/profiles -C | /usr/bin/grep '00000000-0000-0000-A000-4A414D460003')
    else
        displayNotification 'Not JAMF managed. Skipping JAMF management removal...'
    fi

    ## Check if management profile was removed
    while [ -n "$isJamfManaged" ]; do
        #  Wait 15 seconds
        sleep 15
        #  Check if management profile is still present
        isJamfManaged=$(/usr/bin/profiles -C | /usr/bin/grep '00000000-0000-0000-A000-4A414D460003')
        #  Try to remove profile without API
        sudo jamf removeMdmProfile
        #  Terminate execution after 3 retries
        if [ $loopCounter -ge 4 ] ; then
            displayNotification "JAMF management profile could not be removed! Terminating execution..."
            exit 220
        fi
        #  Increment loop counter
        ((loopCounter++))
    done

    ## Remove JAMF Framework
    if [[ -n "$hasJamfBinaries" ]]; then
        displayNotification 'Removing JAMF Framework...'
        sudo jamf removeFramework
    else
        displayNotification 'JAMF Framework not installed. Skipping JAMF Framework removal...'
    fi

    ## Remove all system profiles
    displayNotification 'Removing System Profiles...'
    for identifier in $(/usr/bin/profiles -L | awk '/attribute/' | awk '{print $4}'); do
        displayNotification "Attempting to remove System Profile '$identifier'..."  '' '' '' 'suppressNotification'
        sudo -u "$currentUser" profiles -R -p "$identifier" >/dev/null 2>&1
    done
    if [[ ! $identifier ]]; then
        displayNotification 'No System Profiles to remove...'
    fi

    ## Remove Configuration Profiles
    displayNotification 'Removing all Configuration Profiles...'
    sudo -u "$currentUser" profiles remove -forced -all -v

    ## Display notification
    displayNotification 'JAMF Offboarding is complete!'
}
#endregion

#endregion
##*=============================================
##* END FUNCTION LISTINGS
##*=============================================

##*=============================================
##* SCRIPT BODY
##*=============================================
#region ScriptBody

## Check if script is running as root
runAsRoot "$FULL_SCRIPT_NAME"

## Start logging
startLogging "$LOG_NAME" "$LOG_DIR" "$LOG_HEADER"

## Show script version and suppress terminal output
displayNotification "Running $SCRIPT_NAME version $SCRIPT_VERSION" '' '' '' '' 'suppressTerminal'

## Check if OS is supported
checkSupportedOS "$SUPPORTED_OS_MAJOR_VERSION"

## If Company Portal is installed, continue, otherwise quit
if open -Ra 'Company Portal'; then
    displayNotification 'Company Portal application is installed, continuing...'
else
    displayNotification 'Company Portal application not installed, contact support!'
    displayAlert "Company Portal app is not installed" 'In order to continue, please contact support!' 'critical' '{"Contact Support"}'
    open "$SUPPORT_LINK"
    exit 11
fi

## Unbind from AD
if [[ "$REMOVE_FROM_AD" = 'YES' ]] ; then unbindFromAD ; fi

## Convert mobile accounts to local accounts
if [[ "$CONVERT_MOBILE_ACCOUNTS" = 'YES' ]] ; then
    localUsers=$(/usr/bin/dscl . list /Users UniqueID | awk '$2 > 500 {print $1}')
    for localUser in $localUsers; do
        convertMobileAccount "$localUser" "$SET_ADMIN_RIGHTS"
    done
fi

## Offboard JAMF
if [[ "$JAMF_OFFBOARD" = 'YES' ]] ; then
    startJamfOffboarding
fi

## Disable FileVault
invokeFileVaultAction 'disable'

## Start Company Portal
displayNotification 'Starting Company Portal...'
open -a "$COMPANY_PORTAL_PATH"

## Display documentation
displayNotification 'Displaying documentation...'
open -gj "$DOCUMENTATION_LINK"

#endregion
##*=============================================
##* END SCRIPT BODY
##*=============================================