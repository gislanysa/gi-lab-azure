# Passo-a-passo via Azure CLI — Marco Zero Cosméticos (HOM)

Este documento traz **todos os comandos** na ordem exata de execução,
com explicação de cada bloco. Cada passo numerado mapeia para um script
em `scripts/`, mas você pode rodar manualmente se preferir entender
linha-a-linha.

## 0. Pré-requisitos

```bash
# Azure CLI
az --version

# Autentique-se na sua conta Azure for Students
az login

# Confirme a assinatura ativa e (se houver mais de uma) selecione a correta
az account show -o table
# az account set --subscription "<NOME-OU-ID-DA-ASSINATURA>"

# Confira região e cota — Standard_B2s precisa estar disponível em $LOCATION
az vm list-skus --location centralus --size Standard_B2s --output table
```

> Se `Standard_B2s` não aparecer na sua região, edite
> `scripts/00_variables.sh` e ajuste `LOCATION` (ex.: `eastus`).

## 1. Carregar variáveis do laboratório

```bash
cd /Users/x/gislany-lab-azure
source scripts/00_variables.sh
echo "RG=$RG  LOCATION=$LOCATION  LAB_PUBLIC_IP=$LAB_PUBLIC_IP"
```

Variáveis sensíveis (senhas do MySQL) podem ser sobrescritas antes:

```bash
export MYSQL_ROOT_PWD='Minha$enhaForte#2026'
export MYSQL_APP_PWD='Outr@Senh@App#2026'
```

## 2. Resource Group, VNet, subnets, NSGs e regras

```bash
bash scripts/01_create_rg_network.sh
```

Equivale a executar manualmente:

```bash
az group create -n rg-marcozero-hom-gl -l brazilsouth

az network vnet create -g rg-marcozero-hom-gl -n vnet-marcozero \
  --address-prefix 10.0.0.0/16 \
  --subnet-name app-subnet --subnet-prefix 10.0.1.0/24

az network vnet subnet create -g rg-marcozero-hom-gl --vnet-name vnet-marcozero \
  -n data-subnet --address-prefix 10.0.2.0/24

# NSG público (app-subnet)
az network nsg create -g rg-marcozero-hom-gl -n nsg-public
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-public \
  -n allow-ssh-lab --priority 100 \
  --source-address-prefixes "<SEU-IP-PUBLICO>/32" \
  --destination-port-ranges 22 --access Allow --protocol Tcp
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-public \
  -n allow-http --priority 110 --destination-port-ranges 80 --access Allow --protocol Tcp
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-public \
  -n allow-https --priority 120 --destination-port-ranges 443 --access Allow --protocol Tcp

# NSG privado (data-subnet)
az network nsg create -g rg-marcozero-hom-gl -n nsg-private
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-private \
  -n allow-mysql-from-app --priority 100 \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-port-ranges 3306 --access Allow --protocol Tcp
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-private \
  -n allow-ssh-from-app --priority 110 \
  --source-address-prefixes 10.0.1.0/24 \
  --destination-port-ranges 22 --access Allow --protocol Tcp
az network nsg rule create -g rg-marcozero-hom-gl --nsg-name nsg-private \
  -n deny-internet-inbound --priority 200 \
  --source-address-prefixes Internet \
  --destination-port-ranges '*' --access Deny --protocol '*'

# Associar NSGs às subnets
az network vnet subnet update -g rg-marcozero-hom-gl --vnet-name vnet-marcozero \
  -n app-subnet --network-security-group nsg-public
az network vnet subnet update -g rg-marcozero-hom-gl --vnet-name vnet-marcozero \
  -n data-subnet --network-security-group nsg-private
```

### Captura para o relatório
```bash
az network nsg rule list -g $RG --nsg-name nsg-public  -o table
az network nsg rule list -g $RG --nsg-name nsg-private -o table
```

## 3. Provisionar a VM-APP

```bash
bash scripts/02_create_vm_app.sh
```

O que ele faz:
1. Gera `~/.ssh/marcozero_key` (ed25519) se não existir.
2. Cria a VM com:
   - Imagem: `Ubuntu2204`
   - SKU: `Standard_B2s`
   - Subnet: `app-subnet`
  - IP público **estático** (Standard SKU exige AllocationMethod=Static)
   - Autenticação apenas por chave SSH
   - `--nsg ""` (sem NSG na NIC — a proteção vem da subnet)
3. Guarda o IP público em `scripts/.lab_ips`.

### Captura para o relatório
```bash
az vm show -d -g $RG -n vm-app -o table
```

## 4. Provisionar a VM-DB (sem IP público) + disco

```bash
bash scripts/03_create_vm_db.sh
```

Equivale a:
```bash
az vm create -g $RG -n vm-db \
  --image Ubuntu2204 --size Standard_B2s \
  --vnet-name vnet-marcozero --subnet data-subnet \
  --public-ip-address "" \
  --admin-username azureuser \
  --ssh-key-values ~/.ssh/marcozero_key.pub \
  --nsg ""

az vm disk attach -g $RG --vm-name vm-db \
  --name vm-db-data --new --size-gb 32 --sku Premium_LRS
```

### Captura para o relatório
```bash
az vm show -d -g $RG -n vm-db --query "{Name:name,Pub:publicIps,Priv:privateIps,Size:hardwareProfile.vmSize}" -o table
az disk list -g $RG -o table
```

Note que `publicIps` está vazio — exatamente como exige o item 4.3.

## 5. Configurar VM-APP (Node 20 + PM2 + Nginx)

```bash
bash scripts/04_configure_app.sh
```

Internamente:
1. Conecta via SSH na VM-APP usando o IP público.
2. Instala Node.js 20 via NodeSource, Nginx (apt) e PM2 global.
3. Copia `app/` e `nginx/marcozero.conf` para a VM.
4. Gera `~/app/.env` com `DB_HOST=<IP-privado-da-VM-DB>` e a senha do
   `app_user`.
5. `npm ci` (ou `npm install` se não houver `package-lock.json`),
  `pm2 start ecosystem.config.js`, `pm2 save` e configura
   `pm2 startup` para reiniciar no boot.
6. Move `marcozero.conf` para `/etc/nginx/sites-available/`, ativa,
   remove o default e recarrega o serviço.

### Captura para o relatório
Da VM-APP:
```bash
pm2 status
sudo nginx -t
sudo systemctl status nginx --no-pager
```

## 6. Configurar VM-DB (MySQL 8 + disco montado + schema)

```bash
bash scripts/05_configure_db.sh
```

Internamente, **via bastion** (com agent forwarding), a VM-DB recebe:
1. Formatação ext4 do disco extra; montagem em `/mnt/mysql-data` via UUID em `/etc/fstab`.
2. Instalação do `mysql-server` (MySQL 8).
3. `rsync` do `/var/lib/mysql` para `/mnt/mysql-data` e ajuste do
   `datadir` em `/etc/mysql/mysql.conf.d/marcozero.cnf`.
4. Ajuste do AppArmor (`/etc/apparmor.d/usr.sbin.mysqld`).
5. `mysql_secure_installation` programático (define root password,
   remove usuários anônimos, dropa schema `test`).
6. Carrega `sql/schema.sql` (tabelas + seeds).
7. Cria `app_user@10.0.1.%` com GRANTs restritos ao schema.

### Captura para o relatório
Da VM-DB (via bastion):
```bash
df -h /mnt/mysql-data
sudo systemctl status mysql --no-pager
mysql -uroot -p"$MYSQL_ROOT_PWD" -e "SELECT @@datadir, @@bind_address;"
mysql -uroot -p"$MYSQL_ROOT_PWD" -e "SELECT User,Host FROM mysql.user WHERE User='app_user';"
```

## 7. Executar os 4 testes de conectividade (item 4.4)

```bash
bash scripts/06_connectivity_tests.sh
```

Saída esperada (resumida):
```
TESTE 1  [PASS]  ssh local -> vm-app: hostname vm-app
TESTE 2  [PASS]  ssh local -> vm-db:  timeout
TESTE 3  [PASS]  ssh -A vm-app -> vm-db: hostname vm-db
TESTE 4  [PASS]  GET /health -> {"app":"ok","db":"ok"}; GET /produtos -> [...]
```

Capture a tela inteira deste output — é a evidência da Apresentação
(item 7 do enunciado).

### Manual

```bash
# Teste 1
ssh -i ~/.ssh/marcozero_key azureuser@$APP_IP "hostname && uptime"

# Teste 2 — deve dar timeout (NSG-Private bloqueia)
timeout 12 ssh -i ~/.ssh/marcozero_key azureuser@$DB_PRIV_IP "hostname"

# Teste 3 — via bastion com agent forwarding
ssh-add ~/.ssh/marcozero_key
ssh -A -i ~/.ssh/marcozero_key azureuser@$APP_IP \
  "ssh azureuser@$DB_PRIV_IP 'hostname && uname -a'"

# Teste 4 — aplicação consultando banco
curl http://$APP_IP/health
curl http://$APP_IP/produtos
curl http://$APP_IP/pedidos
```

## 8. (Opcional) Configurar Azure Backup da VM-DB

```bash
az backup vault create -g $RG -n rsv-marcozero -l $LOCATION
az backup protection enable-for-vm \
  -g $RG --vault-name rsv-marcozero \
  --vm vm-db --policy-name DefaultPolicy
az backup protection backup-now \
  -g $RG --vault-name rsv-marcozero \
  --container-name vm-db --item-name vm-db --backup-management-type AzureIaasVM
```

---

## 9. Destruir tudo

```bash
bash scripts/99_destroy.sh         

az group show -n rg-marcozero-hom-gl  # deve retornar 'ResourceGroupNotFound'
```

## Resumo da árvore de comandos (versão TL;DR)

```bash
az login
source scripts/00_variables.sh
bash   scripts/01_create_rg_network.sh
bash   scripts/02_create_vm_app.sh
bash   scripts/03_create_vm_db.sh
bash   scripts/04_configure_app.sh
bash   scripts/05_configure_db.sh
bash   scripts/06_connectivity_tests.sh
bash   scripts/99_destroy.sh
az group show -n rg-marcozero-hom-gl 
```
