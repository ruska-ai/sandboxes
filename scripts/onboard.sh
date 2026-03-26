#!/usr/bin/env bash
set -euo pipefail

# Interactive first-login package installer.
# Extend this list with more tools as needed.
TOOLS=(
  "curl|curl|cURL command-line HTTP client"
  "gh|gh|GitHub CLI"
  "tmux|tmux|Terminal multiplexer"
  "jq|jq|Command-line JSON processor"
  "telnet|telnet|Telnet client"
  "unzip|unzip|ZIP archive extractor"
  "git|git|Distributed version control system"
)

selected_packages=()
install_nvm=false
install_agent_browser=false
generate_ssh_key=false

ask_install() {
  local key="$1"
  local pkg="$2"
  local description="$3"
  local answer

  while true; do
    read -r -p "Install ${key} (${description})? [y/N]: " answer
    case "${answer}" in
      y|Y|yes|YES)
        selected_packages+=("${pkg}")
        return
        ;;
      n|N|no|NO|"")
        return
        ;;
      *)
        echo "Please answer y or n."
        ;;
    esac
  done
}

echo "Developer setup installer"
echo "Choose which packages to install."
echo

for tool in "${TOOLS[@]}"; do
  IFS="|" read -r key pkg description <<< "${tool}"
  ask_install "${key}" "${pkg}" "${description}"
done

while true; do
  read -r -p "Install nvm and set default Node.js to 22? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      install_nvm=true
      break
      ;;
    n|N|no|NO|"")
      break
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

while true; do
  read -r -p "Install agent-browser and system dependencies? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      install_agent_browser=true
      break
      ;;
    n|N|no|NO|"")
      break
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

while true; do
  read -r -p "Generate SSH key at ~/.ssh/id_ed25519? [y/N]: " answer
  case "${answer}" in
    y|Y|yes|YES)
      generate_ssh_key=true
      break
      ;;
    n|N|no|NO|"")
      break
      ;;
    *)
      echo "Please answer y or n."
      ;;
  esac
done

if [ "${#selected_packages[@]}" -eq 0 ] && [ "${install_nvm}" = false ] && [ "${install_agent_browser}" = false ] && [ "${generate_ssh_key}" = false ]; then
  echo
  echo "No packages selected. Exiting."
  exit 0
fi

if [ "${#selected_packages[@]}" -gt 0 ]; then
  echo
  echo "Installing apt packages: ${selected_packages[*]}"
  sudo apt-get update
  sudo apt-get install -y "${selected_packages[@]}"
fi

if [ "${install_nvm}" = true ]; then
  if ! command -v curl >/dev/null 2>&1; then
    echo
    echo "curl is required for nvm; installing curl first."
    sudo apt-get update
    sudo apt-get install -y curl
  fi

  echo
  echo "Installing nvm and setting default Node.js to 22..."
  export NVM_DIR="${HOME}/.nvm"

  if [ ! -s "${NVM_DIR}/nvm.sh" ]; then
    curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.3/install.sh | bash
  fi

  # shellcheck disable=SC1090
  source "${NVM_DIR}/nvm.sh"
  nvm install 22
  nvm alias default 22
fi

if [ "${install_agent_browser}" = true ]; then
  if ! command -v npm >/dev/null 2>&1; then
    export NVM_DIR="${HOME}/.nvm"
    if [ -s "${NVM_DIR}/nvm.sh" ]; then
      # shellcheck disable=SC1090
      source "${NVM_DIR}/nvm.sh"
    fi
  fi

  if ! command -v npm >/dev/null 2>&1; then
    echo
    echo "npm is required for agent-browser. Install Node.js (for example via nvm) and run 'onboard' again."
    exit 1
  fi

  echo
  echo "Installing Codex CLI, agent-browser, and dependencies..."
  npm install -g @openai/codex
  npm install -g agent-browser
  agent-browser install --with-deps
fi

if [ "${generate_ssh_key}" = true ]; then
  if ! command -v ssh-keygen >/dev/null 2>&1; then
    echo
    echo "ssh-keygen not found; installing openssh-client first."
    sudo apt-get update
    sudo apt-get install -y openssh-client
  fi

  key_path="${HOME}/.ssh/id_ed25519"
  pub_key_path="${key_path}.pub"

  mkdir -p "${HOME}/.ssh"
  chmod 700 "${HOME}/.ssh"

  if [ -f "${key_path}" ] || [ -f "${pub_key_path}" ]; then
    while true; do
      read -r -p "SSH key already exists at ${key_path}. Overwrite? [y/N]: " answer
      case "${answer}" in
        y|Y|yes|YES)
          rm -f "${key_path}" "${pub_key_path}"
          break
          ;;
        n|N|no|NO|"")
          echo "Keeping existing SSH key."
          break
          ;;
        *)
          echo "Please answer y or n."
          ;;
      esac
    done
  fi

  if [ ! -f "${key_path}" ]; then
    echo
    echo "Generating SSH key at ${key_path}..."
    ssh-keygen -t ed25519 -f "${key_path}" -N "" -C "${USER}@$(hostname)"
    chmod 600 "${key_path}"
    chmod 644 "${pub_key_path}"
    echo "SSH public key: ${pub_key_path}"
  fi
fi

echo
echo "Install complete."
echo "Run 'onboard' again any time to add more tools."
