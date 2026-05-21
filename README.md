# Marco Zero Cosméticos Lab Azure

Este repositório automatiza a criação de uma infraestrutura simples na Azure (VNet, duas VMs, NSGs, Nginx, Node.js e MySQL) e sobe uma aplicação de exemplo com acesso ao banco.

## Estrutura do pacote

```
gi-lab-azure/
├── README.md                 ← este arquivo
├── COMANDOS.md               ← passo-a-passo CLI didático (LEIA PRIMEIRO)
├── scripts/                  ← automação Azure CLI
│   ├── 00_variables.sh
│   ├── 01_create_rg_network.sh
│   ├── 02_create_vm_app.sh
│   ├── 03_create_vm_db.sh
│   ├── 04_configure_app.sh
│   ├── 05_configure_db.sh
│   ├── 06_connectivity_tests.sh
│   └── 99_destroy.sh
├── sql/
│   └── schema.sql            ← entregável .sql (DDL + seeds)
├── nginx/
│   └── marcozero.conf        ← entregável nginx.conf
├── app/                      ← API Node.js de validação
│   ├── package.json
│   ├── server.js
│   ├── ecosystem.config.js
└── docs/
    ├── diagrama.md           ← diagrama Mermaid (renderizável em PNG)
```
## Visão geral
- **VM-APP (pública):** Node.js 20 + PM2 + Nginx
- **VM-DB (privada):** MySQL 8 com disco dedicado em `/mnt/mysql-data`
- **Rede:** VNet com subnets `app-subnet` e `data-subnet`
- **Segurança:** NSG público na `app-subnet` e NSG privado na `data-subnet`

Veja o diagrama em `docs/diagrama.md`.

## Pré-requisitos
- **Azure CLI** instalada e autenticada:
  ```bash
  az --version
  az login
  az account show -o table
  ```
- **SKU disponível** na região (por padrão `Standard_B2s`):
  ```bash
  az vm list-skus --location centralus --size Standard_B2s --output table
  ```

## Variáveis principais
As variáveis globais estão em `scripts/00_variables.sh`. Você pode sobrescrevê-las antes de executar os scripts:

```bash
source scripts/00_variables.sh
export LOCATION=centralus
export MYSQL_ROOT_PWD='TrocarSenhaRoot#2026'
export MYSQL_APP_PWD='TrocarSenhaApp#2026'
```

O IP público do seu laboratório (`LAB_PUBLIC_IP`) é detectado automaticamente.

## Passo a passo (ordem de execução)
```bash
# 1) Carregar variáveis
source scripts/00_variables.sh

# 2) Resource Group, VNet, subnets, NSGs
bash scripts/01_create_rg_network.sh

# 3) Provisionar VM-APP (IP público estático)
bash scripts/02_create_vm_app.sh

# 4) Provisionar VM-DB (sem IP público) + disco
bash scripts/03_create_vm_db.sh

# 5) Configurar VM-APP (Node 20, PM2, Nginx)
bash scripts/04_configure_app.sh

# 6) Configurar VM-DB (MySQL 8, datadir no disco, schema)
bash scripts/05_configure_db.sh

# 7) Testes de conectividade (item 4.4)
bash scripts/06_connectivity_tests.sh
```

> Todos os comandos detalhados e a explicação linha-a-linha estão em `comandos.md`.

## Testes
O script `scripts/06_connectivity_tests.sh` executa 4 testes e imprime `PASS/FAIL`:
1. SSH local -> VM-APP (deve funcionar)
2. SSH local -> VM-DB (deve falhar)
3. VM-APP -> VM-DB via bastion (deve funcionar)
4. HTTP na VM-APP acessando o banco (deve funcionar)

## Endpoints da aplicação
- `GET /health`
- `GET /produtos`
- `GET /clientes`
- `GET /pedidos`

## Arquivos úteis
- **Guia completo:** `comandos.md`
- **Diagrama:** `docs/diagrama.md`
- **App (Node/Express):** `app/`
- **Nginx:** `nginx/marcozero.conf`
- **Schema/Seeds:** `sql/schema.sql`
- **Scripts:** `scripts/`

## Destruir o ambiente
```bash
bash scripts/99_destroy.sh
```

## Notas
- O IP público da VM-APP é persistido em `scripts/.lab_ips` após o provisionamento.
- A VM-DB não possui IP público por requisito do laboratório.


