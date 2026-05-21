# Exclui o Resource Group inteiro (todos os recursos do lab).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/00_variables.sh"

echo "ATENCAO: este script vai EXCLUIR o Resource Group '$RG' e tudo dentro dele."
read -r -p "Digite 'DESTRUIR' para confirmar: " CONFIRM
if [[ "$CONFIRM" != "DESTRUIR" ]]; then
  echo "Cancelado."
  exit 1
fi

az group delete --name "$RG" --yes --no-wait
echo "Solicitacao enviada. Aguarde alguns minutos."
echo
echo "Para acompanhar:"
echo "  az group show --name $RG     # deve retornar 'ResourceGroupNotFound' quando terminar"
echo
echo "Captura final obrigatoria do relatorio:"
echo "  az group show --name $RG"
echo "  (saida do erro 'ResourceGroupNotFound' confirma que a exclusao foi concluida)"
