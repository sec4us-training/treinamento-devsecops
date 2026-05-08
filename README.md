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
