# Provisiona a VM-APP (Ubuntu 22.04, Standard_B2s) com IP público
# dinâmico, autenticação por chave SSH e sem NSG na NIC
# Tenta a SKU desejada (VM_SIZE) e, em caso de "SkuNotAvailable" ou
# "Capacity Restrictions", percorre VM_SIZE_FALLBACKS automaticamente.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_variables.sh"

if [[ ! -f "$SSH_KEY_PATH" ]]; then
  echo "==> Gerando chave SSH em $SSH_KEY_PATH"
  ssh-keygen -t ed25519 -f "$SSH_KEY_PATH" -N "" -C "marcozero-lab"
else
  echo "==> Chave SSH já existe em $SSH_KEY_PATH (reaproveitando)"
fi

try_create_vm() {
  local size="$1"
  local logf
  logf="$(mktemp)"
  echo "    → tentando size=$size ..."
  if az vm create \
        --resource-group "$RG" \
        --name "$VM_APP" \
        --image "$VM_IMAGE" \
        --size "$size" \
        --vnet-name "$VNET" \
        --subnet "$APP_SUBNET" \
        --public-ip-sku Standard \
        --public-ip-address-allocation Static \
        --admin-username "$ADMIN_USER" \
        --ssh-key-values "${SSH_KEY_PATH}.pub" \
        --nsg "" \
        --os-disk-name "${VM_APP}-osdisk" \
        --storage-sku StandardSSD_LRS \
        --tags $TAGS role=app \
        --output table 2>"$logf"
  then
    rm -f "$logf"
    echo "==> SUCESSO com $size"
    export CHOSEN_VM_SIZE="$size"
    return 0
  fi
  if grep -qE 'SkuNotAvailable|Capacity Restrictions' "$logf"; then
    echo "    ✗ $size indisponível (capacidade no datacenter) — próxima"
    rm -f "$logf"; return 2
  fi
  if grep -qE 'QuotaExceeded' "$logf"; then
    fam=$(grep -oE '[a-zA-Z]+Family' "$logf" | head -1)
    echo "    ✗ $size sem quota na assinatura (família $fam) — próxima"
    rm -f "$logf"; return 2
  fi
  echo "ERRO inesperado:"
  cat "$logf"
  rm -f "$logf"
  return 1
}

echo "==> Criando $VM_APP em $APP_SUBNET (público dinâmico)"
SUCCESS=0
for size in "$VM_SIZE" $VM_SIZE_FALLBACKS; do
  set +e
  try_create_vm "$size"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then SUCCESS=1; break; fi
  if [[ $rc -ne 2 ]]; then exit $rc; fi
done

if [[ $SUCCESS -ne 1 ]]; then
  echo "ERRO: nenhuma SKU disponível em $LOCATION (testadas: $VM_SIZE $VM_SIZE_FALLBACKS)"
  echo "Sugestão: trocar de região (ex.: export LOCATION=centralus; bash scripts/01_create_rg_network.sh ...)"
  exit 1
fi

# IP público 
APP_IP="$(az vm show -d -g "$RG" -n "$VM_APP" --query publicIps -o tsv)"
APP_PRIV_IP="$(az vm show -d -g "$RG" -n "$VM_APP" --query privateIps -o tsv)"

echo "OK — VM-APP criada (size=$CHOSEN_VM_SIZE)"
echo "    IP público : $APP_IP"
echo "    IP privado : $APP_PRIV_IP"
echo "    Acesso SSH : ssh -i $SSH_KEY_PATH $ADMIN_USER@$APP_IP"

# Persiste IPs + a SKU que efetivamente subiu
echo "export APP_IP=$APP_IP"               >  "$SCRIPT_DIR/.lab_ips"
echo "export APP_PRIV_IP=$APP_PRIV_IP"     >> "$SCRIPT_DIR/.lab_ips"
echo "export CHOSEN_VM_SIZE=$CHOSEN_VM_SIZE" >> "$SCRIPT_DIR/.lab_ips"
