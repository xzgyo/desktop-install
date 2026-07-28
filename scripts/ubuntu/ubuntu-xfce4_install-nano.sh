#!/usr/bin/env bash

# Author: xzgyo
set -e
set -o pipefail

# 常量
WILL_INSTALL_NAME="Xfce4"
WILL_INSTALL_TYPE="Desktop Environment"
TARGET_SYSTEM="Ubuntu"
COMMON_GROUPS=(sudo audio cdrom dialout dip floppy plugdev users video)

# 变量
DRY_RUN=0
ADD_USER=1
USE_CN_MIRROR=0
SYSTEM_CODENAME="$(. /etc/os-release && echo $VERSION_CODENAME)"
SYSTEM_VERSION_ID="$(. /etc/os-release && echo $VERSION_ID)"
DEB822_LOCATION="/etc/apt/sources.list.d/ubuntu.sources"
DO_NOT_ASK=0
MINIMAL=0
WITH_ERROR=0
SUCCESS=1

# 其他变量
export DEBIAN_FRONTEND=noninteractive

get_version_id_by_codename() {
  local code="${1,,}"
  case "$code" in
    warty)            echo "4.10" ;;
    hoary)            echo "5.04" ;;
    breezy)           echo "5.10" ;;
    dapper)           echo "6.06" ;;
    edgy)             echo "6.10" ;;
    feisty)           echo "7.04" ;;
    gutsy)            echo "7.10" ;;
    hardy)            echo "8.04" ;;
    intrepid)         echo "8.10" ;;
    jaunty)           echo "9.04" ;;
    karmic)           echo "9.10" ;;
    lucid)            echo "10.04" ;;
    maverick)         echo "10.10" ;;
    natty)            echo "11.04" ;;
    oneiric)          echo "11.10" ;;
    precise)          echo "12.04" ;;
    quantal)          echo "12.10" ;;
    raring)           echo "13.04" ;;
    saucy)            echo "13.10" ;;
    trusty)           echo "14.04" ;;
    utopic)           echo "14.10" ;;
    vivid)            echo "15.04" ;;
    wily)             echo "15.10" ;;
    xenial)           echo "16.04" ;;
    yakkety)          echo "16.10" ;;
    zesty)            echo "17.04" ;;
    artful)           echo "17.10" ;;
    bionic)           echo "18.04" ;;
    cosmic)           echo "18.10" ;;
    disco)            echo "19.04" ;;
    eoan)             echo "19.10" ;;
    focal)            echo "20.04" ;;
    groovy)           echo "20.10" ;;
    hirsute)          echo "21.04" ;;
    impish)           echo "21.10" ;;
    jammy)            echo "22.04" ;;
    kinetic)          echo "22.10" ;;
    lunar)            echo "23.04" ;;
    mantic)           echo "23.10" ;;
    noble)            echo "24.04" ;;
    oracular)         echo "24.10" ;;
    plucky)           echo "25.04" ;;
    questing)         echo "25.10" ;;
    resolute)         echo "26.04" ;;
    stonking)         echo "26.10" ;;
    # 将来的版本
    *)                echo "2147483647" ;;
  esac
}

get_current_codename() {
  if [ -f "$DEB822_LOCATION" ]; then
    local CODENAME="$(grep "Suites" "$DEB822_LOCATION" | sed 's/Suites: //g' | tr ' ' '\n' | grep -v '-')"
    echo $CODENAME
  elif [ -f /etc/apt/sources.list ]; then
    local CODENAME="$(grep '^deb ' /etc/apt/sources.list | awk '{print $3}' | grep -v '-')"
    echo $CODENAME
  fi
}

SYSTEM_CODENAME="$(get_current_codename)"

# 处理参数
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      echo "$0 [--dry-run] [--cn] [--do-not-add-user] [--new-uid=UID] [--new-user=USER] [--new-user-password=PASSWORD] [--codename-overwrite=DEBIAN_VERSION_CODENAME] [--do-not-ask] [--minimal]"
      echo "--cn argument will auto change APT repo to mirrors.tuna.tsinghua.edu.cn."
      exit 0
      ;;
    --dry-run)
      DRY_RUN=1
      shift
      ;;
    --do-not-add-user)
      ADD_USER=0
      shift
      ;;
    --new-uid=*)
      NEW_USER_UID="${1#*=}"
      shift
      ;;
    --new-user=*)
      NEW_USER_USERNAME="${1#*=}"
      shift
      ;;
    --new-user-password=*)
      NEW_USER_PASSWORD="${1#*=}"
      shift
      ;;
    --cn)
      # Tuna一定是金枪鱼的意思吧（
      USE_CN_MIRROR=1
      shift
      ;;
    --codename-overwrite=*)
      # 强制使用stable/testing/sid等特殊codename？
      SYSTEM_CODENAME="${1#*=}"
      SYSTEM_VERSION_ID="$(get_version_id_by_codename "$SYSTEM_CODENAME")"
      shift
      ;;
    --minimal)
      MINIMAL=1
      shift
      ;;
    --do-not-ask)
      DO_NOT_ASK=1
      shift
      ;;
    -*)
      echo -e "\033[31;1mUnknown option $1\033[0m\nType \"$0 --help\" for more details."
      exit 1
      ;;
    *)
      shift
      ;;
  esac
done

if [ $ADD_USER -eq 0 ] && { [ -n "$NEW_USER_UID" ] || [ -n "$NEW_USER_USERNAME" ] || [ -n "$NEW_USER_PASSWORD" ]; }; then
  echo "ERROR: --new-uid/--new-user/--new-user-password and --do-not-add-user are incompatible!!!"
  exit 1
fi

if [ $DO_NOT_ASK -eq 1 ] && [ $ADD_USER -eq 1 ]; then
  if [ -z "$NEW_USER_UID" ] || [ -z "$NEW_USER_USERNAME" ] || [ -z "$NEW_USER_PASSWORD" ]; then
    echo "ERROR: --do-not-ask requires --new-user, --new-uid and --new-user-password args!"
    exit 1
  fi
fi

check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    echo "Are you root?"
    if [ $DRY_RUN -eq 0 ]; then
      echo -e "Run current script with ROOT PERMISSION again."
      exit 1
    else
      echo -e "Root check skipped in --dry-run..."
    fi
  fi
}

greeting() {
  echo -e "This script will install the $WILL_INSTALL_NAME $WILL_INSTALL_TYPE in $TARGET_SYSTEM minimal environment."
  echo 'Common minimal environments include: VM guests, containers, LXC/LXD, WSL, etc.'
  echo 'Author: xzgyo'
}

# environment_detect() {
  # if systemd-detect-virt --quiet; then
    # echo "Running in $(systemd-detect-virt)."
  # else
    # echo "Probably running on bare metal."
  # fi
# }

check_distro() {
  local CURRENT_DISTRO="$( . /etc/os-release >/dev/null 2>&1 && echo "$ID" )"
  echo -e "The current distribution is \033[1m$CURRENT_DISTRO\033[0m"
  if [ "$CURRENT_DISTRO" != "ubuntu" ]; then
    echo -e "\033[1;31mUbuntu is required.\033[0m"
    SUCCESS=0
    exit 1
  fi
}

set_cn_mirror() {
  if [ "$1" = "y" ]; then
    echo -e "Using \033[36;1mTUNA\033[0m mirror for apt."
    echo "Using Codename: $SYSTEM_CODENAME"
    if [ $DRY_RUN -ne 1 ]; then
      local APT_SOURCES_TRADITIONAL="deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute main restricted universe multiverse\ndeb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute main restricted universe multiverse\ndeb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-updates main restricted universe multiverse\ndeb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-updates main restricted universe multiverse\ndeb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-backports main restricted universe multiverse\ndeb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-backports main restricted universe multiverse\ndeb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-security main restricted universe multiverse\ndeb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-security main restricted universe multiverse\n# deb http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-proposed main restricted universe multiverse\n# deb-src http://mirrors.tuna.tsinghua.edu.cn/ubuntu/ resolute-proposed main restricted universe multiverse\n"
      local APT_SOURCES_DEB822="Types: deb deb-src\nURIs: http://mirrors.tuna.tsinghua.edu.cn/ubuntu\nSuites: resolute resolute-updates resolute-backports resolute-security\nComponents: main restricted universe multiverse\nSigned-By: /usr/share/keyrings/ubuntu-archive-keyring.gpg\n"
      if [ -f "$DEB822_LOCATION" ] || [ ${SYSTEM_VERSION_ID%%.*} -ge 24 ]; then
        mkdir -p /etc/apt/sources.list.d/
        echo -e "$APT_SOURCES_DEB822" > "$DEB822_LOCATION"
        if [ -f /etc/apt/sources.list ]; then
          mv /etc/apt/sources.list /etc/apt/sources.list.bak
        fi
      else
        echo -e "$APT_SOURCES_TRADITIONAL" > /etc/apt/sources.list
      fi
    fi
    return
  fi
  while true; do
    case "$(read -r -p $'Use APT mirror by \033[1;36mTUNA\033[0m? \033[1m[y/n]\033[0m ' _confirm && echo "${_confirm,,}")" in
      y|yes)
        set_cn_mirror y
        break
        ;;
      n|no)
        echo "Keep current mirror."
        break
        ;;
      *)
        ;;
    esac
  done
}

do_install_de() {
  local SIMULATE_OR_Y="$( [ $DRY_RUN -eq 1 ] && echo '--simulate' || echo '-y' )"
  local BASE_TOOLS_PKGS=(
    bash-completion sudo iproute2 net-tools iputils-ping
    nano vim procps curl wget git screen
  )
  if [ $MINIMAL -eq 0 ]; then
    local DE_PKGS=(
      dbus-x11 eject cups fonts-symbola 'fonts-noto*' xdg-utils
      yaru-theme-gtk yaru-theme-icon yaru-theme-sound  xfce4
      xfce4-notifyd xfce4-taskmanager xfce4-terminal thunar-archive-plugin
      thunar-media-tags-plugin xfce4-battery-plugin xfce4-clipman-plugin
      xfce4-cpufreq-plugin xfce4-cpugraph-plugin xfce4-diskperf-plugin
      xfce4-fsguard-plugin xfce4-genmon-plugin xfce4-mailwatch-plugin
      xfce4-netload-plugin xfce4-places-plugin xfce4-screenshooter
      xfce4-sensors-plugin xfce4-smartbookmark-plugin xfce4-systemload-plugin
      xfce4-timer-plugin xfce4-verve-plugin xfce4-wavelan-plugin
      xfce4-weather-plugin xfce4-whiskermenu-plugin xfce4-xkb-plugin
      xfce4-power-manager xfce4-indicator-plugin xfce4-mpc-plugin
    )
  else
  # Minimal installation
    local DE_PKGS=(
      dbus-x11 eject cups fonts-symbola xdg-utils
      xfce4-notifyd xfce4 xfce4-terminal
    )
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "apt update"
  else
    apt update || { echo -e "\033[31mAPT update failed!\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
  fi
  apt full-upgrade "$SIMULATE_OR_Y" || { echo -e "\033[33mUpgrade FAILED!\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
  apt install "$SIMULATE_OR_Y" "${BASE_TOOLS_PKGS[@]}" || { echo -e "\033[33mFailed to install some tools...\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); }
  apt install "$SIMULATE_OR_Y" --no-install-recommends "${DE_PKGS[@]}" || { echo -e "\033[31mFailed to install desktop...\033[0m"; SUCCESS=0; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
  apt autoremove --purge "$SIMULATE_OR_Y" || { echo -e "\033[31mFailed to apt autoremove --purge...\033[0m"; SUCCESS=0; WITH_ERROR=$((WITH_ERROR+1)); }
}

create_user_account() {
  # Arguments:
  # $1: UID
  # $2: Unix Username
  local NEW_UID="$1"
  local NEW_USERNAME="$2"
  local NEW_PASSWORD="$3"
  # Get UID ranges
  local UID_MIN=$(awk '/^UID_MIN/ {print $2}' /etc/login.defs 2>/dev/null || echo 1000)
  local UID_MAX=$(awk '/^UID_MAX/ {print $2}' /etc/login.defs 2>/dev/null || echo 60000)

  # Check UID
  while true; do
    echo "Acceptable UID range: $UID_MIN ~ $UID_MAX"
    if [ -n "$NEW_UID" ] && [[ "$NEW_UID" =~ ^[0-9]+$ ]] && [ "$NEW_UID" -ge "$UID_MIN" ] && [ "$NEW_UID" -le "$UID_MAX" ]; then
      echo -e "UID for new user is: \033[1m$NEW_UID\033[0m"
      break
    else
      if [ $DO_NOT_ASK -eq 1 ]; then
        echo -e "\033[31mERROR: Invalid or missing UID '$NEW_UID' in unattended mode! (Allowed range: $UID_MIN ~ $UID_MAX)\033[0m"
        SUCCESS=0
        WITH_ERROR=$((WITH_ERROR+1))
        exit $WITH_ERROR
      fi
      read -p "Enter UID for new user ($UID_MIN ~ $UID_MAX): " NEW_UID
    fi
  done

  # Check Username
  while true; do
    if [ -n "$NEW_USERNAME" ] && [[ "$NEW_USERNAME" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
      echo -e "UserName for new user is: \033[1m$NEW_USERNAME\033[0m"
      break
    else
      if [ $DO_NOT_ASK -eq 1 ]; then
        echo -e "\033[31mERROR: Invalid or missing username '$NEW_USERNAME' in unattended mode! (Must match ^[a-z_][a-z0-9_-]*$)\033[0m"
        SUCCESS=0
        WITH_ERROR=$((WITH_ERROR+1))
        exit $WITH_ERROR
      fi
      read -p "Enter a valid Unix username: " NEW_USERNAME
    fi
  done

  # Start to do create
  if [ $DRY_RUN -eq 1 ]; then
    echo -e "Create User \033[1m$NEW_USERNAME\033[0m with UID \033[1m$NEW_UID\033[0m with SHELL /bin/bash"
    (for g in "${COMMON_GROUPS[@]}" ; do echo -e "Invite \033[1m$NEW_USERNAME\033[0m into $g"; done)
  else
    useradd -m -u "$NEW_UID" -s /bin/bash "$NEW_USERNAME" && \
    (for g in "${COMMON_GROUPS[@]}" ; do usermod -aG "$g" "$NEW_USERNAME" || true; done)
  fi

  # Set password
  if [ -n "$NEW_PASSWORD" ]; then
    echo "Setting password non-interactively for $NEW_USERNAME..."
    [ $DRY_RUN -eq 1 ] && echo "run \`echo \"$NEW_USERNAME:$NEW_PASSWORD\" | chpasswd\`" || \
    echo "$NEW_USERNAME:$NEW_PASSWORD" | chpasswd
  else
    if [ $DO_NOT_ASK -eq 1 ]; then
      local DEFAULT_PASS="password"
      echo -e "\033[33mWARNING: No password provided in unattended mode! Setting to default:\033[0m $DEFAULT_PASS"
      [ $DRY_RUN -eq 1 ] && echo "run \`echo \"$NEW_USERNAME:$DEFAULT_PASS\" | chpasswd\`" || \
      echo "$NEW_USERNAME:$DEFAULT_PASS" | chpasswd
    else
      echo "Set password for $NEW_USERNAME (Interactive)"
      [ $DRY_RUN -ne 1 ] && passwd "$NEW_USERNAME"
    fi
  fi
}

cleanup() {
  echo -e "Total \033[34;1m${SECONDS}s\033[0m"
}
trap cleanup EXIT
check_root
check_distro
greeting

echo "Setting APT mirror..."
if [ $USE_CN_MIRROR -eq 1 ]; then
  set_cn_mirror y
elif [ $DO_NOT_ASK -eq 0 ]; then
  set_cn_mirror
fi

if [ $DO_NOT_ASK -eq 1 ] || [[ "$(read -r -p $'Contine install Xfce4 Desktop \033[1m[Y/n]\033[0m ' _confirm && echo "${_confirm,,}")" =~ ^(yes|y|)$ ]]; then
  do_install_de
else
  echo "Abort."
  exit 1
fi

echo "User account configuration..."
SHOULD_ADD_USER=0
if [ $ADD_USER -eq 1 ]; then
  if [ $DO_NOT_ASK -eq 1 ]; then
    SHOULD_ADD_USER=1
  else
    read -r -p "Create a new user account? [Y/n] " _confirm
    [[ "${_confirm,,}" =~ ^(yes|y|)$ ]] && SHOULD_ADD_USER=1
  fi
fi

if [ $SHOULD_ADD_USER -eq 1 ]; then
  create_user_account "$NEW_USER_UID" "$NEW_USER_USERNAME" "$NEW_USER_PASSWORD"
else
  echo "Will not create user."
fi

SUMMARY="\n"
[ $DRY_RUN -eq 1 ] && SUMMARY+="Dry run "
[ $SUCCESS -eq 1 ] && SUMMARY+="\033[32mSuccess\033[0m" || SUMMARY+="\033[32mFAILED\033[0m"
SUMMARY+=" with "
[ $WITH_ERROR -eq 0 ] && SUMMARY+="\033[34;1mNO ERROR.\033[0m" || SUMMARY+="\033[31;1m$WITH_ERROR ERROR(S)\033[0m!"
echo -e  "$SUMMARY"
exit $WITH_ERROR
