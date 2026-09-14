# Deploy pelo vm_manager (`.sec4us-ci.yml`)

Este laboratório passou a ter uma segunda forma de ser provisionado: a
**orquestração de laboratório** do vm_manager (Deploy → Laboratórios). O fluxo
antigo (`deploy.sh` rodando dentro do próprio servidor) continua no repositório e
segue funcionando — os dois usam os **mesmos playbooks**, na **mesma ordem**.

## O que muda

| Antes (`deploy.sh`) | Agora (`.sec4us-ci.yml`) |
|---------------------|--------------------------|
| você instala o Ubuntu à mão e roda o script dentro dele | a VM vem de um **template de deploy** do vm_manager (uma linha em `machines:`) |
| controller = alvo (o ansible roda no próprio servidor) | controller = **orquestrador**; o ansible fala com o servidor por SSH |
| o script instala ansible, pip e as collections no alvo | o orquestrador já tem o ansible; as collections saem do `requirements.yml` |
| `ssh-keygen` + `cat ssh_key.pub >> /root/.ssh/authorized_keys` no script | job `prepare` (`ci_prepare.yml`), com o par guardado como artefato |
| ordem garantida pelo `for` do `DEPLOY_STEPS` | `stages` + `needs` + `retries`/`delay` por job |
| `/root/executed.txt` marca o que já rodou | retomada por passo, na tela do laboratório |
| acompanhamento pelo terminal | tela do laboratório (pipeline no formato do GitLab, com log por passo) |
| recriação manual | `recreate` agendado a cada X dias |

O `vars.yml` **não** é gerado pelo pipeline: neste repositório ele é versionado e
continua sendo a fonte da verdade dos dois fluxos (hostnames, `local_username`,
`default_password`). A única linha que o pipeline reescreve é a do
`pip_extra_args`, pelo mesmo motivo e com o mesmo critério do `deploy.sh`.

## Pré-requisitos no vm_manager

1. Um **template de deploy Linux** em produção. O nome usado aqui é
   `Ubuntu 22.04` — ajuste em `machines: template:` se o seu tiver outro.
2. Um **servidor VMware** cadastrado; ele é o destino padrão do laboratório.
3. Saída para a internet a partir do servidor do laboratório: o deploy baixa
   GitLab, Jenkins, SonarQube, JFrog, imagens Docker e os pacotes do apt.

## Como executar

1. **Deploy → Laboratórios → Novo laboratório**: nome, URL deste repositório,
   servidor VMware e, se quiser, o recreate a cada X dias.
2. **Sincronizar e validar** → **Migrar para produção**.
3. **Executar**. O pipeline cria a VM e instala o ecossistema inteiro.

Reserve tempo: é um deploy longo (GitLab, SonarQube, JFrog e o build da imagem
do agente do Azure DevOps são os trechos mais demorados).

## O pipeline

| Stage | Jobs | O que faz |
|-------|------|-----------|
| `network` | `lab-network`, `lab-network-win` | move a placa de cada máquina para o portgroup do laboratório e aplica o IP fixo |
| `proxy` | `proxy-linux`, `proxy-win` | grava o proxy de saída, de forma persistente, nas duas máquinas e nos containers |
| `prepare` | `prepare` | recupera/gera o par de chaves do laboratório, autoriza a pública no root e ajusta o `pip_extra_args` |
| `base` | `base` | `setup_base`, `setup_tools`, `setup_docker`, `setup_powershell` |
| `platform` | `vault` → `gitlab` → `jfrog` → `sonar` | os serviços da plataforma, na ordem do `deploy.sh` |
| `ci` | `jenkins` → `azure-devops` → `jenkins-sonar` → `web01` → `gitlab-runner` | Jenkins e runners, a integração com o Sonar, o Web01 e os runners do GitLab |
| `windows-ci` | `jenkins-runner-win` | o agente do Jenkins na VM Windows |
| `projects` | `projects` | os seis repositórios da turma no GitLab |
| `finish` | `lab-files`, `credentials` | arquivos extras da turma e as credenciais de acesso ao servidor |

O pipeline é **sequencial**: os jobs rodam um por vez, na ordem do stage e, dentro
do stage, na ordem do arquivo. O `needs` não paraleliza nada — ele decide o que é
PULADO quando uma dependência falha.

A ordem do `platform`/`ci` **importa**: o GitLab, o JFrog, o SonarQube e o
Jenkins guardam no Vault as credenciais que sorteiam, e os playbooks seguintes as
leem de lá (`vault_token_*.yml`). Vault fora do ar = o resto não sobe.

## A rede e a troca de IP

A VM nasce na rede do template, com o endereço que o provisionamento deu, e só
depois vai para a rede do laboratório com o IP fixo. É o **primeiro** stage, e
nada roda antes dele: o `setup_base.yml` escreve o `/etc/hosts`, gera o
certificado e sobe o Nginx com o endereço da máquina — refazer a rede depois
seria refazer tudo.

São dois passos, nesta ordem:

1. **`network: "$REDE_LAB"`** — move a placa para o portgroup do laboratório
   (`Rede_30`). É feito direto no vSphere, sem falar com o guest, e precisa vir
   primeiro: o `192.168.30.249` só existe nessa rede. A placa é desconectada e
   reconectada logo depois, para o guest renovar o DHCP na rede nova.
2. **o IP fixo**, num `script:` de bash. Ele desliga a configuração de rede do
   cloud-init (senão o IP some no primeiro reboot), escreve
   `/etc/netplan/99-lab-static.yaml` — o `99-` vence o `50-cloud-init.yaml` na
   mesclagem, chave a chave —, valida com `netplan generate` e agenda o
   `netplan apply` destacado. O `apply` derruba a sessão SSH: o passo devolve OK
   antes disso, e o orquestrador reencontra a máquina no IP fixo.

Entre um passo e outro o orquestrador procura a máquina: primeiro no IP fixo,
depois no endereço atual e, se ela sumiu dos dois, pergunta ao VMware Tools qual
endereço ela pegou.

> **A `$REDE_LAB` precisa ter DHCP.** O passo do IP fixo roda *dentro* da
> máquina, e é pelo endereço do DHCP que o orquestrador a reencontra entre a
> troca de placa e a aplicação do endereço estático.

Rede e endereçamento ficam em `variables:` (`REDE_LAB`, `STATIC_IP`,
`NETMASK_CIDR`, `GATEWAY`, `UPSTREAM_DNS_1`, `UPSTREAM_DNS_2`). O `STATIC_IP`
tem que ser o mesmo `ip:` declarado em `machines:` — é por ele que o motor
reencontra a VM.

Nenhum playbook do repositório mexe em rede: isso é do laboratório, não do
servidor DevSecOps, e o `deploy.sh` nem sabe que essa rede existe. Por isso o
passo é um `script:` dentro do próprio `.sec4us-ci.yml`.

## O proxy de saída

A `Rede_30` não tem rota direta para a internet: tudo que sai passa pelo proxy em
`192.168.30.1:8080`. Isso chega às máquinas por dois caminhos, e os dois são
necessários:

1. **como ambiente do passo** — `variables:` vira o ambiente de todo passo, então
   cada `script:` já nasce com `HTTP_PROXY`/`HTTPS_PROXY`/`NO_PROXY` exportados
   (no Linux como `export`, no Windows como environment da task `win_shell`);
2. **gravado nas máquinas**, no stage `proxy`. É o que vale para os passos
   `ansible:`: o ambiente deles fica no processo do `ansible-playbook`, que roda
   no **orquestrador**, e não atravessa o SSH/WinRM até os módulos.

O stage `proxy` vem antes do `prepare` porque o primeiro download do laboratório
é o `apt update` do `setup_base.yml` — sem proxy o pipeline trava ali.

No **servidor Linux** ele grava:

| Onde | Para quê |
|------|----------|
| `/etc/environment` | o `pam_env` aplica em toda sessão SSH, inclusive as não interativas do ansible — é o que faz `apt`, `pip`, `get_url` e `uri` saírem pelo proxy sem o playbook saber |
| `/etc/profile.d/99-lab-proxy.sh` | shells de login (o aluno no terminal, os Jenkinsfile) |
| `/etc/apt/apt.conf.d/99-lab-proxy` | o apt quando roda pelo systemd, que não vê o ambiente do shell |
| `/etc/systemd/system/docker.service.d/http-proxy.conf` | o **daemon** do docker, que é quem faz `docker pull` |
| `/root/.docker/config.json` (`proxies.default`) | os **containers**: o docker injeta isso como build-arg no `docker build` e como ambiente no `docker run`/`compose up` |

O `config.json` é **mesclado** com `python3`, não sobrescrito — o mesmo arquivo
guarda o `auths` do `docker login` no registry do laboratório.

No **runner Windows**:

| Onde | Para quê |
|------|----------|
| variáveis de ambiente da máquina | toda sessão nova (WinRM, tarefa agendada, serviço); é o que `git` e `curl` leem |
| `netsh winhttp set proxy` | os **serviços** — inclusive a tarefa agendada do agente, que roda como SYSTEM |
| WinINET (`HKCU` e `HKU\.DEFAULT`) | o `Invoke-WebRequest` do PowerShell 5.1, que **não** lê as variáveis de ambiente |

Os dois jobs rodam com `force: true`: a configuração é persistente, mas reaplicar
é barato e garante o estado depois de um snapshot revertido.

> O `NO_PROXY` não é detalhe: os `*.labs.sec4us.com.br` resolvem para `127.0.0.1`
> no servidor e o registry local é um deles. Sem as exceções, o laboratório
> tentaria falar consigo mesmo através do proxy.

Ele vale **dentro dos containers** também, que herdam as variáveis do
`proxies.default`. Por isso a lista tem `0.0.0.0` (o endereço "unspecified" não é
loopback, então a lib de HTTP do Go o manda para o proxy) e `172.16.0.0/12` (as
bridges do docker, onde ficam o `host-gateway` e os containers falando entre si).

Um efeito desse tipo é silencioso: quando o `VAULT_ADDR` do container do Vault
era `http://0.0.0.0:8200`, o `vault status` do entrypoint levava 403 do proxy, o
laço de espera estourava e o Vault ficava **selado** — de pé, com a porta 8200
respondendo, e o deploy seguindo em frente. Endereço que um cliente disca dentro
de um container deve ser loopback; o Go isenta loopback sempre, sem depender de
`NO_PROXY`.

> Variável de ambiente de container é fixada na **criação**. Mudar o `NO_PROXY`
> aqui não alcança containers que já existem — eles precisam ser recriados
> (`docker compose up -d --force-recreate`, ou uma execução nova do stage que os
> cria).

## O par de chaves do laboratório

O `deploy.sh` gera um par de chaves, autoriza a pública no `secops` e no `root` e
guarda a privada no Vault (`secret/devops-server/ssh`) — é esse o caminho da
prática: achar o segredo no Vault e virar root no servidor.

No pipeline isso é o job `prepare` (`ci_prepare.yml`). O detalhe que obriga o
artefato: o orquestrador **substitui o diretório do repositório a cada
sincronização** e **pula os passos já concluídos** numa retomada. Um par gerado
de novo depois do `install_vault` deixaria o segredo do Vault sem acesso nenhum.
Por isso o job faz, nesta ordem:

1. `download-artifact: ssh-key` (com `ignore_error`, porque na primeira execução
   não há nada guardado);
2. `ci_prepare.yml` — gera o par só se a privada não veio, e reconstrói a pública
   a partir dela se só a pública faltar;
3. `upload-artifact: ssh-key`.

Destruir a máquina ou recriá-la do zero abre uma **geração nova** de artefatos, e
o par também é novo — o que é o certo: a VM é outra.

## `pip_extra_args` e o PEP 668

A partir do Ubuntu 23.04 / Debian 12 o python do sistema é gerenciado pela distro
e o `pip` recusa instalar sem `--break-system-packages`; nas imagens anteriores o
`pip` não conhece a opção, e passá-la quebra o `setup_tools`. O `deploy.sh`
decide isso pela versão do python do alvo; o `ci_prepare.yml` decide pelo
marcador `/usr/lib/python3*/EXTERNALLY-MANAGED` e reescreve a linha no `vars.yml`
do diretório do laboratório.

O job `prepare` roda com `force: true` — em **toda** execução, mesmo nas
retomadas — justamente porque o `vars.yml` volta ao conteúdo do repositório a
cada sincronização.

## Variáveis do pipeline

Estão em `variables:` e valem como variável de ambiente do passo (é assim que os
playbooks as leem, com `lookup('env', ...)`):

| Variável | Para quê |
|----------|----------|
| `REDE_LAB` | portgroup do laboratório, para onde a placa é movida no stage `network` |
| `STATIC_IP` / `NETMASK_CIDR` / `GATEWAY` | endereçamento fixo aplicado no guest; o `STATIC_IP` tem que bater com o `ip:` de `machines:` |
| `UPSTREAM_DNS_1` / `UPSTREAM_DNS_2` | resolvedores do servidor depois da troca de rede |
| `HTTP_PROXY` / `HTTPS_PROXY` (e os minúsculos) | proxy de saída do laboratório; ver "O proxy de saída" |
| `NO_PROXY` / `no_proxy` | o que NÃO passa pelo proxy: loopback, a sub-rede do lab e os `*.labs.sec4us.com.br` |
| `ADITIONAL_FILES_PATH` | diretório **no orquestrador** com os arquivos extras da turma; o `sync_lab_files.yml` os copia para `/u01/lab_files`. Vazio = não copia nada |
| `SKIP_BUILD` | `true` pula o build/push da imagem do agente do Azure DevOps e reaproveita a que já está no registry |

> As variáveis do pipeline também chegam aos playbooks como **extra-vars**, que
> vencem o `vars.yml`. Não repita aqui nenhum nome que já exista lá — a menos que
> a intenção seja exatamente sobrescrevê-lo.

## Credenciais

As senhas e tokens dos serviços já saem dos próprios playbooks de instalação, com
o marcador `__SEC4US_CRED__::<nome>::<valor>` (Vault Token, GitLab Root Password,
GitLab Token, JFrog Admin Password, JFrog Access Token, Sonar Admin Password,
Sonar Admin Token, Jenkins Admin Password). Elas aparecem na tela de credenciais
da máquina.

O job `credentials` (`ci_creds.yml`) fecha a lista com o que o `deploy.sh`
imprimia no final: usuário e senha do servidor e o endereço do Squid. A chave SSH
privada não entra ali — o marcador lê uma linha só, e ela está no Vault, que é
onde a prática espera encontrá-la.

## Arquivos novos

| Arquivo | Papel |
|---------|-------|
| `.sec4us-ci.yml` | máquina, stages e jobs |
| `ci_prepare.yml` | par de chaves, `authorized_keys` do root e `pip_extra_args` |
| `ci_creds.yml` | credenciais de acesso ao servidor |
| `requirements.yml` | collections do ansible instaladas pelo orquestrador |

`config.yml`, `ansible.cfg`, `ssh_key.pem` e `ssh_key.pub` são gerados em tempo
de execução (estão no `.gitignore`).

## Ainda usando o fluxo antigo?

Nada foi removido nem alterado. O `deploy.sh` continua sendo o caminho descrito
no `README.md`, e nenhum dos playbooks existentes foi tocado para o pipeline
funcionar — `ci_prepare.yml`, `ci_creds.yml` e `requirements.yml` são arquivos
novos, que o `deploy.sh` não chama.
