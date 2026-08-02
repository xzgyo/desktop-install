#!/bin/sh

# Author: xzgyo
set -e
set -o pipefail

# 常量
WILL_INSTALL_NAME="Xfce4"
WILL_INSTALL_TYPE="Desktop Environment"
TARGET_SYSTEM="Alpine Linux"
COMMON_GROUPS="cdrom floppy wheel audio dip video render plugdev users netdev scanner bluetooth lpadmin libvirt docker kvm"

# 变量
DRY_RUN=0
ADD_USER=1
USE_CN_MIRROR=0
APK_REPO="/etc/apk/repositories"
DO_NOT_ASK=0
MINIMAL=0
WITH_ERROR=0
SUCCESS=1

# 处理参数
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      echo "$0 [--dry-run] [--cn] [--do-not-add-user] [--new-uid=UID] [--new-user=USER] [--new-user-password=PASSWORD] [--do-not-ask] [--minimal]"
      echo "--cn argument will auto change Apk repo to mirrors.tuna.tsinghua.edu.cn."
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

check_distro() {
  local CURRENT_DISTRO="$( . /etc/os-release >/dev/null 2>&1 && echo "$ID" )"
  echo -e "The current distribution is \033[1m$CURRENT_DISTRO\033[0m"
  if [ "$CURRENT_DISTRO" != "alpine" ]; then
    printf '\033[1;31mAlpine Linux is required.\033[0m\n'
    SUCCESS=0
    exit 1
  fi
}

set_cn_mirror() {
  if [ "$1" = "y" ]; then
    printf 'Using \033[36;1mTUNA\033[0m mirror for apk.\n'
      sed -i 's#https\?://dl-cdn.alpinelinux.org/alpine#https://mirrors.tuna.tsinghua.edu.cn/alpine#g' $APK_REPO
    return
  fi
  while true; do
    printf 'Use Apk mirror by \033[1;36mTUNA\033[0m? \033[1m[y/n]\033[0m '
    read -r _confirm
    _confirm=$(echo "$_confirm" | tr '[:upper:]' '[:lower:]')
    case "$_confirm" in
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
  local BASE_TOOLS_PKGS="bash-completion sudo-rs iproute2 net-tools iputils nano vim procps-ng curl wget screen ca-certificates"
  local VGA_PKGS="mesa mesa-utils mesa-dri-gallium mesa-egl mesa-gl mesa-gles mesa-va-gallium vulkan-loader vulkan-tools mesa-vulkan-ati mesa-vulkan-intel mesa-vulkan-nouveau"
  if [ $MINIMAL -eq 0 ]; then
    local DE_PKGS="dbus cups xdg-utils font-noto-all pulseaudio pavucontrol xfce4 xfce4-terminal thunar-archive-plugin thunar-media-tags-plugin xfce4-battery-plugin xfce4-clipman-plugin xfce4-cpufreq-plugin xfce4-cpugraph-plugin xfce4-diskperf-plugin xfce4-fsguard-plugin xfce4-genmon-plugin xfce4-mailwatch-plugin xfce4-mpc-plugin xfce4-netload-plugin xfce4-notifyd xfce4-places-plugin xfce4-pulseaudio-plugin xfce4-screensaver xfce4-screenshooter xfce4-sensors-plugin xfce4-smartbookmark-plugin xfce4-systemload-plugin xfce4-taskmanager xfce4-timer-plugin xfce4-verve-plugin xfce4-wavelan-plugin xfce4-weather-plugin xfce4-whiskermenu-plugin xfce4-xkb-plugin"
  else
  # Minimal installation
    local DE_PKGS="dbus cups xdg-utils font-noto-all pulseaudio pavucontrol xfce4 xfce4-terminal"
  fi
  if [ $DRY_RUN -eq 1 ]; then
    echo "apk update"
    echo "apk upgrade"
    echo "Install packages: $BASE_TOOLS_PKGS"
    echo "Install packages: $VGA_PKGS"
    echo "Install packages: $DE_PKGS"
  else
    apk update || { printf '\033[31mapk update failed!\033[0m\n'; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
    apk upgrade || { printf '\033[31mapk upgrade failed!\033[0m\n'; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
    # shellcheck disable=SC2086
    apk add $BASE_TOOLS_PKGS || { printf '\033[33mFailed to install some tools...\033[0m\n'; WITH_ERROR=$((WITH_ERROR+1)); }
    # shellcheck disable=SC2086
    apk add $VGA_PKGS || { printf '\033[31mFailed to install video drivers (mesa)...\033[0m\n'; SUCCESS=0; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
    # shellcheck disable=SC2086
    apk add $DE_PKGS || { printf '\033[31mFailed to install desktop...\033[0m\n'; SUCCESS=0; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
  fi
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
    if [ -n "$NEW_UID" ] && case "$NEW_UID" in ''|*[!0-9]*) false ;; *) true ;; esac && [ "$NEW_UID" -ge "$UID_MIN" ] && [ "$NEW_UID" -le "$UID_MAX" ]; then
      printf 'UID for new user is: \033[1m%s\033[0m\n' "$NEW_UID"
      break
    else
      if [ $DO_NOT_ASK -eq 1 ]; then
        printf '\033[31mERROR: Invalid or missing UID '\''%s'\'' in unattended mode! (Allowed range: %s ~ %s)\033[0m\n' "$NEW_UID" "$UID_MIN" "$UID_MAX"
        SUCCESS=0
        WITH_ERROR=$((WITH_ERROR+1))
        exit $WITH_ERROR
      fi
      printf "Enter UID for new user (%s ~ %s): " "$UID_MIN" "$UID_MAX"
      read -r NEW_UID
    fi
  done

  # Check Username
  while true; do
    if [ -n "$NEW_USERNAME" ] && echo "$NEW_USERNAME" | grep -qE '^[a-z_][a-z0-9_-]*$'; then
      printf 'UserName for new user is: \033[1m%s\033[0m\n' "$NEW_USERNAME"
      break
    else
      if [ $DO_NOT_ASK -eq 1 ]; then
        printf '\033[31mERROR: Invalid or missing username '\''%s'\'' in unattended mode! (Must match ^[a-z_][a-z0-9_-]*$)\033[0m\n' "$NEW_USERNAME"
        SUCCESS=0
        WITH_ERROR=$((WITH_ERROR+1))
        exit $WITH_ERROR
      fi
      printf "Enter a valid Unix username: "
      read -r NEW_USERNAME
    fi
  done

  # Start to do create
  if [ $DRY_RUN -eq 1 ]; then
    printf 'Create User \033[1m%s\033[0m with UID \033[1m%s\033[0m with SHELL /bin/bash\n' "$NEW_USERNAME" "$NEW_UID"
    for g in $COMMON_GROUPS; do
      printf 'Invite \033[1m%s\033[0m into %s\n' "$NEW_USERNAME" "$g"
    done
  else
    useradd -m -u "$NEW_UID" -s /bin/bash "$NEW_USERNAME" && \
    for g in $COMMON_GROUPS; do usermod -aG "$g" "$NEW_USERNAME" || true; done
  fi

  # Set password
  if [ -n "$NEW_PASSWORD" ]; then
    echo "Setting password non-interactively for $NEW_USERNAME..."
    if [ $DRY_RUN -eq 1 ]; then
      echo "run \`echo \"$NEW_USERNAME:$NEW_PASSWORD\" | chpasswd\`"
    else
      echo "$NEW_USERNAME:$NEW_PASSWORD" | chpasswd
    fi
  else
    if [ $DO_NOT_ASK -eq 1 ]; then
      local DEFAULT_PASS="password"
      printf '\033[33mWARNING: No password provided in unattended mode! Setting to default:\033[0m %s\n' "$DEFAULT_PASS"
      if [ $DRY_RUN -eq 1 ]; then
        echo "run \`echo \"$NEW_USERNAME:$DEFAULT_PASS\" | chpasswd\`"
      else
        echo "$NEW_USERNAME:$DEFAULT_PASS" | chpasswd
      fi
    else
      echo "Set password for $NEW_USERNAME (Interactive)"
      if [ $DRY_RUN -ne 1 ]; then
        passwd "$NEW_USERNAME"
      fi
    fi
  fi
}

cleanup() {
  local ELAPSED=$(($(date +%s) - START_TIME))
  printf 'Total \033[34;1m%ss\033[0m\n' "$ELAPSED"
}
trap cleanup EXIT
START_TIME=$(date +%s)
check_root
check_distro
greeting

echo "Setting Apk mirror..."
if [ $USE_CN_MIRROR -eq 1 ]; then
  set_cn_mirror y
elif [ $DO_NOT_ASK -eq 0 ]; then
  set_cn_mirror
fi

if [ $DO_NOT_ASK -eq 1 ]; then
  do_install_de
else
  printf 'Continue install Xfce4 Desktop \033[1m[Y/n]\033[0m '
  read -r _confirm
  _confirm=$(echo "$_confirm" | tr '[:upper:]' '[:lower:]')
  case "$_confirm" in
    y|yes|'') do_install_de ;;
    *) echo "Abort."; exit 1 ;;
  esac
fi

echo "User account configuration..."
SHOULD_ADD_USER=0
if [ $ADD_USER -eq 1 ]; then
  if [ $DO_NOT_ASK -eq 1 ]; then
    SHOULD_ADD_USER=1
  else
    printf 'Create a new user account? [Y/n] '
    read -r _confirm
    _confirm=$(echo "$_confirm" | tr '[:upper:]' '[:lower:]')
    case "$_confirm" in
      y|yes|'') SHOULD_ADD_USER=1 ;;
    esac
  fi
fi

if [ $SHOULD_ADD_USER -eq 1 ]; then
  create_user_account "$NEW_USER_UID" "$NEW_USER_USERNAME" "$NEW_USER_PASSWORD"
else
  echo "Will not create user."
fi

SUMMARY="\n"
[ $DRY_RUN -eq 1 ] && SUMMARY="${SUMMARY}Dry run "
if [ $SUCCESS -eq 1 ]; then
  SUMMARY="${SUMMARY}\033[32mSuccess\033[0m"
else
  SUMMARY="${SUMMARY}\033[32mFAILED\033[0m"
fi
SUMMARY="${SUMMARY} with "
if [ $WITH_ERROR -eq 0 ]; then
  SUMMARY="${SUMMARY}\033[34;1mNO ERROR.\033[0m"
else
  SUMMARY="${SUMMARY}\033[31;1m$WITH_ERROR ERROR(S)\033[0m!"
fi
printf '%b\n' "$SUMMARY"
exit $WITH_ERROR
