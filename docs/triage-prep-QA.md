# Triage Prep — Q&A (Digai / WhatsApp)

**Formato:** 4 perguntas tecnicas, 5 min cada, via WhatsApp (texto).
**Estrategia:** Respostas concisas (WhatsApp nao e redacao). Citar o projeto OrderHub-APIM como exemplo pratico sempre que possivel. Demonstrar profundidade, nao so amplitude.

---

## BLOCO 1 — API Management & Gateway Patterns

### P1: O que e Azure API Management e qual o papel dele em uma arquitetura de microservices?

**Resposta:**
Azure APIM e um gateway gerenciado que fica entre os consumers (clientes, parceiros, apps) e os backends (microservices). Ele centraliza cross-cutting concerns que voce nao quer repetir em cada microservice:

- **Rate limiting** — protege backends de sobrecarga (ex: 50 calls/min por subscription)
- **Caching** — reduz latencia e carga no backend para respostas que nao mudam com frequencia
- **Autenticacao** — valida subscription keys ou JWT tokens antes do request chegar no backend
- **Transformacao** — modifica headers, payloads, URLs entre o client e o backend
- **Retry** — tenta novamente em caso de falha temporaria (ex: 500/503)
- **Observability** — metricas, logs e traces centralizados

Na pratica, no meu projeto OrderHub-APIM, o APIM fronts duas Azure Functions (Orders API e Products API). Cada API tem policies XML que aplicam rate-limit, cache, retry e headers customizados. O backend nao precisa saber nada sobre autenticacao ou throttling — o APIM resolve antes.

O ponto-chave: APIM desacopla concerns de infraestrutura dos concerns de negocio.

---

### P2: Quais API Gateway Patterns voce conhece e como implementaria rate limiting e caching?

**Resposta:**
Os principais patterns que implemento no dia a dia:

**Rate Limiting** — Protege contra abuso e garante fair usage. No APIM, uso a policy `<rate-limit>` no inbound:
```xml
<rate-limit calls="50" renewal-period="60" />
```
Isso limita 50 chamadas por 60 segundos por subscription. Tambem existe `rate-limit-by-key` para limitar por IP, header ou claim do JWT.

**Caching** — Reduz latencia e carga. Uso `<cache-lookup>` no inbound e `<cache-store>` no outbound:
```xml
<cache-lookup vary-by-query-parameter="*" />  <!-- inbound -->
<cache-store duration="300" />                <!-- outbound, 5 min -->
```
O APIM serve a resposta do cache sem nem tocar no backend.

**Request/Response Transformation** — Adiciono headers customizados para rastreabilidade:
```xml
<set-header name="X-Processed-By" exists-action="override">
  <value>APIM-OrderHub</value>
</set-header>
```

**Retry** — Para resiliencia contra falhas transientes no backend:
```xml
<retry condition="@(context.Response.StatusCode == 500 || context.Response.StatusCode == 503)"
       count="3" interval="2" />
```

**JWT Validation** — Valida tokens OAuth 2.0 antes do request chegar no backend, integrando com Entra ID (Azure AD).

No OrderHub-APIM, apliquei todos esses patterns via policies XML vinculadas ao Terraform, entao tudo e versionado e reproduzivel.

---

### P3: Como voce garante a seguranca de uma API exposta no APIM?

**Resposta:**
Seguranca em camadas:

1. **Subscription Keys** — Primeira camada. Cada consumer recebe uma key unica (`Ocp-Apim-Subscription-Key`). Sem a key, o APIM retorna 401 antes de tocar no backend. E o padrao default do APIM.

2. **JWT Validation** — Para cenarios mais robustos, uso `<validate-jwt>` integrando com Entra ID (Azure AD). O APIM valida o token, verifica audience, issuer e expiracao. O backend nunca ve um request nao autenticado.

3. **IP Filtering** — `<ip-filter>` para restringir acesso por range de IP (ex: so o IP do parceiro).

4. **CORS** — Controle granular de quais origens podem chamar a API.

5. **HTTPS only** — Todas as APIs expostas so via HTTPS (protocols = ["https"] no Terraform).

6. **Managed Identity** — A Function App usa Managed Identity para acessar Service Bus e Storage sem secrets hardcoded no codigo.

7. **Rate Limiting** — Previne brute-force e DDoS na camada de aplicacao.

8. **Backend isolation** — Os microservices (Functions) nao sao expostos diretamente na internet. So o APIM tem acesso.

Na triagem, posso mostrar as policies XML no meu repositorio onde implementei subscription key + JWT reference + rate limiting.

---

## BLOCO 2 — Integracoes Sincronas e Assincronas

### P4: Qual a diferenca entre integracao sincrona e assincrona? Quando usar cada uma?

**Resposta:**
**Sincrona:** O client faz o request e espera a resposta. Usa quando precisa da resposta imediata para continuar. Ex: GET /products — o client precisa da lista de produtos para renderizar a tela.

**Assincrona:** O client envia o request, recebe um ACK (ex: 202 Accepted), e o processamento acontece em background. Usa quando o processamento e demorado ou envolve sistemas externos que podem falhar.

No OrderHub-APIM implementei os dois:

- **Sincrono:** `GET /api/products` retorna 200 com a lista de produtos. Request-response direto.
- **Assincrono:** `POST /api/orders` valida o pedido, publica um evento no Azure Service Bus (Topic), e retorna 202 imediatamente. O processamento (chamar o SaaS externo) acontece em outro servico que escuta o Topic via Subscription.

**Quando usar assincrono:**
- Processamento demorado (>2-3 segundos)
- Integracao com sistemas externos que podem estar fora do ar
- Quando voce precisa de retry automatico (Service Bus tem `max_delivery_count`)
- Fire-and-forget (notificacoes, emails, webhooks)
- Desacoplamento entre produtores e consumidores

**Vantagem chave:** Se o SaaS externo estiver fora, o Service Bus guarda a mensagem e tenta de novo. O client nao e impactado.

---

### P5: Como funciona o Azure Service Bus e qual a diferenca entre Queue e Topic?

**Resposta:**
Azure Service Bus e um message broker enterprise gerenciado.

**Queue:** Point-to-point. Uma mensagem, um consumidor. Primeiro a chegar, primeiro a ser processado. Use para work distribution (ex: processar jobs em paralelo com competing consumers).

**Topic + Subscription:** Publish/subscribe. Uma mensagem, N consumidores. O produtor publica no Topic. Cada Subscription recebe uma copia da mensagem. Use quando multiplos sistemas precisam reagir ao mesmo evento.

No OrderHub-APIM usei Topic + Subscription porque:
- O `create_order` publica no `orders-topic`
- O `processor-sub` consome e chama o SaaS
- Se amanha precisar de outro consumer (ex: enviar email, atualizar dashboard), basta criar outra Subscription. Zero mudanca no produtor.

**Recursos importantes:**
- `max_delivery_count = 5` — tenta 5 vezes antes de mandar para dead-letter queue
- Dead-letter queue — mensagens que falharam ficam la para investigacao
- Sessions — para processar mensagens em ordem (FIFO)
- Duplicate detection — evita processamento duplicado

Escolhi Standard SKU (nao Basic) justamente para suportar Topics.

---

## BLOCO 3 — Observability & Monitoring

### P6: Como voce garante observabilidade end-to-end em uma arquitetura de integracao?

**Resposta:**
Observabilidade e sobre responder rapido: "O que quebrou? Onde? Por que?"

Tres pilares:

1. **Logs estruturados** — Cada funcao loga eventos de negocio com contexto:
```python
logging.info(f"Order {order_id} published to Service Bus")
logging.info(f"Order {order_id} processed, SaaS response: {response.status_code}")
logging.error(f"Order {order_id} SaaS call failed: {error}")
```
O `order_id` permite rastrear o pedido end-to-end: da entrada no APIM ate o processamento assincrono.

2. **Metricas** — Application Insights captura automaticamente:
   - Request rate, latencia, status codes (HTTP functions)
   - Dependency calls (tempo e sucesso das chamadas externas, ex: JSONPlaceholder)
   - Service Bus metrics (queue depth, dead-letter count)
   - APIM Analytics (requests por API, cache hit ratio, rate limit hits)

3. **Traces distribuidos** — Application Insights correlaciona automaticamente a request HTTP com a mensagem no Service Bus e a chamada ao SaaS. Voce ve o fluxo completo em Transaction Search.

**Onde olhar no Azure Portal:**
- APIM > Analytics — visao macro (throughput, erros por API)
- App Insights > Live Metrics — real-time
- App Insights > Transaction Search — trace end-to-end
- App Insights > Failures — root cause de erros
- Service Bus > Overview — mensagens acumuladas, dead-letter

No OrderHub-APIM, a integracao com App Insights e automatica via Terraform (connection string injetada na Function App).

---

### P7: O que voce faria se uma integracao comecasse a falhar intermitentemente?

**Resposta:**
Processo sistematico:

1. **Identificar** — Olho Application Insights > Failures. Filtro por time range e procuro o padrao: e um endpoint especifico? Uma dependencia externa? Um horario especifico?

2. **Isolar** — Se e uma dependencia (ex: SaaS externo), vejo Dependency calls no App Insights. Verifico latencia e taxa de erro. Se o Service Bus esta acumulando mensagens, olho dead-letter queue para ver o motivo das falhas.

3. **Mitigar** — Acoes imediatas:
   - Se e sobrecarga: verifico se o rate-limit esta adequado, ajusto se necessario
   - Se e timeout do backend: aumento timeout ou ajusto retry policy no APIM
   - Se e o SaaS externo fora: o retry do Service Bus (`max_delivery_count`) ja trata. Monitoro dead-letter. Se necessario, processo mensagens da dead-letter manualmente.

4. **Resolver** — Com os dados do App Insights, faco o fix. Se foi transiente, documento. Se foi sistematico, ajusto a politica de retry ou implemento circuit breaker.

5. **Prevenir** — Crio alert no App Insights para o cenario especifico (ex: error rate > 5% em 5 min). Proximo episodio, somos notificados antes do usuario perceber.

---

## BLOCO 4 — Infrastructure as Code (Terraform)

### P8: Por que usar Terraform e como voce estrutura um projeto de IaC?

**Resposta:**
**Por que Terraform:**
- **Reprodutibilidade** — `terraform apply` cria o ambiente identico em dev, staging, prod
- **Versionamento** — Infraestrutura versionada no Git, com code review antes de deploy
- **State management** — Terraform sabe o que existe e o que precisa mudar (plan antes de apply)
- **Multi-cloud** — Mesmo workflow para Azure, AWS, GCP
- **Idempotencia** — Rodar 2x da o mesmo resultado

**Como estruturo:**
No OrderHub-APIM usei uma estrutura flat (adequada ao tamanho do projeto):
```
terraform/
  providers.tf   — provider versions e config
  variables.tf   — inputs parametrizados (location, prefix, email)
  main.tf        — todos os recursos
  outputs.tf     — valores uteis (URLs, keys)
  policies/      — arquivos XML referenciados via file()
```

Para projetos maiores, uso modules:
```
modules/
  apim/        — APIM + APIs + policies
  functions/   — Service Plan + Function App
  messaging/   — Service Bus + Topics
```

**Boas praticas que sigo:**
- Variables para tudo que muda entre ambientes
- Outputs para valores que outros sistemas precisam
- `sensitive = true` em keys e connection strings
- Random suffixes para nomes globalmente unicos (APIM, Storage)
- State remoto (Azure Storage backend) em projetos de equipe

---

### P9: Como voce faz o deploy das Azure Functions e como o APIM se conecta a elas?

**Resposta:**
**Deploy das Functions:**
1. Terraform provisiona a infra (Function App, Service Plan, Storage)
2. `func azure functionapp publish <nome>` faz o deploy do codigo Python
3. O nome da Function App vem do Terraform output: `terraform output -raw function_app_name`

**Conexao APIM -> Functions:**
No Terraform, o APIM API aponta para o hostname da Function App:
```hcl
service_url = "https://${azurerm_linux_function_app.functions.default_hostname}/api"
```

O APIM faz proxy: client chama `apim-gateway/orders/orders`, o APIM aplica policies, e forward para `func-app/api/orders`.

**Fluxo completo:**
Client -> APIM (rate-limit, cache, auth) -> Function App (logica) -> Service Bus (async) -> Processor Function -> SaaS

Cada camada tem uma responsabilidade clara e nenhuma conhece os detalhes da outra.

---

## BLOCO 5 — Microservices & REST API Design

### P10: Como voce desenharia uma API REST bem estruturada?

**Resposta:**
Principios que sigo:

1. **Resources, nao acoes** — `/orders`, `/products` (substantivos). Metodos HTTP definem a acao: GET (ler), POST (criar), PUT (atualizar), DELETE (remover).

2. **Status codes semanticos:**
   - 200 — sucesso com body (GET /products)
   - 201 — recurso criado (POST com resposta sincrona)
   - 202 — aceito para processamento assincrono (POST /orders no OrderHub)
   - 400 — erro do client (validacao falhou)
   - 401 — nao autenticado
   - 404 — recurso nao encontrado
   - 429 — rate limit excedido
   - 500 — erro interno

3. **Versionamento** — Path-based (`/v1/orders`) ou header-based. No APIM, uso revisions para gerenciar versoes sem quebrar consumers existentes.

4. **OpenAPI/Swagger** — Contrato da API documentado e versionado. O APIM Developer Portal publica automaticamente a documentacao para consumers.

5. **Validacao na borda** — APIM valida auth e rate-limit. O backend valida o body:
```python
if not all([customer_name, product_id, quantity]):
    return 400, {"error": "Missing required fields"}
```

6. **Respostas consistentes** — Sempre JSON, sempre com `Content-Type: application/json`.

---

### P11: Como voce habilitaria um time ou vendor externo a consumir suas APIs?

**Resposta:**
O APIM Developer Portal e o ponto central:

1. **Onboarding** — Vendor se cadastra no portal, solicita subscription key
2. **Documentacao** — OpenAPI/Swagger publicado automaticamente. Exemplos de requests/responses.
3. **Sandbox** — Ambiente de teste com rate limits mais permissivos
4. **Subscription Keys** — Cada vendor recebe sua propria key. Permite monitorar uso individualmente e revogar acesso se necessario.
5. **Policies por produto** — Posso criar Products no APIM com diferentes niveis de acesso (Basic: 50 req/min, Premium: 500 req/min)
6. **Analytics** — APIM mostra quem esta chamando o que, com que frequencia, e com que taxa de erro

No OrderHub-APIM, o README ja serve como documentacao basica com exemplos de `curl`. Em producao, isso estaria no Developer Portal do APIM.

---

## BLOCO 6 — Perguntas Situacionais

### P12: Descreva um cenario onde voce precisou integrar sistemas com diferentes padroes (sync/async).

**Resposta (baseada no OrderHub-APIM):**
No OrderHub-APIM, tive exatamente esse cenario:

- O **frontend** precisa de resposta sincrona para mostrar a lista de produtos (GET /products -> 200 com JSON)
- A **criacao de pedido** precisa ser rapida para o usuario, mas o processamento (chamar SaaS externo, enviar notificacao) e demorado e pode falhar

**Solucao:**
- `POST /orders` e sincrono na perspectiva do client: valida, retorna 202 em <100ms
- Internamente, publica evento no Service Bus Topic (assincrono)
- Processor function consome da Subscription e processa em background
- Se o SaaS falhar, Service Bus retenta automaticamente (max 5x)
- Se esgotar retries, mensagem vai para dead-letter queue para investigacao

**Beneficio:** O usuario nao espera. O sistema e resiliente. Os componentes sao desacoplados. Adicionar novos consumers (ex: enviar email) e so criar nova Subscription — zero mudanca no codigo existente.

---

### P13: Como voce lidaria com uma situacao onde um vendor externo esta sobrecarregando sua API?

**Resposta:**
1. **Deteccao** — APIM Analytics mostra requests por subscription. Identifico o vendor pelo subscription key.

2. **Mitigacao imediata** — Rate limiting ja esta em vigor (50 req/min). Se nao for suficiente:
   - `<rate-limit-by-key>` para limitar especificamente aquele vendor
   - `<quota>` para limites mensais (ex: 10.000 chamadas/mes no plano Basic)

3. **Comunicacao** — Notifico o vendor com dados: "Voces estao fazendo X req/min, o limite e Y. Aqui esta a documentacao de best practices (caching client-side, exponential backoff)."

4. **Longo prazo** — Crio Products no APIM com tiers (Free, Basic, Premium) com diferentes limites. O vendor escolhe/paga pelo tier adequado ao volume dele.

5. **Monitoramento** — Alert no App Insights para 429 responses acima de um threshold.

---

## DICAS PARA A TRIAGEM (WhatsApp, 5 min/pergunta)

### Formato ideal de resposta:
1. **Resposta direta** (1-2 frases) — mostra que voce sabe
2. **Exemplo pratico** (2-3 frases) — mostra que voce faz
3. **Referencia ao projeto** (1 frase) — mostra evidencia

### Exemplo:
> "Rate limiting no APIM e configurado via policy XML no inbound. No meu projeto OrderHub-APIM, aplico 50 req/min por subscription com `<rate-limit calls='50' renewal-period='60' />`, e todo o provisionamento e feito via Terraform. O repo esta no meu GitHub se quiser ver o codigo."

### Frases-chave para usar:
- "No meu projeto OrderHub-APIM, implementei isso com..."
- "Provisionei tudo via Terraform, entao e reproduzivel e versionado"
- "Uso Application Insights para observabilidade end-to-end"
- "A integracao assincrona via Service Bus garante resiliencia"
- "As policies do APIM centralizam seguranca e governance"

### Erros a evitar:
- Respostas muito longas (WhatsApp, nao e email)
- So teoria, sem exemplo pratico
- Falar "eu faria" em vez de "eu fiz" (voce TEM o projeto)
- Esquecer de mencionar Terraform/IaC
- Nao mencionar observabilidade (e um diferencial forte)
