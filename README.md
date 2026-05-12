# Treinamento DevOps Ecosystem Exploits

Este arquivo tem por objetivo catalogar os comandos utilizados durante o treinamento

## Copyright

Arquivo pertencente ao treinamento de DevOps Ecosystem Exploits
Autor: Sec4US - Hélvio Junior (M4v3r1ck)

**Proibida a reprodução ou publicação deste material sem prévia autorização expressa**

---

## Sobre

Este é um procedimento que realiza a configuração completa de um servidor Linux para as práticas e testes realizados durante o treinamento de DevSecOps da Sec4US.

Conheça mais sobre nosso treinamento em: https://sec4us.com.br/treinamentos/devops-ecosystem-exploits/

## Aviso de Segurança

> [!CAUTION]
> Este ambiente contém **vulnerabilidades que podem permitir o comprometimento total
> do servidor** (credenciais padrão, serviços sem hardening e cenários propositalmente
> exploráveis para as práticas do treinamento). Por esse motivo, **NÃO deve ser
> disponibilizado publicamente na internet**. Mantenha o lab em rede privada/restrita
> (VPN, allow-list de IP ou acesso somente via o Squid do próprio lab) enquanto o
> treinamento estiver em andamento e desligue/derrube o servidor ao final.

## Ambiente

> [!WARNING] 
> O "alvo" servidor de deploy, deve ser um ubuntu linux e todos os seus dados poderão ser destruídos, sendo assim NÃO execute este procedimento em um servidor com dados que não podem ser perdidos.

O servidor (ou alvo) deve ser um Ubuntu Linux que será o alvo de todo o procedimento de instalação. Recomenda-se que o servidor seja um Ubuntu Linux 22.04 ou superior, recentemente instalado e sem nenhuma informação que possa ser perdida, pois o procedimento de instalação é bem invasivo e irá reconfigurar diversos serviços do servidor.

## Preparação do servidor

> Requisitos mínimos:
- Memória: 8GB
- Disco: 60Gb

### Instalação

Instale o Ubuntu em sua plataforma preferida (VmWare, VirtualBox, Hyper-V e etc).

Dentro do servidor Ubuntu recém instalado realize os procedimentos abaixo.

#### Atualize e instale as dependências básicas

```bash
apt update && apt -y upgrade
apt install wget
```

#### Deploy

```bash
wget --no-cache -q -O- https://raw.githubusercontent.com/sec4us-training/treinamento-devsecops/main/deploy.sh | sudo bash
```

> [!NOTE]
> O script deploy.sh irá executar todos o processo de deploy dos arquivos .yml, sendo assim NÃO precisa executar manualmente cada um deles.

---

## Infraestrutura do Lab

Todos os serviços do treinamento são instalados em **um único servidor Ubuntu** e expostos
através de um **Nginx** atuando como reverse-proxy TLS para os diversos *hostnames* do
domínio `labs.sec4us.com.br`. 

```
            Internet / Aluno
                  │
                  ▼
        ┌───────────────────────┐
        │   <IP do servidor>    │
        │  (Ubuntu DevSecOps)   │
        │                       │
        │  443 ─► Nginx (TLS)   │  ──► reverse-proxy por SNI/Host
        │  48284 ─► Squid       │  ──► forward-proxy (ACL: *.sec4us.com.br)
        │                       │
        │  Serviços locais:     │
        │   • GitLab            │
        │   • Vault             │
        │   • JFrog             │
        │   • Jenkins           │
        │   • SonarQube         │
        │   • Web01             │
        │   • Registry          │
        └───────────────────────┘
```

### Hosts/URLs do lab

Todos os hostnames abaixo apontam para o **mesmo IP** (o IP público do servidor onde o
`deploy.sh` foi executado). Substitua `<IP_DO_SERVIDOR>` pelo IP real do seu lab
(ex.: `54.212.51.187`).

| Serviço            | URL                                        |
| ------------------ | ------------------------------------------ |
| HashiCorp Vault    | https://vault.labs.sec4us.com.br           |
| GitLab             | https://gitlab.labs.sec4us.com.br          |
| JFrog Artifactory  | https://artifactory.labs.sec4us.com.br     |
| Jenkins            | https://jenkins.labs.sec4us.com.br         |
| SonarQube          | https://sonar.labs.sec4us.com.br           |
| Web01 (DVWA-like)  | https://www.labs.sec4us.com.br             |
| Docker Registry    | https://registry.labs.sec4us.com.br        |

> [!IMPORTANT]
> O Nginx faz roteamento por *Host header*, então **acessar diretamente pelo IP não
> funciona** — você precisa resolver os hostnames acima para o IP do servidor. Use
> uma das duas opções a seguir: (1) editar o arquivo `hosts` da sua máquina, ou
> (2) configurar o **upstream proxy** apontando para o Squid do lab.

---

## Opção 1 — Editar o arquivo `hosts` da sua máquina

Adicione as 7 entradas abaixo ao arquivo `hosts` do seu sistema operacional,
substituindo `<IP_DO_SERVIDOR>` pelo IP do seu lab:

```
<IP_DO_SERVIDOR>   vault.labs.sec4us.com.br
<IP_DO_SERVIDOR>   gitlab.labs.sec4us.com.br
<IP_DO_SERVIDOR>   artifactory.labs.sec4us.com.br
<IP_DO_SERVIDOR>   jenkins.labs.sec4us.com.br
<IP_DO_SERVIDOR>   sonar.labs.sec4us.com.br
<IP_DO_SERVIDOR>   www.labs.sec4us.com.br
<IP_DO_SERVIDOR>   registry.labs.sec4us.com.br
```

### Windows

1. Abra o **Bloco de Notas** *como Administrador* (clique direito → *Executar como administrador*).
2. Abra o arquivo `C:\Windows\System32\drivers\etc\hosts`.
3. Cole as linhas acima no final do arquivo e salve.
4. (Opcional) Limpe o cache DNS: abra um `cmd` como admin e execute `ipconfig /flushdns`.

### Linux

```bash
sudo nano /etc/hosts
# cole as linhas e salve (Ctrl+O, Enter, Ctrl+X)

# (opcional) flush do resolver, dependendo da distro:
sudo systemd-resolve --flush-caches   # systemd-resolved
sudo resolvectl flush-caches          # systemd recente
```

### macOS

```bash
sudo nano /etc/hosts
# cole as linhas e salve (Ctrl+O, Enter, Ctrl+X)

sudo dscacheutil -flushcache
sudo killall -HUP mDNSResponder
```

### Validação

```bash
ping -c1 gitlab.labs.sec4us.com.br
# deve resolver para <IP_DO_SERVIDOR>
```

---

## Opção 2 — Usar o Squid (forward proxy) do lab

O servidor já provisiona um **Squid** escutando em `<IP_DO_SERVIDOR>:48284`, com ACL
liberada apenas para destinos `*.sec4us.com.br`. Apontar seu navegador (ou Burp Suite)
para esse proxy faz com que a resolução de DNS ocorra **no servidor**, dispensando a
edição do arquivo `hosts`.

| Parâmetro | Valor                  |
| --------- | ---------------------- |
| Host      | `<IP_DO_SERVIDOR>`     |
| Porta     | `48284`                |
| Protocolo | HTTP (CONNECT p/ HTTPS)|
| ACL       | apenas `*.sec4us.com.br` |

### Firefox

1. **Settings → General → Network Settings → Settings…**
2. Selecione **Manual proxy configuration**.
3. Em **HTTP Proxy**, informe `<IP_DO_SERVIDOR>` e porta `48284`.
4. Marque **Also use this proxy for HTTPS**.
5. Em **No proxy for**, deixe `localhost, 127.0.0.1`.
6. OK.

### Chrome / Edge (macOS e Windows)

Esses navegadores usam o proxy do sistema operacional. Configure o proxy do SO:

- **Windows:** *Settings → Network & Internet → Proxy → Manual proxy setup* → endereço
  `<IP_DO_SERVIDOR>` / porta `48284`.
- **macOS:** *System Settings → Network → Wi-Fi (ou interface ativa) → Details → Proxies
  → Web Proxy (HTTP) e Secure Web Proxy (HTTPS)* → endereço `<IP_DO_SERVIDOR>` / porta `48284`.
- **Linux (GNOME):** *Settings → Network → Network Proxy → Manual* → mesmo host/porta.

### Burp Suite — Upstream proxy

Esta é a forma recomendada quando você já está interceptando o tráfego com o Burp
e quer que o **próprio Burp** repasse as requisições para o lab via Squid, sem mexer
no `hosts` da máquina.

**Settings → Network → Connections → Upstream proxy servers → Add**

| Campo              | Valor                          |
| ------------------ | ------------------------------ |
| Destination host   | `*.labs.sec4us.com.br`         |
| Proxy host         | `<IP_DO_SERVIDOR>`             |
| Proxy port         | `48284`                        |
| Authentication type| `None`                         |

Com essa regra ativa, o Burp só usa o upstream quando o destino casar com
`*.labs.sec4us.com.br`; o restante do tráfego segue direto.

> [!TIP]
> O certificado dos serviços é assinado pela *Sec4US Root CA*. Para evitar avisos de
> certificado no navegador, importe o arquivo `/etc/nginx/certs/root-ca.pem` (gerado
> no servidor durante o deploy) como **Trusted Root CA** no seu sistema/navegador.
