# Instala Node.js 20, PM2, Nginx na VM-APP, faz upload da aplicação,
# configura reverse proxy 80 -> 3000 e sobe os processos PM2.
# Roda DA MÁQUINA LOCAL (usa SSH para entrar na VM-APP).

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/00_variables.sh"
source "$SCRIPT_DIR/.lab_ips"
SSH="ssh -i $SSH_KEY_PATH -o StrictHostKeyChecking=accept-new $ADMIN_USER@$APP_IP"
SCP="scp -i $SSH_KEY_PATH -o StrictHostKeyChecking=accept-new"
echo "==> [1/4] Instalando Node.js 20 + Nginx + PM2 em $APP_IP"
$SSH 'bash -se' <<'REMOTE'
set -euo pipefail
sudo apt-get update -y
sudo apt-get install -y curl ca-certificates gnupg
curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
sudo apt-get install -y nodejs nginx
sudo npm install -g pm2@latest
node -v && npm -v && nginx -v && pm2 -v
REMOTE
echo "==> [2/4] Enviando aplicação e configuração do Nginx"
$SSH "rm -rf /home/$ADMIN_USER/app && mkdir -p /home/$ADMIN_USER/app"
$SCP -r "$ROOT_DIR/app/." "$ADMIN_USER@$APP_IP:/home/$ADMIN_USER/app/"
$SCP "$ROOT_DIR/nginx/marcozero.conf" "$ADMIN_USER@$APP_IP:/tmp/marcozero.conf"
echo "==> [3/4] Configurando .env da aplicação (DB_HOST = $DB_PRIV_IP)"
$SSH "cat > /home/$ADMIN_USER/app/.env <<EOF
PORT=3000
DB_HOST=$DB_PRIV_IP
DB_PORT=3306
DB_NAME=marcozero_ecommerce
DB_USER=app_user
DB_PASSWORD=$MYSQL_APP_PWD
EOF
chmod 600 /home/$ADMIN_USER/app/.env"
echo "==> [4/4] Instalando dependências e subindo PM2 + Nginx"
$SSH 'bash -se' <<'REMOTE'
set -euo pipefail
cd ~/app
if [[ -f package-lock.json ]]; then
	npm ci --omit=dev
else
	npm install --omit=dev
fi
mkdir -p ~/app/logs
pm2 start ecosystem.config.js
pm2 save
sudo env PATH=$PATH:/usr/bin pm2 startup systemd -u $USER --hp $HOME | tail -1 | sudo bash || true
sudo mv /tmp/marcozero.conf /etc/nginx/sites-available/marcozero
sudo ln -sf /etc/nginx/sites-available/marcozero /etc/nginx/sites-enabled/marcozero
sudo rm -f /etc/nginx/sites-enabled/default
sudo nginx -t
sudo systemctl reload nginx
pm2 status
REMOTE
echo "OK — App online: http://$APP_IP/health"
