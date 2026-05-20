# Variáveis globais usadas por todos os scripts deste lab.

export RG="rg-marcozero-hom-gl"
export LOCATION="${LOCATION:-centralus}"   # Brazil South fora da cota Azure for Students
export TAGS="env=hom projeto=marcozero owner=gislany disciplina=cloud-computing"

# Rede
export VNET="vnet-marcozero"
export VNET_CIDR="10.0.0.0/16"
export APP_SUBNET="app-subnet"
export APP_SUBNET_CIDR="10.0.1.0/24"
export DATA_SUBNET="data-subnet"
export DATA_SUBNET_CIDR="10.0.2.0/24"

export NSG_PUBLIC="nsg-public"
export NSG_PRIVATE="nsg-private"

# VMs 
export VM_APP="vm-app"
export VM_DB="vm-db"
export VM_SIZE="${VM_SIZE:-Standard_B2s}"
export VM_SIZE_FALLBACKS="\
Standard_B2s_v2 \
Standard_B2ls_v2 \
Standard_B2ms \
Standard_B2as_v2 \
Standard_B2als_v2 \
Standard_B1ms \
Standard_D2s_v3 \
Standard_DS2_v2 \
Standard_D2as_v4 \
Standard_DS1_v2 \
Standard_D2s_v5 \
Standard_D2as_v5 \
Standard_A2_v2 \
Standard_F2s_v2"
export VM_IMAGE="Ubuntu2204"
export ADMIN_USER="azureuser"
export SSH_KEY_PATH="$HOME/.ssh/marcozero_key"

# Disco extra da VM-DB 
export DB_DISK_NAME="vm-db-data"
export DB_DISK_SIZE_GB=32
export DB_DISK_SKU="Premium_LRS"

# IP público do laboratório (origem permitida no SSH da VM-APP)
if [[ -z "${LAB_PUBLIC_IP:-}" ]]; then
  export LAB_PUBLIC_IP="$(curl -s -4 ifconfig.me)"
fi

# Senha do MySQL 
: "${MYSQL_ROOT_PWD:=TrocarSenhaRoot#2026}"
: "${MYSQL_APP_PWD:=TrocarSenhaApp#2026}"
export MYSQL_ROOT_PWD MYSQL_APP_PWD

echo "[vars] RG=$RG  LOC=$LOCATION  LAB_PUBLIC_IP=$LAB_PUBLIC_IP"
