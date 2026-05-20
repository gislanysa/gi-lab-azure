# Provisiona a VM-DB (Ubuntu 22.04, Standard_B2s) SEM IP público,
# em data-subnet, com disco de dados Premium SSD 32GB anexado.
# Usa a SKU que ficou registrada em .lab_ips pelo script 02 (e tenta os


set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_variables.sh"
[[ -f "$SCRIPT_DIR/.lab_ips" ]] && source "$SCRIPT_DIR/.lab_ips"

# Tenta primeiro a SKU que funcionou no script 02 (se houver registro)
TRY_FIRST="${CHOSEN_VM_SIZE:-$VM_SIZE}"

try_create_db() {
  local size="$1"
  local logf
  logf="$(mktemp)"
  echo "    → tentando size=$size ..."
  if az vm create \
        --resource-group "$RG" \
        --name "$VM_DB" \
        --image "$VM_IMAGE" \
        --size "$size" \
        --vnet-name "$VNET" \
        --subnet "$DATA_SUBNET" \
        --public-ip-address "" \
        --admin-username "$ADMIN_USER" \
        --ssh-key-values "${SSH_KEY_PATH}.pub" \
        --nsg "" \
        --os-disk-name "${VM_DB}-osdisk" \
        --storage-sku StandardSSD_LRS \
        --tags $TAGS role=db \
        --output table 2>"$logf"
  then
    rm -f "$logf"
    echo "==> SUCESSO com $size"
    export CHOSEN_VM_SIZE_DB="$size"
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

echo "==> Criando $VM_DB em $DATA_SUBNET (sem IP público)"
SUCCESS=0
for size in "$TRY_FIRST" $VM_SIZE_FALLBACKS; do
  set +e
  try_create_db "$size"
  rc=$?
  set -e
  if [[ $rc -eq 0 ]]; then SUCCESS=1; break; fi
  if [[ $rc -ne 2 ]]; then exit $rc; fi
done
[[ $SUCCESS -ne 1 ]] && { echo "ERRO: nenhuma SKU disponível para VM-DB"; exit 1; }

echo "==> Anexando disco de dados $DB_DISK_NAME ($DB_DISK_SIZE_GB GB, $DB_DISK_SKU)"
az vm disk attach \
  --resource-group "$RG" \
  --vm-name "$VM_DB" \
  --name "$DB_DISK_NAME" \
  --new \
  --size-gb "$DB_DISK_SIZE_GB" \
  --sku "$DB_DISK_SKU" \
  --output table

DB_PRIV_IP="$(az vm show -d -g "$RG" -n "$VM_DB" --query privateIps -o tsv)"
echo "OK — VM-DB criada (size=$CHOSEN_VM_SIZE_DB, IP privado: $DB_PRIV_IP)"

# Persiste IP da DB para próximos scripts
if grep -q DB_PRIV_IP "$SCRIPT_DIR/.lab_ips" 2>/dev/null; then
  sed -i.bak '/DB_PRIV_IP/d' "$SCRIPT_DIR/.lab_ips" && rm -f "$SCRIPT_DIR/.lab_ips.bak"
fi
echo "export DB_PRIV_IP=$DB_PRIV_IP"        >> "$SCRIPT_DIR/.lab_ips"
echo "export CHOSEN_VM_SIZE_DB=$CHOSEN_VM_SIZE_DB" >> "$SCRIPT_DIR/.lab_ips"
