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
| `prepare` | `prepare` | recupera/gera o par de chaves do laboratório, autoriza a pública no root e ajusta o `pip_extra_args` |
| `base` | `base` | `setup_base`, `setup_tools`, `setup_docker`, `setup_powershell` |
| `platform` | `vault` → `gitlab` → `jfrog` → `sonar` | os serviços da plataforma, na ordem do `deploy.sh` |
| `ci` | `jenkins` → `azure-devops` → `jenkins-sonar` → `web01` → `gitlab-runner` | Jenkins e runners, a integração com o Sonar, o Web01 e os runners do GitLab |
| `projects` | `projects` | os seis repositórios da turma no GitLab |
| `finish` | `lab-files`, `credentials` | arquivos extras da turma e as credenciais de acesso ao servidor |

A ordem do `platform`/`ci` **importa**: o GitLab, o JFrog, o SonarQube e o
Jenkins guardam no Vault as credenciais que sorteiam, e os playbooks seguintes as
leem de lá (`vault_token_*.yml`). Vault fora do ar = o resto não sobe.

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
