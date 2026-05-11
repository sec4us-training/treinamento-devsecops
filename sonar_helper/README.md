# sonar-helper

Projeto **lab** em Java que conecta em um SonarQube e lista os projetos via API REST. Inclui um `Jenkinsfile` que baixa Java 21 + Maven, builda o projeto e publica os artefatos em um JFrog Artifactory.

> **Aviso:** projeto de laboratório. As constantes em `SonarConfig` são preenchidas em tempo de build a partir de variáveis de ambiente, mas o `.jar` resultante contém as credenciais embutidas. Não use esse padrão em produção.

---

## Estrutura

```
sonar_helper/
├── Jenkinsfile
├── pom.xml
├── README.md
└── src/
    └── main/
        ├── java/
        │   └── com/sec4us/lab/sonarhelper/
        │       └── SonarHelper.java          # main: lista projetos do Sonar
        └── java-templates/
            └── com/sec4us/lab/sonarhelper/config/
                └── SonarConfig.java          # template filtrado pelo Maven
```

- `SonarHelper.java` — usa `java.net.http.HttpClient` + Jackson para chamar `GET /api/projects/search` com Basic Auth, pagina e imprime `KEY / NAME / VISIBILITY`.
- `SonarConfig.java` (template) — `SONAR_ADMIN_USER` e `SONAR_ADMIN_PASSWORD` são substituídos no build pelo `templating-maven-plugin` a partir das env vars `SONAR_ADMIN_USER` / `SONAR_ADMIN_PASSWORD`.

---

## Requisitos

- Java **21**
- Maven **3.9+**
- Acesso de rede ao SonarQube (`https://sonar.labs.sec4us.com.br`)

---

## Configuração

Credenciais do SonarQube são lidas de variáveis de ambiente em tempo de build:

| Variável               | Descrição                              |
|------------------------|----------------------------------------|
| `SONAR_ADMIN_USER`     | Usuário admin do SonarQube             |
| `SONAR_ADMIN_PASSWORD` | Senha do admin do SonarQube            |

A URL do Sonar está fixada em `SonarConfig.SONAR_URL` (`https://sonar.labs.sec4us.com.br`).

---

## Build & execução local

```bash
export SONAR_ADMIN_USER=admin
export SONAR_ADMIN_PASSWORD=admin

mvn clean package
java -jar target/sonar-helper-1.0.0-all.jar
```

Saída esperada:

```
Connecting to SonarQube at https://sonar.labs.sec4us.com.br as admin
Found N project(s).
----------------------------------------
KEY                                      NAME                           VISIBILITY
----------------------------------------
my-project-key                           My Project                     public
...
----------------------------------------
Done. Listed N project(s).
```

### Alternativa sem env vars

Passe as credenciais como propriedades do Maven:

```bash
mvn -Dsonar.admin.user=admin -Dsonar.admin.password=admin clean package
```

Se nem env var nem `-D` forem fornecidos, a compilação falha (o template mantém literais `${env.SONAR_ADMIN_USER}` no `.java` gerado, o que quebra o `javac` — falha visível e cedo).

---

## Como funciona o templating

`pom.xml` declara:

```xml
<properties>
    <sonar.admin.user>${env.SONAR_ADMIN_USER}</sonar.admin.user>
    <sonar.admin.password>${env.SONAR_ADMIN_PASSWORD}</sonar.admin.password>
</properties>
```

e usa o `templating-maven-plugin` (goal `filter-sources`), que lê `src/main/java-templates/` e gera o `.java` final em `target/generated-sources/java-templates/`, automaticamente incluído no source path da compilação.

---

## CI/CD — Jenkinsfile

O pipeline tem 4 stages:

1. **Checkout** — `checkout scm`.
2. **Install Java 21 & Maven** — baixa Temurin JDK 21.0.4+7 e Apache Maven 3.9.9 para `${WORKSPACE}/.tools/` (com cache; só baixa se ainda não existir). Sem `sudo`, sem dependência de pacotes do SO.
3. **Build** — `mvn -B -ntp clean package`, dentro de um `withCredentials` que expõe `SONAR_ADMIN_USER` e `SONAR_ADMIN_PASSWORD` a partir da credencial Jenkins `sonar-admin`.
4. **Deploy to JFrog** — `curl -T` envia `jar`, `pom` e fat-jar para `https://artifactory.labs.sec4us.com.br/artifactory/sec4us/com/sec4us/lab/sonar-helper/1.0.0/`, usando a credencial Jenkins `jfrog-sec4us`.

### Credenciais Jenkins necessárias

| ID              | Tipo                | Conteúdo                                  |
|-----------------|---------------------|-------------------------------------------|
| `sonar-admin`   | Username/Password   | Usuário/senha admin do SonarQube          |
| `jfrog-sec4us`  | Username/Password   | Usuário/senha com permissão de deploy em `sec4us` |

### Variáveis do pipeline

Definidas no bloco `environment` do `Jenkinsfile` — ajuste conforme necessário:

- `JFROG_URL`, `JFROG_REPO`, `JFROG_TARGET`
- `ARTIFACT_GROUP`, `ARTIFACT_ID`, `ARTIFACT_VERSION`
- `JAVA_VERSION`, `JAVA_URL`, `MAVEN_VERSION`, `MAVEN_URL`

---

## Deploy — caminho final no JFrog

```
https://artifactory.labs.sec4us.com.br/artifactory/sec4us/com/sec4us/lab/sonar-helper/1.0.0/
├── sonar-helper-1.0.0.jar
├── sonar-helper-1.0.0.pom
└── sonar-helper-1.0.0-all.jar   (fat-jar executável)
```
