# Provisiona Resource Group, VNet, subnets e NSGs .
# Pré-requisito:  source ./scripts/00_variables.sh && az login

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_variables.sh"

echo "==> [1/6] Criando Resource Group $RG em $LOCATION"
az group create \
  --name "$RG" \
  --location "$LOCATION" \
  --tags $TAGS \
  --output table

echo "==> [2/6] Criando VNet $VNET ($VNET_CIDR) com $APP_SUBNET"
az network vnet create \
  --resource-group "$RG" \
  --name "$VNET" \
  --address-prefix "$VNET_CIDR" \
  --subnet-name "$APP_SUBNET" \
  --subnet-prefix "$APP_SUBNET_CIDR" \
  --output table

echo "==> [3/6] Criando subnet $DATA_SUBNET ($DATA_SUBNET_CIDR)"
az network vnet subnet create \
  --resource-group "$RG" \
  --vnet-name "$VNET" \
  --name "$DATA_SUBNET" \
  --address-prefix "$DATA_SUBNET_CIDR" \
  --output table

echo "==> [4/6] Criando NSG público (app-subnet) e regras"
az network nsg create -g "$RG" -n "$NSG_PUBLIC" --output table

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PUBLIC" \
  --name "allow-ssh-lab" --priority 100 \
  --source-address-prefixes "$LAB_PUBLIC_IP/32" \
  --destination-port-ranges 22 \
  --access Allow --protocol Tcp --direction Inbound \
  --description "SSH liberado apenas a partir do IP publico do laboratorio" \
  --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PUBLIC" \
  --name "allow-http" --priority 110 \
  --source-address-prefixes Internet \
  --destination-port-ranges 80 \
  --access Allow --protocol Tcp --direction Inbound \
  --description "HTTP publico (Nginx reverse proxy)" \
  --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PUBLIC" \
  --name "allow-https" --priority 120 \
  --source-address-prefixes Internet \
  --destination-port-ranges 443 \
  --access Allow --protocol Tcp --direction Inbound \
  --description "HTTPS publico" \
  --output none

echo "==> [5/6] Criando NSG privado (data-subnet) e regras"
az network nsg create -g "$RG" -n "$NSG_PRIVATE" --output table

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PRIVATE" \
  --name "allow-mysql-from-app" --priority 100 \
  --source-address-prefixes "$APP_SUBNET_CIDR" \
  --destination-port-ranges 3306 \
  --access Allow --protocol Tcp --direction Inbound \
  --description "MySQL acessivel apenas da app-subnet" \
  --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PRIVATE" \
  --name "allow-ssh-from-app" --priority 110 \
  --source-address-prefixes "$APP_SUBNET_CIDR" \
  --destination-port-ranges 22 \
  --access Allow --protocol Tcp --direction Inbound \
  --description "SSH via VM-APP atuando como bastion" \
  --output none

az network nsg rule create \
  --resource-group "$RG" --nsg-name "$NSG_PRIVATE" \
  --name "deny-internet-inbound" --priority 200 \
  --source-address-prefixes Internet \
  --destination-port-ranges '*' \
  --access Deny --protocol '*' --direction Inbound \
  --description "Negacao explicita de qualquer trafego vindo da Internet" \
  --output none

echo "==> [6/6] Associando NSGs às subnets"
az network vnet subnet update \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name "$APP_SUBNET" --network-security-group "$NSG_PUBLIC" \
  --output none

az network vnet subnet update \
  --resource-group "$RG" --vnet-name "$VNET" \
  --name "$DATA_SUBNET" --network-security-group "$NSG_PRIVATE" \
  --output none

echo "OK — Rede e NSGs prontos."
