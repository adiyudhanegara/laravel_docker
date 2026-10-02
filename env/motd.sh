# ==================================================
# Custom Login Banner - AYCRAFT PROJECTS
# ==================================================

[[ -n "$PS1" ]] || return
# clear # clear upper

TODAY=$(date +"%d/%m/%y")
THISYEAR=$(date +"%Y")

# =========================
# TEXT STYLES
# =========================
RESET="\033[0m"
BOLD="\033[1m"
DIM="\033[2m"
UNDERLINE="\033[4m"
BLINK="\033[5m"        # jarang dipakai
REVERSE="\033[7m"

# =========================
# BASIC ANSI COLORS (16)
# =========================
BLACK="\033[30m"
RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
BLUE="\033[34m"
MAGENTA="\033[35m"
CYAN="\033[36m"
WHITE="\033[37m"

# Bright
BRIGHT_BLACK="\033[90m"
BRIGHT_RED="\033[91m"
BRIGHT_GREEN="\033[92m"
BRIGHT_YELLOW="\033[93m"
BRIGHT_BLUE="\033[94m"
BRIGHT_MAGENTA="\033[95m"
BRIGHT_CYAN="\033[96m"
BRIGHT_WHITE="\033[97m"

# =========================
# BRAND / NICE 256 COLORS
# =========================
NAVY="\033[38;5;24m"
ROYAL_BLUE="\033[38;5;26m"
SKY_BLUE="\033[38;5;39m"

TEAL="\033[38;5;37m"      # tosca
AQUA="\033[38;5;45m"
MINT="\033[38;5;48m"

PURPLE="\033[38;5;141m"
VIOLET="\033[38;5;135m"
PINK="\033[38;5;205m"

ORANGE="\033[38;5;208m"
GOLD="\033[38;5;220m"

LIME="\033[38;5;118m"
EMERALD="\033[38;5;35m"

GRAY="\033[38;5;245m"
DARK_GRAY="\033[38;5;238m"
LIGHT_GRAY="\033[38;5;250m"

# =========================
# BACKGROUND COLORS (OPTIONAL)
# =========================
BG_NAVY="\033[48;5;24m"
BG_TEAL="\033[48;5;37m"
BG_GRAY="\033[48;5;236m"


# SETUP
BORDER=$DARK_GRAY
ICON1=$BRIGHT_BLUE
ICON2=$PURPLE
ICON=$SKY_BLUE
TEXT=$LIGHT_GRAY

printf "${BORDER}╔════════════════════════════════════════════════════════════════════════╗${RESET}\n"
printf "${BORDER}║${RESET}                            ${ORANGE}${BOLD}${UNDERLINE}AYCRAFT${RESET}${SKY_BLUE}${BOLD}${UNDERLINE}PROJECTS${RESET}                             ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                                                                        ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}        ${ICON1}ÆÆÆÆÆÆ${RESET}                                                          ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}     ${ICON1}ÆÆÆ${RESET}     ${ICON1}ÆÆÆ${RESET}                                                        ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}    ${ICON1}ÆÆ${RESET}  ${ICON2}ÆÆÆ${RESET}   ${ICON2}ÆÆ${RESET} ${ICON}Æ${RESET}    ${TEXT}ÆÆÆ  ÆÆ   ÆÆ   ÆÆÆ  ÆÆÆÆÆ     ÆÆÆ   ÆÆÆÆÆ ÆÆÆÆÆÆÆ${RESET} ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}   ${ICON1}ÆÆ${RESET}  ${ICON2}ÆÆÆÆÆ${RESET} ${ICON2}ÆÆÆ${RESET} ${ICON}ÆÆ${RESET}   ${TEXT}ÆÆÆÆ  ÆÆÆÆÆ ÆÆÆ   Æ ÆÆ  ÆÆ   ÆÆÆÆ   ÆÆÆ     ÆÆÆ${RESET}   ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}   ${ICON1}Æ${RESET}  ${ICON2}ÆÆÆ${RESET} ${ICON2}ÆÆÆÆÆ${RESET}  ${ICON}ÆÆ${RESET}  ${TEXT}ÆÆ ÆÆ   ÆÆÆ  ÆÆÆ     ÆÆÆÆÆ    ÆÆ ÆÆ  ÆÆÆÆÆ   ÆÆÆ${RESET}   ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}   ${ICON1}ÆÆ${RESET} ${ICON2}ÆÆÆÆ${RESET} ${ICON2}ÆÆÆ${RESET}   ${ICON}ÆÆ${RESET} ${TEXT}ÆÆÆÆÆÆÆ  ÆÆÆ  ÆÆÆÆ  Æ ÆÆ  ÆÆ  ÆÆÆÆÆÆÆ ÆÆ      ÆÆÆ${RESET}   ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}     ${ICON2}ÆÆ${RESET}     ${ICON2}ÆÆ${RESET}  ${ICON}ÆÆ${RESET}  ${TEXT}ÆÆ    ÆÆ ÆÆ      ÆÆÆ  ÆÆ   ÆÆÆÆ    ÆÆ ÆÆ       ÆÆ${RESET}   ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}     ${ICON}ÆÆÆÆ${RESET}    ${ICON}ÆÆÆ${RESET}                                                        ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}        ${ICON}ÆÆÆÆÆ${RESET}                                                           ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                                 ${DIM}Today:${RESET}                                 ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                                ${GREEN}$TODAY${RESET}                                ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                                                                        ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                                 ${DIM}v.1.0${RESET}                                  ${BORDER}║${RESET}\n"
printf "${BORDER}║${RESET}                        ${GRAY}© Copyright ${BOLD}AYCRAFT${RESET} $THISYEAR${RESET}                        ${BORDER}║${RESET}\n"
printf "${BORDER}╚════════════════════════════════════════════════════════════════════════╝${RESET}\n"
