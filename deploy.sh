#!/bin/bash


usage()
{
    echo "usage: wget --no-cache -q -O- https://raw.githubusercontent.com/sec4us-training/treinamento-devsecops/main/deploy.sh | sudo bash"
}

info()
{
    whoami
    uname -a
    cat /etc/lsb-release
    lsb_release -a
    ip addr show
}


W='\033[0m'  # white (normal)
R='\033[31m' # red
G='\033[32m' # green
O='\033[33m' # orange
B='\033[34m' # blue
P='\033[35m' # purple
C='\033[36m' # cyan
GR='\033[37m' # gray
D='\033[2m'   # dims current color. {W} resets.

OK=$(echo -e "${W}${D}[${W}${G}+${W}${D}]${W}")
ERROR=$(echo -e "${O}[${R}!${O}]${W}")
WARN=$(echo -e "${W}[${C}?${W}]")
DEBUG=$(echo -e "${D}[${W}${B}*${W}${D}]${W}")

unset ansible_user
unset key
unset ip
unset status_file
unset PYTHON3

echo "IF9fX19fICAgICAgICAgICAgIF9fXyBfICAgXyBfX19fXwovICBfX198ICAgICAgICAgICAvICAgfCB8IHwgLyAgX19ffApcIGAtLS4gIF9fXyAgX19fIC8gL3wgfCB8IHwgXCBgLS0uCiBgLS0uIFwvIF8gXC8gX18vIC9ffCB8IHwgfCB8YC0tLiBcCi9cX18vIC8gIF9fLyAoX19cX19fICB8IHxffCAvXF9fLyAvClxfX19fLyBcX19ffFxfX198ICAgfF8vXF9fXy9cX19fXy8K" | base64 -d
echo " "
echo "Treinamento: DevSecOps"
echo "Linux Deploy"
echo " "
echo "Copyright © Sec4US® - Todos os direitos reservados. Nenhuma parte dos materiais disponibilizadas, incluindo este script, servidor, suas aplicações e seu código fonte, podem ser copiadas, publicadas, compartilhadas, redistribuídas, sublicenciadas, transmitidas, alteradas, comercializadas ou utilizadas para trabalhos sem a autorização por escrito da Sec4US"

if [ "$(id -u)" -ne 0 ]; then 
  usage
  echo -e "\n${ERROR} ${O}Execute este script como root${W}\n"
  info
  exit 1; 
fi

ansible_user=$(whoami)
status_file=/root/executed.txt

PYTHON3="/usr/bin/python3"

# Obter versão do Python (major.minor)
PY_VERSION="$($PYTHON3 - <<'EOF'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
EOF
)"

MAJOR="${PY_VERSION%%.*}"
MINOR="${PY_VERSION##*.}"

PIP_FLAGS=""

# Python 3.12+ exige --break-system-packages em muitos distros (PEP 668)
if [ "$MAJOR" -gt 3 ] || { [ "$MAJOR" -eq 3 ] && [ "$MINOR" -ge 12 ]; }; then
  PIP_FLAGS="--break-system-packages"
fi

echo -e "\n${OK} Python version: $PY_VERSION"
echo -e "${OK} pip flags: ${PIP_FLAGS:-<none>}"

grep "startup_script" "$status_file" >/dev/null 2>&1
if [ "$?" == "0" ]; then
    echo -e "${DEBUG} ${C}Pulando startup base...${W}"
else
    echo -e "\n${OK} Atualizando servidor"

    #Remove CDROM line from apt source list
    #  deb [check-date=no] file:///cdrom jammy main restricted
    cp /etc/apt/sources.list /tmp/
    grep -vE '^deb.*/cdrom.*' /tmp/sources.list > /etc/apt/sources.list

    DEBIAN_FRONTEND=noninteractive apt update
    DEBIAN_FRONTEND=noninteractive apt -y upgrade
    DEBIAN_FRONTEND=noninteractive apt install -y openssh-client openssh-server git wget vim zip unzip python3 python3-pip
    DEBIAN_FRONTEND=noninteractive apt remove -y ansible ansible-core

    echo -e "\n${OK} Configurando SSH"
    systemctl enable ssh
    systemctl start ssh

    echo -e "\n${OK} Instalando/atualizando versão do ansible core"
    $PYTHON3 -m pip install $PIP_FLAGS -U ansible 'ansible-core>=2.17.0' 'jinja2>=3.1.6' hvac
    if [ "$?" != "0" ]; then
        echo -e "${ERROR} ${O} Erro atualizando Ansible${W}\n"
        info
        exit 1
    fi

    echo "startup_script" >> "$status_file"
    echo -e "${OK} ${G}OK${W}"
fi

echo -e "\n${OK} Iniciando deploy"

echo -e "\n${OK} Gerando chaves SSH"
key="/tmp/sshkey"
if [ ! -f "$key" ]; then
  hostname devsecops
  hostnamectl set-hostname devsecops
  ssh-keygen -b 2048 -t rsa -f $key -q -N ""
fi

ip="127.0.0.1"

SSH_FILE=$key
# Verifica se o arquivo da chave SSH existe
if [ ! -f "$SSH_FILE" ]; then
    echo -e "${ERROR} ${O}Arquivo de chave privada do SSH inexistente: ${C}${SSH_FILE}${W}\n"
    info
    exit 1
fi

SSH_FILE_PUB="$key.pub"
# Verifica se o arquivo da chave SSH existe
if [ ! -f "$SSH_FILE_PUB" ]; then
    echo -e "${ERROR} ${O}Arquivo de chave pública do SSH inexistente: ${C}${SSH_FILE_PUB}${W}\n"
    info
    exit 1
fi

echo -e "\n${OK} Realizando o download dos scripts"
rm -rf /tmp/devsecops || true
git clone https://github.com/sec4us-training/treinamento-devsecops /tmp/devsecops
rsync -av /u01/tmp/devsecops/* /tmp/devsecops/ || true
pushd /tmp/devsecops


# Garante que o arquivo existe
VARS_FILE="vars.yml"
if [ ! -f "$VARS_FILE" ]; then
  echo -e "${ERROR} ${O}${VARS_FILE} não encontrado${W}\n"
  exit 1
fi

# Se a chave já existe, substitui; senão, adiciona
if grep -qE '^[[:space:]]*pip_extra_args:' "$VARS_FILE"; then
  sed -i \
    "s|^[[:space:]]*pip_extra_args:.*|pip_extra_args: \"${PIP_FLAGS}\"|" \
    "$VARS_FILE"
else
  echo "pip_extra_args: \"${PIP_FLAGS}\"" >> "$VARS_FILE"
fi

cp -f $SSH_FILE ssh_key.pem
cp -f $SSH_FILE_PUB ssh_key.pub
cp -f $SSH_FILE /tmp/web_api_ssh_key.pem
cp -f $SSH_FILE_PUB /tmp/web_api_ssh_key.pub
chmod 444 /tmp/web_api_ssh*
mkdir /root/.ssh/
cat ssh_key.pub >> /root/.ssh/authorized_keys

PK=$(cat ssh_key.pem)
PUBK=$(cat ssh_key.pub)

ansible_path=`command -v ansible-playbook 2> /dev/null`
if [ "$?" -ne "0" ] || [ "W$ansible_path" = "W" ]; then
  ansible_path=`which ansible-playbook 2> /dev/null`
  if [ "$?" -ne "0" ]; then
    ansible_path=""
  fi
fi

if [ "W$ansible_path" = "W" ]; then
  echo -e "${ERROR} ${O}A aplicação ansible-playbook parece não estar instalada.${W}\n\n"
  echo "Em ambientes debian/ubuntu, realize a instalação com os comandos abaixo:"
  echo "sudo apt install ansible"
  echo "ansible-galaxy collection install community.general"
  echo "ansible-galaxy collection install ansible.posix"
  echo "ansible-galaxy collection install ansible.windows"
  echo "ansible-galaxy collection install community.windows"
  echo "ansible-galaxy collection install community.hashi_vault"
  echo "ansible-galaxy collection install community.general"
  echo " "
  info
  exit 1
fi

echo -e "\n${OK} Instalando dependencias do ansible"
grep "ansible_deps" "$status_file" >/dev/null 2>&1
if [ "$?" == "0" ]; then
    echo -e "${DEBUG} ${C}Pulando instalação...${W}"
else
    
    ansible-galaxy collection install -U community.general
    ansible-galaxy collection install -U ansible.posix
    ansible-galaxy collection install -U ansible.windows
    ansible-galaxy collection install -U community.windows
    ansible-galaxy collection install -U community.hashi_vault
    ansible-galaxy collection install -U community.general
    echo "ansible_deps" >> "$status_file"
    echo -e "${OK} ${G}OK${W}"
fi

# remove a linha ansible_user do vars.yml
cp vars.yml vars_old.yml
grep -i -v "ansible_user" vars_old.yml > vars.yml

echo -e "\n${OK} Verificando senha padrão no arquivo vars.yml"
password=$(cat vars.yml | grep default_password | cut -d '"' -f2)
if [ "$?" -ne "0" ] || [ "W$password" = "W" ]; then
  echo -e "\n${ERROR} ${O}Senha do usuário ${C}webapi ${O}não definida no parâmetro ${C}'default_password' ${O}do arquivo vars.yml${W}\n"
  info
  exit 1
else
    echo -e "${OK} ${G}OK${W}"
fi

export OBJC_DISABLE_INITIALIZE_FORK_SAFETY=YES
export ANSIBLE_DEPRECATION_WARNINGS=False

# Check conectivity and if user has root privileges
echo -e "\n${OK} Verificando usuário"
ansible-playbook -i $ip,  --private-key $SSH_FILE  --extra-vars ansible_user=$ansible_user  --ssh-extra-args '-o StrictHostKeyChecking=no  -o UserKnownHostsFile=/dev/null' check_user.yml
if [ "$?" != "0" ]; then
    echo -e "${ERROR} ${O} Erro verificando usuário${W}\n"
    info
    exit 1
fi

# -----------------------------------------------------------------------------
# Loop principal de deploy
# -----------------------------------------------------------------------------

STEP_NUMBER=0

run_step() {
    local marker="$1"
    local playbook="$2"
    local label="$3"
    local pre_hook="$4"

    STEP_NUMBER=$((STEP_NUMBER + 1))

    echo -e "\n${OK} Executando passo ${STEP_NUMBER} - ${playbook}"
    if grep -q "${marker}" "$status_file" 2>/dev/null; then
        echo -e "${DEBUG} ${C}Pulando passo ${STEP_NUMBER}...${W}"
        return 0
    fi

    if [ -n "$pre_hook" ] && declare -F "$pre_hook" >/dev/null; then
        "$pre_hook"
    fi

    ansible-playbook -i "$ip," \
        --private-key "$SSH_FILE" \
        --extra-vars ansible_user="$ansible_user" \
        --ssh-extra-args '-o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null' \
        "$playbook"

    if [ "$?" != "0" ]; then
        echo -e "${ERROR} ${O} Erro executando ansible ${label}${W}\n"
        info
        exit 1
    fi

    echo "${marker}" >> "$status_file"
    echo -e "${OK} ${G}OK${W}"
}

fix_password_auth() {
    if [ "$(uname -s)" = "Darwin" ]; then
        sed -i "" "s/PasswordAuthentication no/PasswordAuthentication yes/g" "setup_base.yml"
    else
        sed -i "s/PasswordAuthentication no/PasswordAuthentication yes/g" "setup_base.yml"
    fi
}

# Cada entrada: "marker|playbook|label|pre_hook(opcional)"
DEPLOY_STEPS=(
    "step1_base|setup_base.yml|setup base|fix_password_auth"
    "step2_tools|setup_tools.yml|tools"
    "step3_docker|setup_docker.yml|Docker"
    "step4_vault|install_vault.yml|Vault"
    "step5_gitlab|install_gitlab.yml|Gitlab"
    "step6_jfrog|install_jfrog.yml|Artifactory"
    "step7_sonar|install_sonar.yml|Sonarqube"
    "step8_web01|install_web01.yml|Web01"
    "step9_jenkins|install_jenkins.yml|Jenkins"
    "gitlab_helvio|gitlab_helvio.yml|gitlab_helvio"
    "gitlab_bank|gitlab_bank.yml|gitlab_bank"
    "gitlab_sonar_helper|gitlab_sonar_helper.yml|gitlab_sonar_helper"
    "gitlab_webapi|gitlab_webapi.yml|gitlab_webapi"
    "gitlab_devsecops|gitlab_devsecops.yml|gitlab_devsecops"
    "gitlab_runner|gitlab_runner.yml|gitlab_runner"
)

for entry in "${DEPLOY_STEPS[@]}"; do
    IFS='|' read -r marker playbook label pre_hook <<< "$entry"
    run_step "$marker" "$playbook" "$label" "$pre_hook"
done

popd

echo -e "\n\n${O}===================================================${W}"
echo -e "${O} Deploy finalizado! ${W}"
echo -e "${O}===================================================${W}"

echo -e "${OK} Credenciais"
echo -e "     ${C}Usuário.:${O} secops${W}"
echo -e "     ${C}Senha...:${O} ${password}${W}"
echo ""
echo -e "${OK} Acessos"
echo -e "     ${C}IP......:${O} ${ip}${W}"
echo -e "     ${C}SSH.....:${O} Porta 22${W}"
echo " "

echo -e "${OK} Chaves"
echo -e "     ${C}Chave privada SSH.:${O}\n${PK}\n${W}"
echo -e "     ${C}Chave pública SSH.:${O}\n${PUBK}v${W}"
echo ""
