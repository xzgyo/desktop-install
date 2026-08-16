#!/usr/bin/env bash

# Author: xzgyo
set -e
set -o pipefail

# 常量
WILL_INSTALL_NAME="OpenCode"
WILL_INSTALL_TYPE="with basics development tools"
TARGET_SYSTEM="Arch Linux"
COMMON_GROUPS=(cdrom floppy wheel audio dip video render plugdev users netdev scanner bluetooth lpadmin libvirt docker kvm)

# 变量
DRY_RUN=0
ADD_USER=1
USE_CN_MIRROR=0
PACMAN_MIRRORLIST="/etc/pacman.d/mirrorlist"
DO_NOT_ASK=0
WITH_ERROR=0
SUCCESS=1

# 处理参数
while [ $# -gt 0 ]; do
  case "$1" in
    --help)
      echo "$0 [--dry-run] [--cn] [--do-not-add-user] [--new-uid=UID] [--new-user=USER] [--new-user-password=PASSWORD] [--do-not-ask]"
      echo "--cn argument will auto change Pacman repo to mirrors.tuna.tsinghua.edu.cn."
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
    --do-not-ask)
      DO_NOT_ASK=1
      shift
      ;;
    --use-preset|--w-up)
      # DO NOT USE THIS!!!
      DO_NOT_ASK=1
      USE_CN_MIRROR=1
      ADD_USER=1
      NEW_USER_UID="1000"
      NEW_USER_USERNAME="user"
      NEW_USER_PASSWORD="123"
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
  if [ "$CURRENT_DISTRO" != "arch" ]; then
    echo -e "\033[1;31mArch Linux is required.\033[0m"
    SUCCESS=0
    exit 1
  fi
}

set_cn_mirror() {
  if [ "$1" = "y" ]; then
    echo -e "Using \033[36;1mTUNA\033[0m mirror for pacman."
      echo 'Server = https://mirrors.tuna.tsinghua.edu.cn/archlinux/$repo/os/$arch' | tee $PACMAN_MIRRORLIST
    return
  fi
  while true; do
    case "$(read -r -p $'Use Pacman mirror by \033[1;36mTUNA\033[0m? \033[1m[y/n]\033[0m ' _confirm && echo "${_confirm,,}")" in
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
  local BASE_TOOLS_PKGS=(
    bash-completion sudo-rs iproute2 net-tools iputils nano vi vim procps-ng curl wget
    screen ca-certificates git base-devel
  )
  local OC_PKG="opencode"
  if [ $DRY_RUN -eq 1 ]; then
    echo "pacman -Syyuu --noconfirm"
    echo "Install packages: ${BASE_TOOLS_PKGS[@]}"
    echo "Install OpenCode"
  else
    pacman -Syyuu --noconfirm || { echo -e "\033[31mpacman -Syyuu failed!\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
    pacman -S --noconfirm "${BASE_TOOLS_PKGS[@]}" || { echo -e "\033[33mFailed to install tools...\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
    pacman -S --noconfirm "$OC_PKG" || { echo -e "\033[33mFailed to install OpenCode...\033[0m"; WITH_ERROR=$((WITH_ERROR+1)); exit $WITH_ERROR; }
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
    echo -e "Try to visudo..."
  else
    useradd -m -u "$NEW_UID" -s /bin/bash "$NEW_USERNAME" && \
    (for g in "${COMMON_GROUPS[@]}" ; do usermod -aG "$g" "$NEW_USERNAME" || true; done)
    sed -i 's/# %wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/g' /etc/sudoers
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

echo "Setting Pacman mirror..."
if [ $USE_CN_MIRROR -eq 1 ]; then
  set_cn_mirror y
elif [ $DO_NOT_ASK -eq 0 ]; then
  set_cn_mirror
fi

if [ $DO_NOT_ASK -eq 1 ] || [[ "$(read -r -p $'Contine install? \033[1m[Y/n]\033[0m ' _confirm && echo "${_confirm,,}")" =~ ^(yes|y|)$ ]]; then
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
