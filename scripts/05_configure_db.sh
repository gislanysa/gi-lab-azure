# Configura a VM-DB acessando-a VIA VM-APP (bastion).
#   - Formata o disco anexado e monta em /var/lib/mysql
#   - Instala MySQL 8 e move o datadir para o disco
#   - Aplica securização (mysql_secure_installation equivalente)
#   - Carrega schema sql/schema.sql (banco + usuário + tabelas + seeds)


set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
source "$SCRIPT_DIR/00_variables.sh"
source "$SCRIPT_DIR/.lab_ips"

# Habilita agent forwarding — usaremos a chave local para pular da APP -> DB
eval "$(ssh-agent -s)" >/dev/null
ssh-add "$SSH_KEY_PATH" >/dev/null

SSH_APP="ssh -A -i $SSH_KEY_PATH -o StrictHostKeyChecking=accept-new $ADMIN_USER@$APP_IP"

echo "==> [1/4] Copiando schema.sql para a VM-APP (escala intermediária)"
scp -i "$SSH_KEY_PATH" -o StrictHostKeyChecking=accept-new \
  "$ROOT_DIR/sql/schema.sql" "$ADMIN_USER@$APP_IP:/tmp/schema.sql"

echo "==> [2/4] Da VM-APP, copiando schema.sql para a VM-DB"
$SSH_APP "scp -o StrictHostKeyChecking=accept-new /tmp/schema.sql $ADMIN_USER@$DB_PRIV_IP:/tmp/schema.sql"

echo "==> [3/4] Configurando disco + MySQL na VM-DB (via bastion)"
# Usamos heredoc dentro do heredoc cuidando do escape das vars locais
$SSH_APP "ssh -o StrictHostKeyChecking=accept-new $ADMIN_USER@$DB_PRIV_IP \
  'MYSQL_ROOT_PWD=$MYSQL_ROOT_PWD MYSQL_APP_PWD=$MYSQL_APP_PWD APP_CIDR=$APP_SUBNET_CIDR bash -s'" <<'REMOTE'
set -euo pipefail

# --- a) Identificar e formatar o disco extra ----------------------------
# Em B2s o disco extra costuma aparecer como /dev/sdc (sda=os, sdb=temp).
DEV=""
for cand in /dev/sdc /dev/sdd; do
  if [[ -b "$cand" ]] && ! lsblk -no MOUNTPOINT "$cand" | grep -q .; then
    DEV="$cand"; break
  fi
done
if [[ -z "$DEV" ]]; then
  echo "ERRO: nao foi possivel localizar o disco de dados anexado" >&2
  lsblk; exit 1
fi
echo "Disco de dados: $DEV"

if ! sudo blkid "$DEV" >/dev/null 2>&1; then
  sudo mkfs.ext4 -F "$DEV"
fi
sudo mkdir -p /mnt/mysql-data
UUID=$(sudo blkid -s UUID -o value "$DEV")
grep -q "$UUID" /etc/fstab || \
  echo "UUID=$UUID /mnt/mysql-data ext4 defaults,nofail 0 2" | sudo tee -a /etc/fstab
sudo mount -a
df -h /mnt/mysql-data

# --- b) Instalar MySQL 8 ------------------------------------------------
sudo apt-get update -y
sudo DEBIAN_FRONTEND=noninteractive apt-get install -y mysql-server

# --- c) Parar e mover o datadir ----------------------------------------
sudo systemctl stop mysql
if [[ ! -f /mnt/mysql-data/.migrated ]]; then
  sudo rsync -av /var/lib/mysql/ /mnt/mysql-data/
  sudo touch /mnt/mysql-data/.migrated
fi
sudo chown -R mysql:mysql /mnt/mysql-data

# Aponta o datadir e o bind-address
sudo tee /etc/mysql/mysql.conf.d/marcozero.cnf >/dev/null <<CNF
[mysqld]
datadir         = /mnt/mysql-data
bind-address    = 0.0.0.0
default-authentication-plugin = mysql_native_password
CNF

# AppArmor precisa permitir o novo datadir
if [[ -f /etc/apparmor.d/usr.sbin.mysqld ]]; then
  sudo sed -i 's|/var/lib/mysql/|/mnt/mysql-data/|g' /etc/apparmor.d/usr.sbin.mysqld || true
  sudo systemctl reload apparmor || true
fi

sudo systemctl start mysql
sudo systemctl enable mysql

# --- d) Securização (equivalente ao mysql_secure_installation) ---------
sudo mysql <<SQL
ALTER USER 'root'@'localhost' IDENTIFIED WITH mysql_native_password BY '${MYSQL_ROOT_PWD}';
DELETE FROM mysql.user WHERE User='';
DELETE FROM mysql.user WHERE User='root' AND Host NOT IN ('localhost','127.0.0.1','::1');
DROP DATABASE IF EXISTS test;
DELETE FROM mysql.db WHERE Db='test' OR Db='test\\_%';
FLUSH PRIVILEGES;
SQL

# --- e) Carrega schema + cria usuario de aplicacao restrito ao subnet --
mysql -uroot -p"${MYSQL_ROOT_PWD}" < /tmp/schema.sql
mysql -uroot -p"${MYSQL_ROOT_PWD}" <<SQL
CREATE USER IF NOT EXISTS 'app_user'@'10.0.1.%' IDENTIFIED BY '${MYSQL_APP_PWD}';
GRANT SELECT, INSERT, UPDATE, DELETE ON marcozero_ecommerce.* TO 'app_user'@'10.0.1.%';
FLUSH PRIVILEGES;
SQL

echo "OK - MySQL configurado, datadir em $(sudo mysql -uroot -p'${MYSQL_ROOT_PWD}' -Nse 'SELECT @@datadir')"
REMOTE

echo "==> [4/4] Limpando arquivo temporário do schema na VM-APP"
$SSH_APP "rm -f /tmp/schema.sql"

echo "OK — VM-DB configurada e banco carregado."
