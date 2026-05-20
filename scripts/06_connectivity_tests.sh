# Executa os 4 testes obrigatórios do item 4.4 do enunciado e
# imprime resultados rotulados PASS/FAIL para captura no relatório.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_variables.sh"
source "$SCRIPT_DIR/.lab_ips"

pass() { echo -e "\033[32m[PASS]\033[0m $*"; }
fail() { echo -e "\033[31m[FAIL]\033[0m $*"; }

echo "================================================================"
echo "TESTE 1 — SSH local -> VM-APP (DEVE funcionar)"
echo "================================================================"
if ssh -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
       "$ADMIN_USER@$APP_IP" "hostname && uptime"; then
  pass "Acesso SSH publico a VM-APP funcionando"
else
  fail "Nao foi possivel acessar VM-APP via SSH"
fi
echo

echo "================================================================"
echo "TESTE 2 — SSH local -> VM-DB (DEVE falhar por timeout)"
echo "================================================================"
if timeout 12 ssh -i "$SSH_KEY_PATH" \
     -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
     -o BatchMode=yes \
     "$ADMIN_USER@$DB_PRIV_IP" "hostname" 2>&1; then
  fail "VM-DB respondeu SSH da Internet — NSG esta permissivo demais!"
else
  pass "VM-DB inacessivel diretamente (timeout/conn refused conforme esperado)"
fi
echo

echo "================================================================"
echo "TESTE 3 — VM-APP -> VM-DB (bastion via agent forwarding)"
echo "================================================================"
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$SSH_KEY_PATH" >/dev/null
if ssh -A -i "$SSH_KEY_PATH" -o ConnectTimeout=10 -o StrictHostKeyChecking=accept-new \
       "$ADMIN_USER@$APP_IP" \
       "ssh -o StrictHostKeyChecking=accept-new $ADMIN_USER@$DB_PRIV_IP 'hostname && uname -a'"; then
  pass "Bastion funcionou: VM-APP alcanca VM-DB via SSH"
else
  fail "Bastion falhou — verificar agent forwarding e NSG-Private regra 110"
fi
echo

echo "================================================================"
echo "TESTE 4 — App HTTP (VM-APP) consulta banco (VM-DB)"
echo "================================================================"
HEALTH_JSON="$(curl -s -m 10 "http://$APP_IP/health" || echo '{"error":"timeout"}')"
PRODUTOS_JSON="$(curl -s -m 10 "http://$APP_IP/produtos" || echo '[]')"

echo "GET /health    -> $HEALTH_JSON"
echo "GET /produtos  -> $(echo "$PRODUTOS_JSON" | head -c 400)..."

if echo "$HEALTH_JSON" | grep -q '"db":"ok"' && \
   echo "$PRODUTOS_JSON" | grep -q '"id"'; then
  pass "Aplicacao na VM-APP consulta banco na VM-DB com sucesso"
else
  fail "Aplicacao nao conseguiu listar registros do banco"
fi
echo

echo "================================================================"
echo "RESUMO DOS RECURSOS"
echo "================================================================"
az resource list -g "$RG" --query "[].{Name:name, Type:type, Loc:location}" -o table
