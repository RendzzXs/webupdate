#!/bin/bash
# ============================================
#   👑 RENDZZ ULTIMATE INSTALLER v36.0 FINAL
#   Casino • Gacha • WAF • Full Money System
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; MAGENTA='\033[0;35m'; WHITE='\033[1;37m'; NC='\033[0m'

[[ $EUID -ne 0 ]] && { echo -e "${RED}❌ Harus root!${NC}"; exit 1; }

clear
echo -e "${CYAN}╔════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║  👑 RENDZZ ULTIMATE INSTALLER v36.0 FINAL  ║${NC}"
echo -e "${CYAN}║  Casino • Gacha • WAF • Full Money System  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════╝${NC}"
echo ""

read -p "👉 Masukkan Domain Web (contoh: panel.domain.com): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }

read -p "👉 Email SSL (buat Let's Encrypt): " EMAIL
[[ -z "$EMAIL" ]] && EMAIL="admin@$DOMAIN"

echo ""

WEB_ROOT="/var/www/$DOMAIN"
DB_NAME="reseller_$(echo $DOMAIN | tr '.' '_' | cut -c1-20)"
DB_USER="reseller"
DB_PASS=$(openssl rand -hex 16)
NGINX_CONF="/etc/nginx/sites-available/$DOMAIN"

# ============================================
# 1. INSTALL DEPENDENCY
# ============================================
echo -e "${CYAN}[1/7] Install Dependency...${NC}"
export DEBIAN_FRONTEND=noninteractive
rm -f /var/lib/dpkg/lock-frontend /var/lib/dpkg/lock /var/cache/apt/archives/lock /var/lib/apt/lists/lock
dpkg --configure -a >/dev/null 2>&1
apt --fix-broken install -y -qq >/dev/null 2>&1

apt update -qq 2>/dev/null
apt install -y software-properties-common curl wget git unzip >/dev/null 2>&1
add-apt-repository -y ppa:ondrej/php >/dev/null 2>&1
apt update -qq 2>/dev/null

apt install -y nginx php8.3-fpm php8.3-mysql php8.3-mbstring php8.3-curl php8.3-xml php8.3-zip php8.3-gd php8.3-intl php8.3-bcmath mariadb-server mariadb-client certbot python3-certbot-nginx >/dev/null 2>&1
apt install -y -o Dpkg::Options::="--force-confnew" mariadb-server >/dev/null 2>&1

systemctl enable --now nginx php8.3-fpm mariadb >/dev/null 2>&1
echo -e "${GREEN}  ✅ Dependency Siap${NC}\n"

# ============================================
# 2. SETUP DATABASE
# ============================================
echo -e "${CYAN}[2/7] Setup Database (Full Tables)...${NC}"
mysql -e "DROP DATABASE IF EXISTS \`$DB_NAME\`;" 2>/dev/null
mysql -e "CREATE DATABASE \`$DB_NAME\` CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;" 2>/dev/null

mysql "$DB_NAME" << SQLEOF 2>/dev/null
CREATE TABLE users (
    id INT AUTO_INCREMENT PRIMARY KEY,
    username VARCHAR(50) UNIQUE NOT NULL,
    email VARCHAR(100) DEFAULT NULL,
    password VARCHAR(255) NOT NULL,
    role ENUM('admin','user') DEFAULT 'user',
    status ENUM('active','banned') DEFAULT 'active',
    is_verified TINYINT(1) DEFAULT 0,
    avatar VARCHAR(255) DEFAULT NULL,
    balance INT DEFAULT 0,
    referred_by INT DEFAULT NULL,
    referral_count INT DEFAULT 0,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE servers (
    id INT AUTO_INCREMENT PRIMARY KEY,
    user_id INT,
    server_name VARCHAR(100),
    ptero_id INT,
    ram INT,
    email VARCHAR(100) DEFAULT NULL,
    password VARCHAR(100) DEFAULT NULL,
    status ENUM('active','suspended') DEFAULT 'active',
    abuse_reason VARCHAR(255) DEFAULT NULL,
    created_at DATETIME DEFAULT CURRENT_TIMESTAMP
);
CREATE TABLE settings (k VARCHAR(50) PRIMARY KEY, v TEXT);
CREATE TABLE chats (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT, username VARCHAR(50), message TEXT, is_admin TINYINT(1) DEFAULT 0, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE announcements (id INT AUTO_INCREMENT PRIMARY KEY, message TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE password_requests (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, status ENUM('pending','approved') DEFAULT 'pending', new_password VARCHAR(255) DEFAULT NULL, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE verify_requests (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, status ENUM('pending','approved','rejected') DEFAULT 'pending', created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE reviews (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, rating INT NOT NULL, comment TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE withdrawals (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT NOT NULL, amount INT NOT NULL, dana_number VARCHAR(20) NOT NULL, status ENUM('pending','approved','rejected') DEFAULT 'pending', created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE hack_logs (id INT AUTO_INCREMENT PRIMARY KEY, ip_address VARCHAR(50), username VARCHAR(50), action TEXT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE gacha_logs (id INT AUTO_INCREMENT PRIMARY KEY, user_id INT, bet_amount INT, win_amount INT, status ENUM('win','lose') DEFAULT 'lose', created_at DATETIME DEFAULT CURRENT_TIMESTAMP);
CREATE TABLE wd_logs_public (id INT AUTO_INCREMENT PRIMARY KEY, masked_name VARCHAR(50), amount INT, created_at DATETIME DEFAULT CURRENT_TIMESTAMP);

INSERT INTO settings VALUES 
('ptero_domain', ''), ('ptla', ''), ('ptlc', ''), ('location_id', '1'), ('egg_id', '15'),
('maintenance', '0'), ('maintenance_msg', 'Website sedang dalam perbaikan.'),
('ptero_create_status', 'on'), ('gacha_winrate', '50');

INSERT INTO users (username, email, password, role) VALUES ('aulia', 'admin@$DOMAIN', 'ADMIN_HASH_PLACEHOLDER', 'admin');
SQLEOF

ADMIN_HASH=$(php -r "echo password_hash('aulia55', PASSWORD_BCRYPT);")
mysql "$DB_NAME" -e "UPDATE users SET password='$ADMIN_HASH' WHERE username='aulia';" 2>/dev/null

mysql -e "DROP USER IF EXISTS '$DB_USER'@'localhost';" 2>/dev/null
mysql -e "CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS';" 2>/dev/null
mysql -e "GRANT ALL PRIVILEGES ON \`$DB_NAME\`.* TO '$DB_USER'@'localhost';" 2>/dev/null
mysql -e "FLUSH PRIVILEGES;" 2>/dev/null
echo -e "${GREEN}  ✅ Database Siap${NC}\n"

# ============================================
# 3. BIKIN FOLDER & CONFIG (WAF + ANTI ADMIN)
# ============================================
echo -e "${CYAN}[3/7] Bikin Config & Security (WAF)...${NC}"
rm -rf "$WEB_ROOT"
mkdir -p "$WEB_ROOT"/{includes,assets/css,uploads/avatars,api,admin,tools}

cat > "$WEB_ROOT/includes/config.php" << PHPEOF
<?php
ini_set('session.cookie_lifetime', 86400 * 30);
ini_set('session.gc_maxlifetime', 86400 * 30);
session_set_cookie_params(86400 * 30, '/', '', false, true);
session_start();

date_default_timezone_set('Asia/Jakarta');
define('DB_HOST', '127.0.0.1');
define('DB_NAME', '$DB_NAME');
define('DB_USER', '$DB_USER');
define('DB_PASS', '$DB_PASS');
define('SITE_NAME', 'Rendzz Premium');

try {
    \$pdo = new PDO("mysql:host=".DB_HOST.";dbname=".DB_NAME.";charset=utf8mb4", DB_USER, DB_PASS, [
        PDO::ATTR_ERRMODE => PDO::ERRMODE_EXCEPTION,
        PDO::ATTR_DEFAULT_FETCH_MODE => PDO::FETCH_ASSOC,
    ]);
} catch (PDOException \$e) { die("DB Error: " . \$e->getMessage()); }

function isLoggedIn() { return isset(\$_SESSION['user_id']); }
function isAdmin() { return isLoggedIn() && \$_SESSION['role'] === 'admin'; }
function requireLogin() { if (!isLoggedIn()) { header('Location: /login.php'); exit; } }
function requireAdmin() { if (!isAdmin()) { header('Location: /'); exit; } }
function getSetting(\$pdo, \$k, \$default = '') {
    \$s = \$pdo->prepare("SELECT v FROM settings WHERE k=?"); \$s->execute([\$k]);
    \$r = \$s->fetch(); return \$r ? \$r['v'] : \$default;
}

// WAF (WEB APPLICATION FIREWALL) - ANTI SQLi
\$badWords = ['UNION', 'SELECT', 'DROP', 'INSERT', 'DELETE', 'UPDATE', 'SCRIPT', 'ALERT', 'ONERROR', 'EVAL', 'BASE64'];
\$requestUri = strtoupper(urldecode(\$_SERVER['REQUEST_URI']));
foreach (\$badWords as \$word) {
    if (strpos(\$requestUri, \$word) !== false) {
        \$ip = \$_SERVER['REMOTE_ADDR']; \$usr = \$_SESSION['username'] ?? 'Guest';
        \$act = "SQLi/XSS Attempt: " . substr(\$_SERVER['REQUEST_URI'], 0, 100);
        try { \$pdo->prepare("INSERT INTO hack_logs (ip_address, username, action) VALUES (?,?,?)")->execute([\$ip, \$usr, \$act]); } catch (Exception \$e) {}
        die("<body style='background:#000;color:#ff0000;font-family:monospace;display:flex;justify-content:center;align-items:center;height:100vh;text-align:center;'><div><h1 style='font-size:3em;'>🚫 WAF DETECTED 🚫</h1><p>Percobaan Hack Terdeteksi. IP Kamu: <b>\$ip</b></p></div></body>");
    }
}

// ANTI HACK DASHBOARD ADMIN
if (strpos(\$_SERVER['PHP_SELF'], '/admin/') !== false && !isAdmin()) {
    \$ip = \$_SERVER['REMOTE_ADDR']; \$usr = \$_SESSION['username'] ?? 'Guest';
    \$act = "Mencoba akses Admin Panel tanpa izin";
    try { \$pdo->prepare("INSERT INTO hack_logs (ip_address, username, action) VALUES (?,?,?)")->execute([\$ip, \$usr, \$act]); } catch (Exception \$e) {}
    die("<body style='background:#050508;color:#fff;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;text-align:center;'><div><h1 style='font-size:3em;color:#ef4444;'>LU SIAPA NGENTOD?</h1><p style='color:#94a3b8;font-size:1.2em;'>Mau ngapain nge-hack panel orang, woy!</p><p style='color:#64748b;font-size:0.8em;margin-top:20px;'>IP Kamu: \$ip sudah kami catat.</p></div></body>");
}

if (!isLoggedIn() && isset(\$_COOKIE['rendzz_remember'])) {
    \$token = \$_COOKIE['rendzz_remember']; \$parts = explode(':', \$token);
    if (count(\$parts) == 2) {
        \$uid = (int)\$parts[0];
        \$u = \$pdo->prepare("SELECT * FROM users WHERE id=?"); \$u->execute([\$uid]); \$user = \$u->fetch();
        if (\$user && password_verify(\$parts[1], \$user['password'])) {
            \$_SESSION['user_id'] = \$user['id']; \$_SESSION['username'] = \$user['username']; \$_SESSION['role'] = \$user['role'];
        }
    }
}

\$maintenance = getSetting(\$pdo, 'maintenance', '0');
if (\$maintenance == '1' && !isAdmin() && basename(\$_SERVER['PHP_SELF']) != 'login.php') {
    \$msg = getSetting(\$pdo, 'maintenance_msg', 'Maintenance.');
    die("<body style='background:#050508;color:#fff;font-family:sans-serif;display:flex;justify-content:center;align-items:center;height:100vh;text-align:center;'><div><h1 style='color:#f59e0b;'>🚧 MAINTENANCE 🚧</h1><p style='color:#94a3b8;'>\$msg</p></div></body>");
}

function checkPteroStatus(\$pdo) {
    \$domain = rtrim(getSetting(\$pdo, 'ptero_domain'), '/'); \$ptla = getSetting(\$pdo, 'ptla');
    if (empty(\$domain) || empty(\$ptla)) return false;
    \$ch = curl_init("\$domain/api/application/nodes");
    curl_setopt_array(\$ch, [CURLOPT_RETURNTRANSFER => true, CURLOPT_TIMEOUT => 3, CURLOPT_HTTPHEADER => ["Authorization: Bearer \$ptla", "Accept: application/json"]]);
    curl_exec(\$ch); \$code = curl_getinfo(\$ch, CURLINFO_HTTP_CODE); curl_close(\$ch);
    return (\$code >= 200 && \$code < 300);
}
PHPEOF
echo -e "${GREEN}  ✅ Config & Security OK${NC}\n"

# ============================================
# 4. CSS (PREMIUM THEME + SPLIT LOGIN)
# ============================================
echo -e "${CYAN}[4/7] Bikin CSS Premium...${NC}"
cat > "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'
@import url('https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap');
:root {
    --bg: #050508; --bg-gradient: radial-gradient(circle at 0% 0%, #1a1a2e 0%, #050508 50%), radial-gradient(circle at 100% 100%, #16213e 0%, transparent 50%);
    --card: rgba(30, 30, 50, 0.5); --glass-border: rgba(255, 255, 255, 0.08); --text: #ffffff; --text-muted: #94a3b8;
    --primary: #6366f1; --primary-glow: rgba(99, 102, 241, 0.5); --success: #10b981; --danger: #ef4444; --warning: #f59e0b;
    --gradient: linear-gradient(135deg, #6366f1 0%, #8b5cf6 50%, #ec4899 100%);
}
[data-theme="light"] { --bg: #f8fafc; --bg-gradient: radial-gradient(circle at 0% 0%, #e0e7ff 0%, #f8fafc 50%); --card: rgba(255, 255, 255, 0.8); --glass-border: rgba(0, 0, 0, 0.08); --text: #0f172a; --text-muted: #64748b; }
[data-theme="amoled"] { --bg: #000000; --bg-gradient: none; --card: rgba(20, 20, 20, 0.8); --glass-border: rgba(255, 255, 255, 0.1); --text: #ffffff; --text-muted: #888888; }

* { margin: 0; padding: 0; box-sizing: border-box; font-family: 'Plus Jakarta Sans', sans-serif; }
body { background: var(--bg); background-image: var(--bg-gradient); background-attachment: fixed; color: var(--text); min-height: 100vh; padding-top: 70px; padding-bottom: 80px; -webkit-font-smoothing: antialiased; transition: background 0.3s; }
a { color: inherit; text-decoration: none; }
.container { max-width: 800px; margin: 0 auto; padding: 20px; }
.top-nav { position: fixed; top: 0; left: 0; right: 0; display: flex; justify-content: space-between; align-items: center; padding: 12px 20px; background: rgba(10, 10, 20, 0.85); backdrop-filter: blur(20px); border-bottom: 1px solid var(--glass-border); z-index: 9998; }
[data-theme="light"] .top-nav { background: rgba(255,255,255,0.85); }
.brand { font-size: 1.2em; font-weight: 800; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; display: flex; align-items: center; gap: 8px; }
.nav-actions { display: flex; gap: 8px; align-items: center; }
.nav-btn { width: 40px; height: 40px; border-radius: 12px; background: var(--card); border: 1px solid var(--glass-border); color: var(--text); font-size: 1.1em; cursor: pointer; display: flex; align-items: center; justify-content: center; transition: all 0.3s; position: relative; }
.nav-btn:hover { border-color: var(--primary); color: var(--primary); }
.badge-notif { position: absolute; top: -4px; right: -4px; background: var(--danger); color: #fff; font-size: 0.6em; font-weight: 800; width: 18px; height: 18px; border-radius: 50%; display: flex; align-items: center; justify-content: center; border: 2px solid var(--bg); }
.sidebar-overlay { position: fixed; inset: 0; background: rgba(0,0,0,0.7); backdrop-filter: blur(5px); z-index: 9999; opacity: 0; visibility: hidden; transition: all 0.3s; }
.sidebar-overlay.active { opacity: 1; visibility: visible; }
.sidebar { position: fixed; top: 0; left: -320px; width: 300px; height: 100vh; background: var(--card); backdrop-filter: blur(20px); border-right: 1px solid var(--glass-border); z-index: 10000; transition: left 0.4s cubic-bezier(0.175, 0.885, 0.32, 1.275); overflow-y: auto; }
.sidebar.open { left: 0; }
.sidebar-header { padding: 20px; border-bottom: 1px solid var(--glass-border); display: flex; justify-content: space-between; align-items: center; }
.sidebar-title { font-size: 1.1em; font-weight: 800; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; }
.sidebar-nav { padding: 15px; }
.sidebar-label { font-size: 0.7em; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1.5px; font-weight: 700; padding: 15px 15px 8px; }
.sidebar-link { display: flex; align-items: center; gap: 12px; padding: 12px 15px; border-radius: 12px; color: var(--text); font-weight: 600; font-size: 0.95em; transition: all 0.2s; margin-bottom: 2px; }
.sidebar-link:hover { background: rgba(99, 102, 241, 0.1); color: var(--primary); transform: translateX(4px); }
.sidebar-link i { width: 22px; text-align: center; font-size: 1.1em; color: var(--text-muted); }
.sidebar-link:hover i { color: var(--primary); }
.card { background: var(--card); backdrop-filter: blur(20px); border: 1px solid var(--glass-border); border-radius: 20px; padding: 24px; margin-bottom: 20px; transition: all 0.3s; animation: slideUp 0.5s ease-out; }
@keyframes slideUp { from { opacity: 0; transform: translateY(20px); } to { opacity: 1; transform: translateY(0); } }
.btn { padding: 12px 20px; border-radius: 12px; border: none; font-weight: 700; font-family: inherit; font-size: 0.9em; cursor: pointer; display: inline-flex; align-items: center; justify-content: center; gap: 8px; transition: all 0.3s; text-decoration: none; }
.btn-primary { background: var(--gradient); color: #fff; box-shadow: 0 4px 15px var(--primary-glow); }
.btn-primary:hover { transform: translateY(-2px); box-shadow: 0 8px 25px var(--primary-glow); }
.btn-danger { background: rgba(239, 68, 68, 0.15); color: var(--danger); border: 1px solid var(--danger); }
.btn-danger:hover { background: var(--danger); color: #fff; }
.btn-success { background: rgba(16, 185, 129, 0.15); color: var(--success); border: 1px solid var(--success); }
.btn-warning { background: rgba(245, 158, 11, 0.15); color: var(--warning); border: 1px solid var(--warning); }
.btn-disabled { background: #374151; color: #9ca3af; border: 1px solid #4b5563; cursor: not-allowed; transform: none !important; }
.btn-block { width: 100%; }
.btn-sm { padding: 8px 12px; font-size: 0.8em; border-radius: 8px; }
.btn-large { padding: 16px 32px; font-size: 1em; border-radius: 14px; }
.form-group { margin-bottom: 16px; }
.form-group label { display: block; margin-bottom: 8px; font-size: 0.85em; color: var(--text-muted); font-weight: 600; text-transform: uppercase; letter-spacing: 0.5px; }
.form-group input, .form-group select, .form-group textarea { width: 100%; padding: 12px 16px; border: 1px solid var(--glass-border); border-radius: 12px; background: rgba(0, 0, 0, 0.3); color: var(--text); font-family: inherit; font-size: 0.95em; outline: none; transition: all 0.2s; }
.form-group input:focus, .form-group select:focus, .form-group textarea:focus { border-color: var(--primary); box-shadow: 0 0 0 3px var(--primary-glow); }
.alert { padding: 14px 18px; border-radius: 12px; margin-bottom: 16px; font-size: 0.9em; font-weight: 600; display: flex; align-items: center; gap: 10px; }
.alert-error { background: rgba(239, 68, 68, 0.15); color: var(--danger); border: 1px solid rgba(239, 68, 68, 0.3); }
.alert-success { background: rgba(16, 185, 129, 0.15); color: var(--success); border: 1px solid rgba(16, 185, 129, 0.3); }
.badge { padding: 4px 10px; border-radius: 6px; font-size: 0.75em; font-weight: 800; text-transform: uppercase; }
.badge-active { background: rgba(16, 185, 129, 0.15); color: var(--success); }
.badge-banned { background: rgba(239, 68, 68, 0.15); color: var(--danger); }
.bottom-nav { position: fixed; bottom: 15px; left: 15px; right: 15px; background: var(--card); backdrop-filter: blur(20px); border: 1px solid var(--glass-border); border-radius: 24px; display: flex; justify-content: space-around; padding: 10px 0; z-index: 9997; max-width: 500px; margin: 0 auto; box-shadow: 0 10px 40px rgba(0,0,0,0.3); }
.nav-item { display: flex; flex-direction: column; align-items: center; gap: 4px; color: var(--text-muted); font-size: 0.7em; font-weight: 700; padding: 8px 16px; border-radius: 16px; transition: all 0.3s; }
.nav-item i { font-size: 1.4em; }
.nav-item:hover, .nav-item.active { color: var(--primary); background: rgba(99, 102, 241, 0.15); transform: translateY(-4px); }
.tabs { display: flex; gap: 8px; margin-bottom: 20px; overflow-x: auto; padding: 6px; background: rgba(0,0,0,0.2); border-radius: 16px; border: 1px solid var(--glass-border); }
.tab-btn { padding: 10px 18px; border-radius: 12px; border: none; background: transparent; color: var(--text-muted); cursor: pointer; font-weight: 700; font-size: 0.85em; white-space: nowrap; transition: all 0.3s; display: flex; align-items: center; gap: 6px; }
.tab-btn.active { background: var(--gradient); color: #fff; }
.tab-content { display: none; }
.tab-content.active { display: block; animation: slideUp 0.3s; }
.stat-value { font-size: 2em; font-weight: 800; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; display: block; line-height: 1.2; }
.stat-label { font-size: 0.7em; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; font-weight: 700; margin-top: 4px; }
.copyright { text-align: center; padding: 30px 20px; font-size: 0.8em; color: var(--text-muted); margin-top: 30px; }
.copyright span { background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; font-weight: 800; }
.hero-section { text-align: center; padding: 60px 20px 40px; }
.hero-title { font-size: 2.8em; font-weight: 800; line-height: 1.15; margin-bottom: 20px; letter-spacing: -1.5px; }
.hero-title .gradient-text { background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; display: block; }
.hero-subtitle { font-size: 1.1em; color: var(--text-muted); max-width: 600px; margin: 0 auto 35px; line-height: 1.6; }
.stats-section { display: grid; grid-template-columns: repeat(3, 1fr); gap: 16px; max-width: 800px; margin: 0 auto 60px; padding: 0 20px; }
.stat-card { background: var(--card); backdrop-filter: blur(20px); border: 1px solid var(--glass-border); border-radius: 20px; padding: 30px 15px; text-align: center; transition: all 0.4s; }
.stat-card:hover { transform: translateY(-8px); border-color: var(--primary); box-shadow: 0 20px 40px var(--primary-glow); }
.stat-icon { width: 55px; height: 55px; border-radius: 16px; display: flex; align-items: center; justify-content: center; margin: 0 auto 15px; font-size: 1.4em; color: #fff; }
.stat-number { font-size: 2em; font-weight: 800; background: var(--gradient); -webkit-background-clip: text; -webkit-text-fill-color: transparent; line-height: 1.2; }
.stat-text { font-size: 0.8em; color: var(--text-muted); text-transform: uppercase; letter-spacing: 1px; font-weight: 700; margin-top: 4px; }
.avatar-wrap { width: 80px; height: 80px; border-radius: 50%; background: var(--gradient); display: flex; align-items: center; justify-content: center; font-size: 2em; font-weight: 800; color: #fff; margin: 0 auto 15px; overflow: hidden; border: 3px solid var(--glass-border); }
.avatar-wrap img { width: 100%; height: 100%; object-fit: cover; }
.admin-layout { display: grid; grid-template-columns: 250px 1fr 300px; gap: 20px; max-width: 1400px; margin: 0 auto; padding: 20px; align-items: start; }
@media (max-width: 1000px) { .admin-layout { display: flex; flex-direction: column; padding: 15px; gap: 15px; } .admin-sidebar, .admin-right-panel { position: static; width: 100%; } .admin-sidebar { display: flex; flex-wrap: wrap; gap: 8px; padding: 10px; justify-content: center; } .admin-sidebar h3 { width: 100%; text-align: center; margin-bottom: 10px; } .admin-nav-item { margin-bottom: 0; padding: 10px 15px; font-size: 0.85em; flex: 1 1 auto; justify-content: center; border: 1px solid var(--glass-border); } .admin-nav-item span { margin-left: 5px !important; } }
.admin-sidebar { background: var(--card); border: 1px solid var(--glass-border); border-radius: 20px; padding: 15px; position: sticky; top: 90px; }
.admin-nav-item { display: flex; align-items: center; gap: 12px; padding: 12px 15px; border-radius: 12px; color: var(--text-muted); font-weight: 600; cursor: pointer; transition: all 0.2s; margin-bottom: 5px; }
.admin-nav-item:hover, .admin-nav-item.active { background: rgba(99,102,241,0.15); color: var(--primary); }
.admin-right-panel { background: var(--card); border: 1px solid var(--glass-border); border-radius: 20px; padding: 20px; position: sticky; top: 90px; }
@media (max-width: 600px) { .hero-title { font-size: 2em; } .stats-section { grid-template-columns: 1fr; } .container { padding: 15px; } .card { padding: 18px; } }

/* SPLIT LOGIN UI */
.auth-container { display: grid; grid-template-columns: 1fr 1fr; max-width: 900px; margin: 40px auto; background: var(--card); backdrop-filter: blur(20px); border: 1px solid var(--glass-border); border-radius: 24px; overflow: hidden; box-shadow: 0 20px 50px rgba(0,0,0,0.5); }
.auth-left { padding: 40px; }
.auth-right { background: linear-gradient(135deg, rgba(99,102,241,0.2), rgba(236,72,153,0.1)); padding: 40px; display: flex; flex-direction: column; justify-content: center; border-left: 1px solid var(--glass-border); }
@media (max-width: 768px) { .auth-container { grid-template-columns: 1fr; } .auth-right { display: none; } }

/* SLIDER */
input[type=range] { -webkit-appearance: none; width: 100%; background: transparent; }
input[type=range]::-webkit-slider-thumb { -webkit-appearance: none; height: 20px; width: 20px; border-radius: 50%; background: var(--primary); cursor: pointer; margin-top: -8px; box-shadow: 0 0 10px var(--primary-glow); }
input[type=range]::-webkit-slider-runnable-track { width: 100%; height: 5px; cursor: pointer; background: var(--glass-border); border-radius: 5px; }

/* MARQUEE LOG WD */
.marquee-container { overflow: hidden; white-space: nowrap; background: rgba(0,0,0,0.3); border: 1px solid var(--glass-border); border-radius: 50px; padding: 10px 20px; margin: 20px auto; max-width: 800px; }
.marquee-content { display: inline-block; animation: marquee 20s linear infinite; }
.marquee-content span { margin-right: 30px; font-size: 0.85em; font-weight: 600; color: var(--text-muted); }
.marquee-content span b { color: var(--success); }
@keyframes marquee { 0% { transform: translateX(100%); } 100% { transform: translateX(-100%); } }
CSSEOF
echo -e "${GREEN}  ✅ CSS OK${NC}\n"

# ============================================
# 5. HEADER & FOOTER
# ============================================
echo -e "${CYAN}[5/7] Bikin Header & Footer...${NC}"

cat > "$WEB_ROOT/includes/header.php" << 'HTMLEOF'
<!DOCTYPE html>
<html lang="id" data-theme="dark">
<head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width, initial-scale=1.0">
<title><?= $pageTitle ?? 'Home' ?> — <?= SITE_NAME ?></title>
<link href="https://fonts.googleapis.com/css2?family=Plus+Jakarta+Sans:wght@400;500;600;700;800&display=swap" rel="stylesheet">
<link rel="stylesheet" href="https://cdnjs.cloudflare.com/ajax/libs/font-awesome/6.5.1/css/all.min.css">
<link rel="stylesheet" href="/assets/css/style.css">
<script>document.documentElement.setAttribute('data-theme', localStorage.getItem('theme') || 'dark');</script>
</head>
<body>
<div class="top-nav">
    <a href="/" class="brand"><i class="fas fa-bolt"></i> RendzzPanel</a>
    <div class="nav-actions">
        <?php if (isLoggedIn()): ?>
            <?php $notifCount = isAdmin() ? $pdo->query("SELECT COUNT(*) FROM password_requests WHERE status='pending'")->fetchColumn() + $pdo->query("SELECT COUNT(*) FROM verify_requests WHERE status='pending'")->fetchColumn() + $pdo->query("SELECT COUNT(*) FROM withdrawals WHERE status='pending'")->fetchColumn() : 0; ?>
            <a href="<?= isAdmin() ? '/admin/' : '/chat.php' ?>" class="nav-btn" title="Notifikasi"><i class="fas fa-envelope"></i><?php if ($notifCount > 0): ?><span class="badge-notif"><?= $notifCount ?></span><?php endif; ?></a>
        <?php endif; ?>
        <button class="nav-btn" onclick="toggleSidebar()"><i class="fas fa-bars"></i></button>
        <button class="nav-btn" onclick="toggleTheme()"><i class="fas fa-moon" id="themeIcon"></i></button>
    </div>
</div>
<div class="sidebar-overlay" id="sidebarOverlay" onclick="toggleSidebar()"></div>
<div class="sidebar" id="sidebar">
    <div class="sidebar-header"><div class="sidebar-title"><i class="fas fa-bolt"></i> RENDZZ PANEL</div><button class="nav-btn" onclick="toggleSidebar()" style="width:35px;height:35px"><i class="fas fa-times"></i></button></div>
    <nav class="sidebar-nav">
        <?php if (isLoggedIn()): ?>
            <div class="sidebar-label">Menu Utama</div>
            <a href="/dashboard.php" class="sidebar-link"><i class="fas fa-home"></i> Dashboard</a>
            <a href="/gacha.php" class="sidebar-link"><i class="fas fa-dice"></i> Gacha Saldo</a>
            <a href="/withdraw.php" class="sidebar-link"><i class="fas fa-wallet"></i> Saldo & Withdraw</a>
            <a href="/tools/" class="sidebar-link"><i class="fas fa-tachometer-alt"></i> Speedtest</a>
            <a href="/chat.php" class="sidebar-link"><i class="fas fa-comments"></i> Global Chat</a>
            <a href="/profile.php" class="sidebar-link"><i class="fas fa-user"></i> Profile Saya</a>
            <?php if (isAdmin()): ?>
                <div class="sidebar-label">Admin Panel</div>
                <a href="/admin/" class="sidebar-link"><i class="fas fa-shield-halved" style="color:var(--warning)"></i> X-Admin</a>
            <?php endif; ?>
            <div class="sidebar-label">Lainnya</div>
            <a href="/logout.php" class="sidebar-link" style="color:var(--danger)"><i class="fas fa-sign-out-alt"></i> Logout</a>
        <?php else: ?>
            <div class="sidebar-label">Menu</div>
            <a href="/" class="sidebar-link"><i class="fas fa-home"></i> Home</a>
            <a href="/login.php" class="sidebar-link"><i class="fas fa-sign-in-alt"></i> Login</a>
            <a href="/register.php" class="sidebar-link"><i class="fas fa-user-plus"></i> Daftar</a>
        <?php endif; ?>
    </nav>
</div>
<script>
function toggleSidebar() { document.getElementById('sidebar').classList.toggle('open'); document.getElementById('sidebarOverlay').classList.toggle('active'); }
function toggleTheme() { const current = document.documentElement.getAttribute('data-theme'); let next = 'dark'; if (current === 'dark') next = 'light'; else if (current === 'light') next = 'amoled'; else next = 'dark'; document.documentElement.setAttribute('data-theme', next); localStorage.setItem('theme', next); updateIcon(); }
function updateIcon() { const theme = document.documentElement.getAttribute('data-theme'); const icon = document.getElementById('themeIcon'); if (icon) { if (theme === 'dark') icon.className = 'fas fa-moon'; else if (theme === 'light') icon.className = 'fas fa-sun'; else icon.className = 'fas fa-circle'; } }
updateIcon();
</script>
HTMLEOF

cat > "$WEB_ROOT/includes/footer.php" << 'HTMLEOF'
<?php if (isLoggedIn()): ?>
<div class="bottom-nav">
    <a href="/dashboard.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'dashboard.php' ? 'active' : '' ?>"><i class="fas fa-home"></i><span>Home</span></a>
    <a href="/gacha.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'gacha.php' ? 'active' : '' ?>"><i class="fas fa-dice"></i><span>Gacha</span></a>
    <a href="/chat.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'chat.php' ? 'active' : '' ?>"><i class="fas fa-comments"></i><span>Chat</span></a>
    <?php if (isAdmin()): ?><a href="/admin/" class="nav-item <?= strpos($_SERVER['PHP_SELF'], '/admin/') !== false ? 'active' : '' ?>"><i class="fas fa-crown" style="color:var(--warning)"></i><span>Admin</span></a><?php endif; ?>
    <a href="/profile.php" class="nav-item <?= basename($_SERVER['PHP_SELF']) == 'profile.php' ? 'active' : '' ?>"><i class="fas fa-user"></i><span>Profile</span></a>
</div>
<?php endif; ?>
<div class="copyright">&copy; <?= date('Y') ?> By <span>Rendzz Official</span></div>
</body></html>
HTMLEOF
echo -e "${GREEN}  ✅ Header & Footer OK${NC}\n"

# ============================================
# 6. SEMUA HALAMAN WEB
# ============================================
echo -e "${CYAN}[6/7] Bikin Halaman Web & API...${NC}"

# --- INDEX (LIVE STATS, RATING, LOG WD) ---
cat > "$WEB_ROOT/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
$pageTitle = 'Home';
try {
    $totalUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
    $totalServers = $pdo->query("SELECT COUNT(*) FROM servers")->fetchColumn();
    $ramTotal = $pdo->query("SELECT SUM(ram) FROM servers")->fetchColumn() ?: 0;
    $ramTotalGB = round($ramTotal / 1024, 1);
} catch (Exception $e) { $totalUsers = 0; $totalServers = 0; $ramTotalGB = 0; }
$displayUsers = $totalUsers + 3400; $displayServers = $totalServers + 8500; $displayRam = $ramTotalGB + 12000;
include __DIR__ . '/includes/header.php';
?>
<section class="hero-section">
    <div style="display:inline-block; background:rgba(99,102,241,0.1); border:1px solid var(--primary); padding:5px 15px; border-radius:20px; font-size:0.8em; font-weight:700; color:var(--primary); margin-bottom:20px;"><i class="fas fa-star"></i> Platform Hosting No. 1</div>
    <h1 class="hero-title">Bangun Infrastruktur Digitalmu <span class="gradient-text">Tanpa Batas</span></h1>
    <p class="hero-subtitle">Deploy server Minecraft, Node.js, Bot WhatsApp, atau API dalam hitungan detik.</p>
    <div style="display:flex; gap:12px; justify-content:center; flex-wrap:wrap;">
        <a href="/register.php" class="btn btn-primary btn-large" style="padding:16px 40px;"><i class="fas fa-rocket"></i> Mulai Gratis</a>
        <a href="/login.php" class="btn btn-large" style="background:var(--card); color:var(--text); border:1px solid var(--glass-border); padding:16px 40px;"><i class="fas fa-sign-in-alt"></i> Masuk Dashboard</a>
    </div>
</section>
<div class="stats-section">
    <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#6366f1,#8b5cf6)"><i class="fas fa-users"></i></div><div class="stat-number" id="liveUsers" data-count="<?= $displayUsers ?>">0</div><div class="stat-text">User Aktif</div></div>
    <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#10b981,#059669)"><i class="fas fa-server"></i></div><div class="stat-number" id="liveServers" data-count="<?= $displayServers ?>">0</div><div class="stat-text">Server Dibuat</div></div>
    <div class="stat-card"><div class="stat-icon" style="background:linear-gradient(135deg,#f59e0b,#d97706)"><i class="fas fa-memory"></i></div><div class="stat-number" id="liveRam" data-count="<?= $displayRam ?>" data-suffix=" GB">0</div><div class="stat-text">RAM Tersedia</div></div>
</div>

<!-- LOG WD MARQUEE -->
<div class="marquee-container">
    <div class="marquee-content">
        <?php
        $names = ['08******3', '08******7', '08******1', '08******9', '08******5', '08******2'];
        for($i=0; $i<6; $i++) {
            $amt = rand(10, 600) * 1000;
            echo '<span><i class="fas fa-check-circle" style="color:var(--success);"></i> WD Berhasil: '.$names[$i].' - Rp '.number_format($amt,0,',','.').'</span>';
        }
        ?>
    </div>
</div>

<div style="text-align:center; margin-top:20px; margin-bottom:60px;">
    <div style="display:inline-block; background:var(--card); border:1px solid var(--glass-border); padding:10px 25px; border-radius:30px; font-size:0.9em; font-weight:700; color:var(--text-muted);"><i class="fas fa-signal" style="color:var(--success);"></i> Ping Panel: <span id="pingDisplay" style="color:var(--success); font-weight:800;">1-40 ms</span></div>
</div>

<section class="section" style="max-width:800px; margin:0 auto 40px; padding:0 20px;">
    <h2 class="section-title">Apa Kata Mereka?</h2>
    <div class="card" style="margin-bottom:20px;">
        <?php if(isLoggedIn()): 
            $cekRev = $pdo->prepare("SELECT id FROM reviews WHERE user_id=?"); $cekRev->execute([$_SESSION['user_id']]);
            if($cekRev->fetch()): ?>
                <div style="text-align:center; color:var(--success); padding:10px;"><i class="fas fa-check-circle"></i> Kamu sudah memberikan rating. Terima kasih!</div>
            <?php else: ?>
                <h3 style="margin-bottom:15px; font-size:1.1em;"><i class="fas fa-star" style="color:#f59e0b"></i> Beri Rating Web Ini</h3>
                <form method="POST" action="/api/review.php" style="display:flex; flex-direction:column; gap:10px;">
                    <div style="display:flex; gap:5px; font-size:1.5em; color:#f59e0b; cursor:pointer;" id="starRating"><i class="far fa-star" data-val="1"></i><i class="far fa-star" data-val="2"></i><i class="far fa-star" data-val="3"></i><i class="far fa-star" data-val="4"></i><i class="far fa-star" data-val="5"></i></div>
                    <input type="hidden" name="rating" id="ratingVal" value="0" required>
                    <textarea name="comment" placeholder="Tulis ulasan kamu (opsional)..." rows="2" style="padding:10px; border-radius:10px; background:var(--bg); border:1px solid var(--glass-border); color:var(--text);"></textarea>
                    <button type="submit" class="btn btn-primary btn-sm" style="width:max-content;">Kirim Rating</button>
                </form>
            <?php endif; ?>
        <?php else: ?>
            <div style="text-align:center; padding:10px; color:var(--text-muted);">Login dulu untuk memberi rating.</div>
        <?php endif; ?>
    </div>
    <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(250px, 1fr)); gap:15px;">
        <?php $revs = $pdo->query("SELECT r.*, u.username FROM reviews r JOIN users u ON r.user_id=u.id ORDER BY r.id DESC LIMIT 6")->fetchAll(); if(empty($revs)) echo '<div style="text-align:center; color:var(--text-muted); grid-column:1/-1;">Belum ada ulasan.</div>'; foreach($revs as $rv): 
            $name = $rv['username'];
            $censored = substr($name, 0, 1) . str_repeat('*', strlen($name) - 2) . substr($name, -1);
        ?>
            <div class="card" style="margin:0; padding:20px; background:rgba(0,0,0,0.2);"><div style="color:#f59e0b; margin-bottom:8px;"><?php for($i=1; $i<=5; $i++) echo $i <= $rv['rating'] ? '<i class="fas fa-star"></i>' : '<i class="far fa-star"></i>'; ?></div><p style="font-size:0.9em; font-style:italic; margin-bottom:10px;">"<?= htmlspecialchars($rv['comment'] ?? 'Mantap!') ?>"</p><div style="font-size:0.8em; font-weight:700;">@<?= htmlspecialchars($censored) ?></div></div>
        <?php endforeach; ?>
    </div>
</section>

<div class="cta-final"><h2>Siap Bergabung?</h2><p>Ambil kendali penuh atas servermu hari ini.</p><div style="display:flex; gap:12px; justify-content:center; flex-wrap:wrap;"><a href="/register.php" class="btn btn-primary btn-large"><i class="fas fa-user-plus"></i> Buat Akun</a><a href="/login.php" class="btn btn-large" style="background:rgba(255,255,255,0.1); color:var(--text); border:1px solid var(--glass-border)"><i class="fas fa-sign-in-alt"></i> Login</a></div></div>
<script>
function formatNumber(num) { if (num >= 1000000) return (num / 1000000).toFixed(1).replace('.0', '') + ' M'; if (num >= 10000) return (num / 1000).toFixed(1).replace('.0', '') + ' Rb'; return num.toLocaleString('id-ID'); }
function animateValue(obj, start, end, duration, suffix = '') { let startTimestamp = null; const step = (timestamp) => { if (!startTimestamp) startTimestamp = timestamp; const progress = Math.min((timestamp - startTimestamp) / duration, 1); let currentVal = Math.floor(progress * (end - start) + start); obj.innerHTML = formatNumber(currentVal) + suffix; if (progress < 1) { window.requestAnimationFrame(step); } }; window.requestAnimationFrame(step); }
const elUsers = document.getElementById('liveUsers'); const elServers = document.getElementById('liveServers'); const elRam = document.getElementById('liveRam');
let curUsers = parseInt(elUsers.dataset.count); let curServers = parseInt(elServers.dataset.count); let curRam = parseInt(elRam.dataset.count);
animateValue(elUsers, 0, curUsers, 2000); animateValue(elServers, 0, curServers, 2000); animateValue(elRam, 0, curRam, 2000, ' GB');
setInterval(() => { curUsers += Math.floor(Math.random() * 10) + 1; curServers += Math.floor(Math.random() * 5) + 1; curRam += Math.floor(Math.random() * 15) + 1; elUsers.innerHTML = formatNumber(curUsers); elServers.innerHTML = formatNumber(curServers); elRam.innerHTML = formatNumber(curRam) + ' GB'; }, 60000);
setInterval(() => { document.getElementById('pingDisplay').innerText = (Math.floor(Math.random() * 40) + 1) + ' ms'; }, 3000);
const stars = document.querySelectorAll('#starRating i'); const ratingInput = document.getElementById('ratingVal');
if(stars.length > 0) { stars.forEach(star => { star.addEventListener('click', () => { const val = star.getAttribute('data-val'); ratingInput.value = val; stars.forEach(s => { s.className = s.getAttribute('data-val') <= val ? 'fas fa-star' : 'far fa-star'; }); }); }); }
</script>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# --- API REVIEW ---
cat > "$WEB_ROOT/api/review.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
if (!isLoggedIn() || $_SERVER['REQUEST_METHOD'] !== 'POST') { header('Location: /'); exit; }
$rating = (int)$_POST['rating']; $comment = trim($_POST['comment']);
if ($rating >= 1 && $rating <= 5) { $cek = $pdo->prepare("SELECT id FROM reviews WHERE user_id=?"); $cek->execute([$_SESSION['user_id']]); if (!$cek->fetch()) { $pdo->prepare("INSERT INTO reviews (user_id, rating, comment) VALUES (?,?,?)")->execute([$_SESSION['user_id'], $rating, $comment]); } }
header('Location: /'); exit;
PHPEOF

# --- LOGIN & REGISTER (SPLIT UI) ---
cat > "$WEB_ROOT/login.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /dashboard.php'); exit; }
$err = ''; $msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['forgot'])) { $u = trim($_POST['username']); $s = $pdo->prepare("SELECT id FROM users WHERE username=?"); $s->execute([$u]); if ($s->fetch()) { $pdo->prepare("INSERT INTO password_requests (user_id, status) VALUES (?, 'pending')")->execute([$s->fetch()['id']]); $msg = 'Request terkirim!'; } else { $err = 'Username tidak ditemukan.'; } }
    else { $u = trim($_POST['username']); $p = $_POST['password']; $s = $pdo->prepare("SELECT * FROM users WHERE username=?"); $s->execute([$u]); $user = $s->fetch(); if ($user && password_verify($p, $user['password'])) { if ($user['status'] === 'banned') { $err = 'Akun dibanned!'; } else { $_SESSION['user_id'] = $user['id']; $_SESSION['username'] = $user['username']; $_SESSION['role'] = $user['role']; setcookie('rendzz_remember', $user['id'].':'.$user['password'], time() + (86400 * 30), '/', '', false, true); header('Location: /dashboard.php'); exit; } } else { $err = 'Username/Password salah!'; } }
}
$pageTitle = 'Login'; include __DIR__ . '/includes/header.php';
?>
<div class="auth-container">
    <div class="auth-left">
        <h2 class="auth-title">Selamat Datang</h2>
        <p class="auth-sub">Masuk ke dashboard panel kamu.</p>
        <?php if ($err): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $err ?></div><?php endif; ?>
        <?php if ($msg): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
        <form method="POST">
            <div class="form-group"><label>Username</label><input type="text" name="username" placeholder="Masukkan username" required autofocus></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" placeholder="Masukkan password" required></div>
            <button class="btn btn-primary btn-block"><i class="fas fa-sign-in-alt"></i> Masuk</button>
        </form>
        <div style="margin-top:15px; display:flex; justify-content:space-between; font-size:0.85em;">
            <a href="#" onclick="document.getElementById('forgotForm').style.display='block'; return false;" style="color:var(--warning); font-weight:700;">Lupa Password?</a>
            <a href="/register.php" style="color:var(--primary); font-weight:700;">Daftar</a>
        </div>
        <div id="forgotForm" style="display:none; margin-top:15px; padding-top:15px; border-top:1px dashed var(--glass-border);">
            <form method="POST"><input type="hidden" name="forgot" value="1"><div class="form-group"><label>Username</label><input type="text" name="username" required></div><button class="btn btn-warning btn-block"><i class="fas fa-paper-plane"></i> Request Reset</button></form>
        </div>
    </div>
    <div class="auth-right">
        <h2 style="font-size:2em; margin-bottom:10px; color:#fff;">Rendzz Panel</h2>
        <p style="color:rgba(255,255,255,0.7); font-size:0.9em; line-height:1.6;">Platform hosting terbaik untuk developer. Deploy server, bot, dan API dengan mudah.</p>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/register.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
if (isLoggedIn()) { header('Location: /dashboard.php'); exit; }
$err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $u = trim($_POST['username']); $e = trim($_POST['email']); $p = $_POST['password']; $cp = $_POST['confirm_password'];
    if (!isset($_POST['tos'])) { $err = 'Kamu harus setuju dengan TOS!'; }
    elseif (strlen($p) < 6) { $err = 'Password minimal 6 karakter'; }
    elseif ($p !== $cp) { $err = 'Konfirmasi password tidak cocok!'; }
    else {
        $s = $pdo->prepare("SELECT id FROM users WHERE username=? OR email=?"); $s->execute([$u, $e]);
        if ($s->fetch()) { $err = 'Username/Email sudah dipakai!'; }
        else { $refCode = trim($_POST['ref'] ?? ''); $refId = null; if ($refCode) { $r = $pdo->prepare("SELECT id FROM users WHERE username=?"); $r->execute([$refCode]); $rf = $r->fetch(); if($rf) $refId = $rf['id']; } $pdo->prepare("INSERT INTO users (username, email, password, referred_by) VALUES (?,?,?,?)")->execute([$u, $e, password_hash($p, PASSWORD_BCRYPT), $refId]); if ($refId) { $pdo->prepare("UPDATE users SET referral_count = referral_count + 1, balance = balance + 150 WHERE id=?")->execute([$refId]); } header('Location: /login.php'); exit; }
    }
}
$pageTitle = 'Daftar'; include __DIR__ . '/includes/header.php';
?>
<div class="auth-container">
    <div class="auth-left">
        <h2 class="auth-title">Buat Akun</h2>
        <p class="auth-sub">Daftar gratis dan mulai deploy server.</p>
        <?php if ($err): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $err ?></div><?php endif; ?>
        <form method="POST">
            <div class="form-group"><label>Username</label><input type="text" name="username" required></div>
            <div class="form-group"><label>Email</label><input type="email" name="email" required></div>
            <div class="form-group"><label>Password</label><input type="password" name="password" required></div>
            <div class="form-group"><label>Konfirmasi Password</label><input type="password" name="confirm_password" required></div>
            <div class="form-group"><label>Kode Referral (Opsional)</label><input type="text" name="ref" value="<?= htmlspecialchars($_GET['ref'] ?? '') ?>"></div>
            <div style="display:flex; gap:10px; align-items:flex-start; margin-bottom:15px;">
                <input type="checkbox" name="tos" id="tos" required style="width:auto; margin-top:4px;">
                <label for="tos" style="font-size:0.8em; color:var(--text-muted); text-transform:none; letter-spacing:0;">Saya setuju dengan Syarat & Ketentuan serta Kebijakan Privasi Rendzz Panel.</label>
            </div>
            <button class="btn btn-primary btn-block"><i class="fas fa-rocket"></i> Daftar</button>
        </form>
        <p style="margin-top:20px; font-size:0.9em; color:var(--text-muted);">Sudah punya akun? <a href="/login.php" style="color:var(--primary); font-weight:700;">Login</a></p>
    </div>
    <div class="auth-right">
        <h2 style="font-size:2em; margin-bottom:10px; color:#fff;">Gabung Sekarang!</h2>
        <p style="color:rgba(255,255,255,0.7); font-size:0.9em; line-height:1.6;">Dapatkan akses ke server berkualitas tinggi. Daftar gratis, tanpa kartu kredit.</p>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/logout.php" << 'PHPEOF'
<?php session_start(); session_destroy(); setcookie('rendzz_remember', '', time() - 3600, '/'); header('Location: /login.php'); exit;
PHPEOF

# --- DASHBOARD (REFERRAL & AUTO CHECK) ---
cat > "$WEB_ROOT/dashboard.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$s = $pdo->prepare("SELECT * FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch();
$ann = $pdo->query("SELECT * FROM announcements ORDER BY id DESC LIMIT 1")->fetch();
$msg = ''; $err = '';
$totalMyServers = $pdo->prepare("SELECT COUNT(*) FROM servers WHERE user_id=?"); $totalMyServers->execute([$uid]); $myServerCount = $totalMyServers->fetchColumn();
$servers = $pdo->prepare("SELECT * FROM servers WHERE user_id=? ORDER BY id DESC"); $servers->execute([$uid]); $servers = $servers->fetchAll();
$req = $pdo->prepare("SELECT * FROM password_requests WHERE user_id=? AND status='approved' ORDER BY id DESC LIMIT 1"); $req->execute([$uid]); $reqData = $req->fetch();
$pteroDomain = rtrim(getSetting($pdo, 'ptero_domain'), '/'); $ptla = getSetting($pdo, 'ptla'); $ptlc = getSetting($pdo, 'ptlc');
$isCreateOn = getSetting($pdo, 'ptero_create_status', 'on') === 'on';

if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['power_action']) && !empty($ptlc)) {
    $srvId = (int)$_POST['srv_id']; $action = $_POST['power_action'];
    $check = $pdo->prepare("SELECT ptero_id FROM servers WHERE id=? AND user_id=?"); $check->execute([$srvId, $uid]); $srvData = $check->fetch();
    if ($srvData) { $ch = curl_init("$pteroDomain/api/client/servers/{$srvData['ptero_id']}/power"); curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => ["Accept: application/json", "Content-Type: application/json", "Authorization: Bearer $ptlc"], CURLOPT_POSTFIELDS => json_encode(["signal" => $action])]); curl_exec($ch); curl_close($ch); $msg = "Sinyal <b>".strtoupper($action)."</b> dikirim!"; }
}
if ($_SERVER['REQUEST_METHOD'] === 'POST' && isset($_POST['create']) && $isCreateOn) {
    $serverName = trim($_POST['server_name']); $ram = (int)$_POST['ram'];
    if (!$serverName || !isset($_POST['ram'])) { $err = 'Isi semua data!'; }
    else {
        $loc = getSetting($pdo, 'location_id'); $egg = getSetting($pdo, 'egg_id');
        $email = $me['username'] . rand(10,99) . "@rendzz.com"; $password = "Pass" . rand(1000,9999) . "!";
        $headers = ["Accept: application/json", "Content-Type: application/json", "Authorization: Bearer $ptla"];
        $pteroRam = ($ram == 0) ? -1 : $ram; $pteroDisk = ($ram == 0) ? -1 : $ram * 2; $pteroCpu = ($ram == 0) ? -1 : 100;
        $limits = ["memory" => $pteroRam, "swap" => 0, "disk" => $pteroDisk, "io" => 500, "cpu" => $pteroCpu];
        $ch = curl_init("$pteroDomain/api/application/users"); curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_POSTFIELDS => json_encode(["email" => $email, "username" => $me['username'] . rand(100,999), "first_name" => $me['username'], "last_name" => "User", "password" => $password])]);
        $res = json_decode(curl_exec($ch), true); curl_close($ch);
        if (isset($res['errors'])) { $err = 'Gagal: ' . $res['errors'][0]['detail']; }
        else {
            $pteroUserId = $res['attributes']['id']; $startup = 'if [[ -d .git ]] && [[ {{AUTO_UPDATE}} == "1" ]]; then git pull; fi; /usr/local/bin/${CMD_RUN}';
            $ch = curl_init("$pteroDomain/api/application/servers"); curl_setopt_array($ch, [CURLOPT_POST => true, CURLOPT_RETURNTRANSFER => true, CURLOPT_HTTPHEADER => $headers, CURLOPT_POSTFIELDS => json_encode(["name" => $serverName, "description" => "Rendzz", "user" => $pteroUserId, "egg" => (int)$egg, "docker_image" => "ghcr.io/parkervcp/yolks:nodejs_20", "startup" => $startup, "environment" => ["INST" => "npm", "USER_UPLOAD" => "0", "AUTO_UPDATE" => "0", "CMD_RUN" => "npm start"], "limits" => $limits, "feature_limits" => ["databases" => 5, "backups" => 5, "allocations" => 1], "deploy" => ["locations" => [(int)$loc], "dedicated_ip" => false, "port_range" => []]])]);
            $res2 = json_decode(curl_exec($ch), true); curl_close($ch);
            if (isset($res2['errors'])) { $err = 'Gagal: ' . $res2['errors'][0]['detail']; }
            else { $pteroServerId = $res2['attributes']['id']; $pdo->prepare("INSERT INTO servers (user_id, server_name, ptero_id, ram, email, password) VALUES (?,?,?,?,?,?)")->execute([$uid, $serverName, $pteroServerId, $ram, $email, $password]); $msg = "Server <b>$serverName</b> berhasil dibuat!"; }
        }
    }
}
$isPteroReady = checkPteroStatus($pdo);
if (!$isPteroReady) { $isCreateOn = false; }
$pageTitle = 'Dashboard'; include __DIR__ . '/includes/header.php';
?>
<div id="loadingOverlay" style="display:none; position:fixed; inset:0; background:rgba(0,0,0,0.9); z-index:99999; justify-content:center; align-items:center; flex-direction:column; backdrop-filter:blur(10px);"><div style="width:80px; height:80px; border:5px solid rgba(255,255,255,0.1); border-top:5px solid var(--primary); border-radius:50%; animation:spin 1s linear infinite;"></div><h2 id="loadingText" style="margin-top:20px; color:#fff; font-size:1.2em;">Mendeploy...</h2></div>
<style>@keyframes spin { 0% { transform: rotate(0deg); } 100% { transform: rotate(360deg); } }</style>
<div class="container">
    <?php if ($reqData): ?><div class="alert alert-success" id="passNotif" style="position:relative;"><i class="fas fa-key"></i> Password baru: <b><?= htmlspecialchars($reqData['new_password']) ?></b><button onclick="document.getElementById('passNotif').style.display='none';" style="position:absolute; right:10px; top:10px; background:none; border:none; color:inherit; cursor:pointer;"><i class="fas fa-times"></i></button></div><?php endif; ?>
    <?php if ($ann): ?><div style="background:rgba(245,158,11,0.15);border:1px solid var(--warning);color:var(--warning);padding:14px 18px;border-radius:14px;margin-bottom:20px;font-size:0.9em;font-weight:600;"><i class="fas fa-bullhorn"></i> <b>Info:</b> <?= htmlspecialchars($ann['message']) ?></div><?php endif; ?>
    <?php if ($msg): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
    <?php if ($err): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $err ?></div><?php endif; ?>
    <div class="card" style="background:linear-gradient(135deg, rgba(99,102,241,0.15), transparent);"><div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;"><div><h1 style="font-size:1.4em; margin-bottom:5px;">Halo, <?= htmlspecialchars($me['username']) ?>! <i class="fas fa-hand-wave"></i></h1><p style="color:var(--text-muted); font-size:0.9em;">Siap deploy server?</p></div><div style="text-align:right;"><div style="font-size:0.75em; color:var(--text-muted); font-weight:700; text-transform:uppercase;">Total Server</div><div style="font-size:1.5em; font-weight:800; color:var(--primary);"><?= $myServerCount ?></div></div><a href="/withdraw.php" style="text-decoration:none; display:block; text-align:right;"><div style="background:rgba(16,185,129,0.15); border:1px solid var(--success); padding:5px 10px; border-radius:10px;"><div style="font-size:0.65em; color:var(--success); font-weight:700;">SALDO ANDA</div><div style="font-size:1em; font-weight:800; color:var(--success);">Rp <?= number_format($me['balance'] ?? 0, 0, ',', '.') ?></div></div></a></div></div>
    <div class="card">
        <div style="display:flex; justify-content:space-between; align-items:center; margin-bottom:18px;"><h2 style="font-size:1.2em;"><i class="fas fa-rocket" style="color:var(--primary)"></i> Create Server</h2><?php if ($isCreateOn && $isPteroReady): ?><span style="background:rgba(16,185,129,0.15); color:var(--success); padding:5px 12px; border-radius:20px; font-size:0.8em; font-weight:700;"><i class="fas fa-circle" style="font-size:0.6em;"></i> Online</span><?php else: ?><span style="background:rgba(239,68,68,0.15); color:var(--danger); padding:5px 12px; border-radius:20px; font-size:0.8em; font-weight:700;"><i class="fas fa-circle" style="font-size:0.6em;"></i> Offline</span><?php endif; ?></div>
        <?php if (!$isCreateOn): ?><div class="alert alert-error"><i class="fas fa-lock"></i> Fitur Create dimatikan Admin / Panel Down.</div><?php endif; ?>
        <form method="POST" onsubmit="startLoading()"><input type="hidden" name="create" value="1"><div class="form-group"><label>Nama Server</label><input type="text" name="server_name" placeholder="Contoh: Bot WhatsApp" required <?= !$isCreateOn ? 'disabled' : '' ?>></div><div class="form-group"><label>RAM</label><select name="ram" required <?= !$isCreateOn ? 'disabled' : '' ?>><option value="1024">1 GB</option><option value="2048">2 GB</option><option value="4096">4 GB</option><option value="8192">8 GB</option><option value="0">👑 UNLIMITED</option></select></div><button type="submit" class="btn <?= ($isCreateOn && $isPteroReady) ? 'btn-primary' : 'btn-disabled' ?> btn-block" <?= ($isCreateOn && $isPteroReady) ? '' : 'disabled' ?>><i class="fas fa-bolt"></i> Deploy</button></form>
    </div>
    <div style="margin-top:40px;"></div>
    <h2 style="font-size:1.1em; margin-bottom:15px;"><i class="fas fa-server" style="color:var(--primary)"></i> Server Saya (<?= count($servers) ?>)</h2>
    <?php if (empty($servers)): ?><div class="card" style="text-align:center; padding:40px; color:var(--text-muted);"><i class="fas fa-server" style="font-size:2.5em; opacity:0.5; margin-bottom:12px;"></i><p>Belum ada server.</p></div>
    <?php else: foreach ($servers as $srv): ?>
        <div class="card" style="border-left: 4px solid var(--primary); margin-bottom:15px;">
            <div style="display:flex; justify-content:space-between; align-items:flex-start; margin-bottom:12px;"><div><div style="font-weight:800; font-size:1.05em;"><?= htmlspecialchars($srv['server_name']) ?></div><div style="font-size:0.8em; color:var(--text-muted); margin-top:2px;">ID #<?= $srv['ptero_id'] ?> • RAM: <?= $srv['ram']==0?'<span style="color:var(--warning); font-weight:bold;">UNLIMITED</span>':$srv['ram'].'MB' ?></div></div><span class="badge badge-active">Active</span></div>
            <div style="background:rgba(0,0,0,0.4); padding:12px; border-radius:10px; border:1px solid var(--glass-border); font-size:0.85em; margin-bottom:12px; position:relative;"><div style="color:var(--text-muted); margin-bottom:6px; font-size:0.75em; text-transform:uppercase; font-weight:700;">Kredensial</div><div style="display:flex; justify-content:space-between; margin-bottom:4px;"><span><i class="fas fa-envelope" style="width:16px;"></i> Email:</span> <b id="email_<?= $srv['id'] ?>"><?= htmlspecialchars($srv['email'] ?? '-') ?></b></div><div style="display:flex; justify-content:space-between;"><span><i class="fas fa-key" style="width:16px;"></i> Pass:</span> <b id="pass_<?= $srv['id'] ?>"><?= htmlspecialchars($srv['password'] ?? '-') ?></b></div><button onclick="copyCred('email_<?= $srv['id'] ?>', 'pass_<?= $srv['id'] ?>')" class="btn btn-sm btn-warning" style="position:absolute; right:10px; top:10px; padding:4px 8px;"><i class="fas fa-copy"></i></button></div>
            <div style="display:grid; grid-template-columns:1fr 1fr 1fr; gap:8px; margin-bottom:12px;"><form method="POST"><input type="hidden" name="srv_id" value="<?= $srv['id'] ?>"><input type="hidden" name="power_action" value="start"><button class="btn btn-sm btn-success btn-block" <?= empty($ptlc) ? 'disabled' : '' ?>><i class="fas fa-play"></i></button></form><form method="POST"><input type="hidden" name="srv_id" value="<?= $srv['id'] ?>"><input type="hidden" name="power_action" value="restart"><button class="btn btn-sm btn-warning btn-block" <?= empty($ptlc) ? 'disabled' : '' ?>><i class="fas fa-rotate"></i></button></form><form method="POST"><input type="hidden" name="srv_id" value="<?= $srv['id'] ?>"><input type="hidden" name="power_action" value="stop"><button class="btn btn-sm btn-danger btn-block" <?= empty($ptlc) ? 'disabled' : '' ?>><i class="fas fa-stop"></i></button></form></div>
            <a href="<?= htmlspecialchars($pteroDomain) ?>" target="_blank" class="btn btn-primary btn-block" style="font-size:0.9em; padding:12px;"><i class="fas fa-external-link-alt"></i> Buka Panel</a>
        </div>
    <?php endforeach; endif; ?>
</div>
<script>
function startLoading() { document.getElementById('loadingOverlay').style.display = 'flex'; const texts = ["Menghubungi...", "Membuat User...", "Alokasi...", "Selesai..."]; let i = 0; setInterval(() => { document.getElementById('loadingText').innerText = texts[i]; i = (i + 1) % texts.length; }, 1500); }
function copyCred(emailId, passId) { const email = document.getElementById(emailId).innerText; const pass = document.getElementById(passId).innerText; navigator.clipboard.writeText(`Email: ${email}\nPass: ${pass}`).then(() => { alert('Kredensial dicopy!'); }); }
</script>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# --- GACHA, WITHDRAW, TOOLS, CHAT, PROFILE ---
cat > "$WEB_ROOT/gacha.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$s = $pdo->prepare("SELECT balance FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch();
$msg = ''; $err = '';
$winRate = (int)getSetting($pdo, 'gacha_winrate', '50');

if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $bet = (int)$_POST['bet'];
    if ($bet < 100 || $bet > 6000) { $err = 'Minimal Rp 100, Maksimal Rp 6.000'; }
    elseif ($bet > $me['balance']) { $err = 'Saldo tidak cukup!'; }
    else {
        $pdo->prepare("UPDATE users SET balance = balance - ? WHERE id=?")->execute([$bet, $uid]);
        $roll = rand(1, 100);
        $isWin = ($roll <= $winRate);
        if ($isWin) {
            $winAmount = $bet * 2;
            $pdo->prepare("UPDATE users SET balance = balance + ? WHERE id=?")->execute([$winAmount, $uid]);
            $pdo->prepare("INSERT INTO gacha_logs (user_id, bet_amount, win_amount, status) VALUES (?,?,?, 'win')")->execute([$uid, $bet, $winAmount]);
            $msg = "🎉 <b>JACKPOT!</b> Kamu menang <b>Rp " . number_format($winAmount, 0, ',', '.') . "</b>";
        } else {
            $pdo->prepare("INSERT INTO gacha_logs (user_id, bet_amount, win_amount, status) VALUES (?,?,0, 'lose')")->execute([$uid, $bet]);
            $err = "😭 <b>ZONK!</b> Kamu kehilangan <b>Rp " . number_format($bet, 0, ',', '.') . "</b>. Coba lagi!";
        }
    }
}
$pageTitle = 'Gacha'; include __DIR__ . '/includes/header.php';
?>
<div class="container" style="max-width:500px;">
    <div class="card" style="text-align:center; background:linear-gradient(135deg, rgba(245,158,11,0.15), transparent);">
        <h3 style="color:var(--text-muted); font-size:0.9em;">Saldo Kamu</h3>
        <h1 style="font-size:2.5em; color:var(--success); font-weight:800;">Rp <?= number_format($me['balance'], 0, ',', '.') ?></h1>
    </div>
    <?php if ($msg): ?><div class="alert alert-success" style="font-size:1.1em; padding:20px;"><i class="fas fa-trophy"></i> <?= $msg ?></div><?php endif; ?>
    <?php if ($err): ?><div class="alert alert-error" style="font-size:1.1em; padding:20px;"><i class="fas fa-times-circle"></i> <?= $err ?></div><?php endif; ?>
    <div class="card" style="text-align:center;">
        <h3 style="margin-bottom:15px;"><i class="fas fa-dice" style="color:var(--primary)"></i> Gacha Saldo</h3>
        <p style="font-size:0.85em; color:var(--text-muted); margin-bottom:20px;">Tebak keberuntunganmu! Menang = 2x lipat saldo.</p>
        <form method="POST">
            <div class="form-group"><label>Nominal Taruhan (100 - 6.000)</label><input type="number" name="bet" min="100" max="6000" placeholder="Contoh: 1000" required></div>
            <button class="btn btn-primary btn-block btn-large"><i class="fas fa-play"></i> Mainkan!</button>
        </form>
    </div>
</div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/withdraw.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/includes/config.php';
requireLogin();
$uid = $_SESSION['user_id'];
$s = $pdo->prepare("SELECT balance FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch();
$msg = ''; $err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    $amount = (int)$_POST['amount']; $dana = trim($_POST['dana']);
    if ($amount < 10000) { $err = 'Minimal withdraw Rp 10.000'; }
    elseif ($amount > $me['balance']) { $err = 'Saldo tidak cukup!'; }
    elseif (empty($dana)) { $err = 'Nomor DANA wajib diisi!'; }
    else { 
        $pdo->prepare("INSERT INTO withdrawals (user_id, amount, dana_number) VALUES (?,?,?)")->execute([$uid, $amount, $dana]); 
        $pdo->prepare("UPDATE users SET balance = balance - ? WHERE id=?")->execute([$amount, $uid]); 
        $masked = substr($dana, 0, 2) . str_repeat('*', strlen($dana) - 5) . substr($dana, -3);
        $pdo->prepare("INSERT INTO wd_logs_public (masked_name, amount) VALUES (?,?)")->execute([$masked, $amount]);
        $msg = 'Request withdraw terkirim! Tunggu approve admin.'; 
    }
}
$pageTitle = 'Withdraw'; include __DIR__ . '/includes/header.php';
?>
<div class="container" style="max-width:500px;"><div class="card" style="text-align:center; background:linear-gradient(135deg, rgba(16,185,129,0.15), transparent);"><h3 style="color:var(--text-muted); font-size:0.9em;">Saldo Kamu</h3><h1 style="font-size:2.5em; color:var(--success); font-weight:800;">Rp <?= number_format($me['balance'], 0, ',', '.') ?></h1><p style="font-size:0.8em; color:var(--text-muted); margin-top:5px;">Dapatkan Rp 150 per teman yang daftar pakai kode kamu!</p></div>
<?php if ($msg): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?><?php if ($err): ?><div class="alert alert-error"><i class="fas fa-exclamation-circle"></i> <?= $err ?></div><?php endif; ?>
<div class="card"><h3 style="margin-bottom:15px;"><i class="fas fa-wallet"></i> Tarik Saldo (DANA)</h3><form method="POST"><div class="form-group"><label>Jumlah (Min 10.000)</label><input type="number" name="amount" min="10000" placeholder="10000" required></div><div class="form-group"><label>Nomor DANA</label><input type="text" name="dana" placeholder="08xxxxxxxxxx" required></div><button class="btn btn-primary btn-block"><i class="fas fa-paper-plane"></i> Request Withdraw</button></form></div>
<div class="card"><h3 style="margin-bottom:15px;"><i class="fas fa-link"></i> Kode Referral Kamu</h3><div style="display:flex; gap:10px;"><input type="text" value="<?= $_SERVER['HTTP_HOST'] ?>/register.php?ref=<?= strtoupper(substr(md5($_SESSION['username']), 0, 5)) ?>" readonly style="flex:1; padding:10px; border-radius:10px; border:1px solid var(--glass-border); background:var(--bg); color:var(--text); font-size:0.8em;"><button onclick="navigator.clipboard.writeText('<?= $_SERVER['HTTP_HOST'] ?>/register.php?ref=<?= strtoupper(substr(md5($_SESSION['username']), 0, 5)) ?>'); alert('Link dicopy!')" class="btn btn-primary btn-sm"><i class="fas fa-copy"></i></button></div></div></div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/tools/index.php" << 'PHPEOF'
<?php require_once __DIR__ . '/../includes/config.php'; requireLogin(); $pageTitle = 'Speedtest'; include __DIR__ . '/../includes/header.php'; ?>
<div class="container"><div class="card" style="text-align:center; padding:30px 10px; max-width:500px; margin:0 auto;"><h2>Speedtest Real</h2><iframe src="https://openspeedtest.com/speedtest" width="100%" height="450" frameborder="0" style="border-radius:15px; background:#fff; margin-top:20px;"></iframe></div></div>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/chat.php" << 'PHPEOF'
<?php require_once __DIR__ . '/includes/config.php'; requireLogin(); $pageTitle = 'Chat'; include __DIR__ . '/includes/header.php'; ?>
<div class="container" style="max-width:700px;"><div class="card" style="padding:0; height:75vh; display:flex; flex-direction:column;"><div style="padding:15px 20px; border-bottom:1px solid var(--glass-border); font-weight:700;">Global Chat</div><div id="chatBox" style="flex:1; overflow-y:auto; padding:20px; display:flex; flex-direction:column; gap:10px;"></div><div style="padding:15px; display:flex; gap:10px;"><input type="text" id="chatInput" placeholder="Ketik pesan..." style="flex:1; padding:12px; border-radius:12px; border:1px solid var(--glass-border); background:var(--bg); color:var(--text);"><button class="btn btn-primary" onclick="sendMsg()">Kirim</button></div></div></div>
<script>
const chatBox = document.getElementById('chatBox'), chatInput = document.getElementById('chatInput'); const myUser = "<?= htmlspecialchars($_SESSION['username']) ?>";
async function loadChat() { const res = await fetch('/api/chat.php'); const data = await res.json(); if (!data.ok) return; const isBottom = chatBox.scrollHeight - chatBox.scrollTop <= chatBox.clientHeight + 50; chatBox.innerHTML = data.chats.map(c => { const isMe = c.username === myUser; const isAdmin = c.is_admin == 1; const isVerified = c.is_verified == 1; let badge = ''; if (isAdmin) badge += ' <i class="fas fa-crown" style="color:#f59e0b;"></i>'; if (isVerified) badge += ' <i class="fas fa-circle-check" style="color:#3b82f6;"></i>'; const bg = isMe ? 'var(--gradient)' : 'var(--bg)'; const color = isMe ? '#fff' : 'var(--text)'; const align = isMe ? 'flex-end' : 'flex-start'; return `<div style="display:flex;flex-direction:column;align-items:${align};"><div style="font-size:0.75em;color:var(--text-muted);"><b>${c.username}</b>${badge}</div><div style="background:${bg};color:${color};padding:10px;border-radius:16px;max-width:80%;">${c.message}</div></div>`; }).join(''); if (isBottom) chatBox.scrollTop = chatBox.scrollHeight; }
async function sendMsg() { const msg = chatInput.value.trim(); if (!msg) return; chatInput.value = ''; await fetch('/api/chat.php', { method: 'POST', headers: {'Content-Type': 'application/json'}, body: JSON.stringify({ message: msg }) }); loadChat(); chatBox.scrollTop = chatBox.scrollHeight; }
chatInput.addEventListener('keypress', e => { if (e.key === 'Enter') sendMsg(); }); loadChat(); setInterval(loadChat, 2000);
</script>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

cat > "$WEB_ROOT/api/chat.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
header('Content-Type: application/json');
if (!isLoggedIn()) { echo json_encode(['ok'=>false]); exit; }
if ($_SERVER['REQUEST_METHOD'] === 'GET') { $s = $pdo->query("SELECT c.username, c.message, c.is_admin, u.is_verified FROM chats c LEFT JOIN users u ON c.user_id = u.id ORDER BY c.id ASC LIMIT 50"); echo json_encode(['ok'=>true,'chats'=>$s->fetchAll()]); exit; }
$input = json_decode(file_get_contents('php://input'), true); $msg = trim($input['message'] ?? '');
if ($msg) { $u = $pdo->prepare("SELECT username FROM users WHERE id=?"); $u->execute([$_SESSION['user_id']]); $user = $u->fetch(); $pdo->prepare("INSERT INTO chats (user_id, username, message, is_admin) VALUES (?,?,?,?)")->execute([$_SESSION['user_id'], $user['username'], $msg, isAdmin() ? 1 : 0]); echo json_encode(['ok'=>true]); } else { echo json_encode(['ok'=>false]); }
PHPEOF

cat > "$WEB_ROOT/profile.php" << 'PHPEOF'
<?php require_once __DIR__ . '/includes/config.php'; requireLogin(); $uid = $_SESSION['user_id']; $s = $pdo->prepare("SELECT * FROM users WHERE id=?"); $s->execute([$uid]); $me = $s->fetch(); $msg = ''; $err = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['update_avatar'])) { if (isset($_FILES['avatar']) && $_FILES['avatar']['error'] == 0) { $ext = pathinfo($_FILES['avatar']['name'], PATHINFO_EXTENSION); if (in_array(strtolower($ext), ['jpg', 'jpeg', 'png'])) { $filename = 'avatar_' . $uid . '_' . time() . '.' . $ext; if (move_uploaded_file($_FILES['avatar']['tmp_name'], __DIR__ . '/uploads/avatars/' . $filename)) { $pdo->prepare("UPDATE users SET avatar=? WHERE id=?")->execute([$filename, $uid]); $msg = 'Foto diupdate!'; header("Refresh:0"); exit; } } } }
    if (isset($_POST['change_pw'])) { if (password_verify($_POST['old_password'], $me['password'])) { if (strlen($_POST['new_password']) >= 6) { $pdo->prepare("UPDATE users SET password=? WHERE id=?")->execute([password_hash($_POST['new_password'], PASSWORD_BCRYPT), $uid]); $msg = 'PW diubah!'; } else { $err = 'Min 6 char.'; } } else { $err = 'PW lama salah.'; } }
    if (isset($_POST['req_verify'])) { $cek = $pdo->prepare("SELECT id FROM verify_requests WHERE user_id=? AND status='pending'"); $cek->execute([$uid]); if ($cek->fetch()) { $err = 'Sudah request.'; } else { $pdo->prepare("INSERT INTO verify_requests (user_id) VALUES (?)")->execute([$uid]); $msg = 'Request dikirim!'; } }
}
$pageTitle = 'Profile'; include __DIR__ . '/includes/header.php';
?>
<div class="container"><div class="card" style="text-align:center;"><div class="avatar-wrap"><?php if ($me['avatar'] && file_exists(__DIR__ . '/uploads/avatars/' . $me['avatar'])): ?><img src="/uploads/avatars/<?= $me['avatar'] ?>"><?php else: ?><?= strtoupper(substr($me['username'],0,1)) ?><?php endif; ?></div><h1 style="font-size:1.4em; display:flex; justify-content:center; gap:6px;">@<?= htmlspecialchars($me['username']) ?><?php if ($me['is_verified']): ?><i class="fas fa-circle-check" style="color:#3b82f6;"></i><?php endif; ?></h1><p style="color:var(--text-muted);"><?= htmlspecialchars($me['email']) ?></p></div>
<div class="card"><h3>Ganti Foto</h3><form method="POST" enctype="multipart/form-data"><input type="hidden" name="update_avatar" value="1"><input type="file" name="avatar" required style="margin:10px 0;"><button class="btn btn-primary btn-sm">Upload</button></form></div>
<div class="card"><h3>Ganti Password</h3><form method="POST"><input type="hidden" name="change_pw" value="1"><div class="form-group"><label>Lama</label><input type="password" name="old_password" required></div><div class="form-group"><label>Baru</label><input type="password" name="new_password" required></div><button class="btn btn-warning btn-sm">Simpan</button></form></div>
<div class="card" style="text-align:center;"><h3>Verified</h3><?php if (!$me['is_verified']): ?><form method="POST"><button name="req_verify" class="btn btn-primary btn-sm">Request Verified</button></form><?php else: ?><p style="color:var(--success);">Verified!</p><?php endif; ?></div>
<a href="/logout.php" class="btn btn-block" style="background:rgba(239,68,68,0.1); color:var(--danger); border:1px solid var(--danger);">Logout</a></div>
<?php include __DIR__ . '/includes/footer.php'; ?>
PHPEOF

# --- ADMIN PANEL (LENGKAP + GACHA SLIDER + BALANCE MANAGER) ---
cat > "$WEB_ROOT/admin/index.php" << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['save_api'])) { foreach (['ptero_domain', 'ptla', 'ptlc', 'location_id', 'egg_id', 'gacha_winrate'] as $k) if (isset($_POST[$k])) $pdo->prepare("UPDATE settings SET v=? WHERE k=?")->execute([trim($_POST[$k]), $k]); $msg = 'Disimpan.'; }
    if (isset($_POST['toggle_ptero'])) { $new = getSetting($pdo, 'ptero_create_status') == 'on' ? 'off' : 'on'; $pdo->prepare("UPDATE settings SET v=? WHERE k='ptero_create_status'")->execute([$new]); $msg = "Ptero: ".strtoupper($new); }
    if (isset($_POST['toggle_maintenance'])) { $new = getSetting($pdo, 'maintenance') == '1' ? '0' : '1'; $pdo->prepare("UPDATE settings SET v=? WHERE k='maintenance'")->execute([$new]); $msg = "Maint: ".($new=='1'?'ON':'OFF'); }
    if (isset($_POST['approve_verify']) && isset($_POST['req_id'])) { $reqId = (int)$_POST['req_id']; $req = $pdo->prepare("SELECT user_id FROM verify_requests WHERE id=?"); $req->execute([$reqId]); $u = $req->fetch(); $pdo->prepare("UPDATE users SET is_verified=1 WHERE id=?")->execute([$u['user_id']]); $pdo->prepare("UPDATE verify_requests SET status='approved' WHERE id=?")->execute([$reqId]); $msg = 'Verified!'; }
    if (isset($_POST['approve_reset']) && isset($_POST['req_id'])) { $reqId = (int)$_POST['req_id']; $newPass = "NewPass" . rand(1000,9999); $req = $pdo->prepare("SELECT user_id FROM password_requests WHERE id=?"); $req->execute([$reqId]); $u = $req->fetch(); $pdo->prepare("UPDATE users SET password=? WHERE id=?")->execute([password_hash($newPass, PASSWORD_BCRYPT), $u['user_id']]); $pdo->prepare("UPDATE password_requests SET status='approved', new_password=? WHERE id=?")->execute([$newPass, $reqId]); $msg = 'PW: ' . $newPass; }
    if (isset($_POST['toggle_ban']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $new = $_POST['current_status'] === 'active' ? 'banned' : 'active'; $pdo->prepare("UPDATE users SET status=? WHERE id=?")->execute([$new, $uid]); $msg = 'Status diubah.'; }
    if (isset($_POST['delete_user']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $pdo->prepare("DELETE FROM users WHERE id=? AND role='user'")->execute([$uid]); $pdo->prepare("DELETE FROM servers WHERE user_id=?")->execute([$uid]); $msg = 'User dihapus.'; }
    if (isset($_POST['suspend_srv'])) { $srvId = (int)$_POST['srv_id']; $reason = trim($_POST['reason']); $pdo->prepare("UPDATE servers SET status='suspended', abuse_reason=? WHERE id=?")->execute([$reason, $srvId]); $msg = 'Suspended!'; }
    if (isset($_POST['unsuspend_srv'])) { $srvId = (int)$_POST['srv_id']; $pdo->prepare("UPDATE servers SET status='active', abuse_reason=NULL WHERE id=?")->execute([$srvId]); $msg = 'Unsuspended!'; }
    if (isset($_POST['approve_wd'])) { $wdId = (int)$_POST['wd_id']; $pdo->prepare("UPDATE withdrawals SET status='approved' WHERE id=?")->execute([$wdId]); $msg = 'Withdraw approved!'; }
    if (isset($_POST['reject_wd'])) { $wdId = (int)$_POST['wd_id']; $uid = (int)$_POST['uid']; $amount = (int)$_POST['amount']; $pdo->prepare("UPDATE withdrawals SET status='rejected' WHERE id=?")->execute([$wdId]); $pdo->prepare("UPDATE users SET balance = balance + ? WHERE id=?")->execute([$amount, $uid]); $msg = 'Withdraw rejected (Saldo dikembalikan).'; }
    if (isset($_POST['add_balance']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $amt = (int)$_POST['amount']; $pdo->prepare("UPDATE users SET balance = balance + ? WHERE id=?")->execute([$amt, $uid]); $msg = 'Saldo ditambahkan!'; }
    if (isset($_POST['nerf_balance']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $amt = (int)$_POST['amount']; $pdo->prepare("UPDATE users SET balance = balance - ? WHERE id=?")->execute([$amt, $uid]); $msg = 'Saldo dikurangi!'; }
    if (isset($_POST['broadcast'])) { $bc = trim($_POST['message']); if ($bc) { $pdo->prepare("INSERT INTO announcements (message) VALUES (?)")->execute([$bc]); $msg = 'Broadcast terkirim.'; } }
}
$totalUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalServers = $pdo->query("SELECT COUNT(*) FROM servers")->fetchColumn();
$totalRam = $pdo->query("SELECT SUM(ram) FROM servers")->fetchColumn() ?: 0;
$users = $pdo->query("SELECT * FROM users WHERE role='user' ORDER BY id DESC LIMIT 5")->fetchAll();
$allUsers = $pdo->query("SELECT * FROM users WHERE role='user' ORDER BY id DESC")->fetchAll();
$servers = $pdo->query("SELECT s.*, u.username FROM servers s JOIN users u ON s.user_id=u.id ORDER BY s.id DESC")->fetchAll();
$reqs = $pdo->query("SELECT r.*, u.username FROM password_requests r JOIN users u ON r.user_id=u.id WHERE r.status='pending' ORDER BY r.id DESC")->fetchAll();
$vreqs = $pdo->query("SELECT r.*, u.username FROM verify_requests r JOIN users u ON r.user_id=u.id WHERE r.status='pending' ORDER BY r.id DESC")->fetchAll();
$wdreqs = $pdo->query("SELECT w.*, u.username FROM withdrawals w JOIN users u ON w.user_id=u.id WHERE w.status='pending' ORDER BY w.id DESC")->fetchAll();
$hacks = $pdo->query("SELECT * FROM hack_logs ORDER BY id DESC LIMIT 10")->fetchAll();
$pageTitle = 'X-Admin'; include __DIR__ . '/../includes/header.php';
?>
<div class="admin-layout">
    <div class="admin-sidebar">
        <h3 style="font-size:1.1em; margin-bottom:15px; padding-left:10px;"><i class="fas fa-shield-halved" style="color:var(--warning)"></i> Admin Menu</h3>
        <div class="admin-nav-item active" onclick="showTab('dash', event)"><i class="fas fa-chart-pie"></i> <span>Overview</span></div>
        <div class="admin-nav-item" onclick="showTab('api', event)"><i class="fas fa-cog"></i> <span>Pengaturan</span></div>
        <div class="admin-nav-item" onclick="showTab('users', event)"><i class="fas fa-users"></i> <span>Users</span></div>
        <div class="admin-nav-item" onclick="showTab('reqs', event)"><i class="fas fa-key"></i> <span>Req PW</span> <span style="margin-left:auto; background:var(--danger); color:#fff; padding:2px 8px; border-radius:10px; font-size:0.8em;"><?= count($reqs) ?></span></div>
        <div class="admin-nav-item" onclick="showTab('verif', event)"><i class="fas fa-check-circle"></i> <span>Verified</span> <span style="margin-left:auto; background:var(--primary); color:#fff; padding:2px 8px; border-radius:10px; font-size:0.8em;"><?= count($vreqs) ?></span></div>
        <div class="admin-nav-item" onclick="showTab('wd', event)"><i class="fas fa-money-bill-wave"></i> <span>Withdraw</span> <span style="margin-left:auto; background:var(--danger); color:#fff; padding:2px 8px; border-radius:10px; font-size:0.8em;"><?= count($wdreqs) ?></span></div>
        <div class="admin-nav-item" onclick="showTab('servers', event)"><i class="fas fa-server"></i> <span>Servers</span></div>
        <div class="admin-nav-item" onclick="showTab('bc', event)"><i class="fas fa-bullhorn"></i> <span>Broadcast</span></div>
        <div class="admin-nav-item" onclick="showTab('security', event)"><i class="fas fa-user-secret" style="color:var(--danger)"></i> <span>Security Logs</span></div>
        <a href="/logout.php" class="admin-nav-item" style="color:var(--danger); margin-top:20px;"><i class="fas fa-sign-out-alt"></i> <span>Logout</span></a>
    </div>
    <div>
        <?php if ($msg): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
        <div id="tab-dash" class="tab-content active">
            <h1 style="font-size:1.5em; margin-bottom:20px;">Overview</h1>
            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(130px, 1fr)); gap:15px; margin-bottom:20px;">
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">Users</div><div class="stat-value" data-count="<?= $totalUsers ?>">0</div></div>
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">Servers</div><div class="stat-value" data-count="<?= $totalServers ?>">0</div></div>
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">RAM (GB)</div><div class="stat-value" data-count="<?= round($totalRam/1024, 1) ?>">0</div></div>
            </div>
            <div class="card">
                <h3 style="margin-bottom:15px;"><i class="fas fa-toggle-on"></i> Kontrol Cepat</h3>
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:15px; border-radius:12px; margin-bottom:10px; border:1px solid rgba(255,255,255,0.1);"><div><b>Create Server</b></div><form method="POST"><button name="toggle_ptero" class="btn btn-sm <?= getSetting($pdo,'ptero_create_status')=='on'?'btn-success':'btn-danger' ?>"><?= getSetting($pdo,'ptero_create_status')=='on'?'ON':'OFF' ?></button></form></div>
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:15px; border-radius:12px; border:1px solid rgba(255,255,255,0.1);"><div><b>Maintenance</b></div><form method="POST"><button name="toggle_maintenance" class="btn btn-sm <?= getSetting($pdo,'maintenance')=='1'?'btn-danger':'btn-success' ?>"><?= getSetting($pdo,'maintenance')=='1'?'ON':'OFF' ?></button></form></div>
            </div>
        </div>
        <div id="tab-api" class="tab-content">
            <h1 style="font-size:1.5em; margin-bottom:20px;">Pengaturan</h1>
            <div class="card">
                <form method="POST">
                    <input type="hidden" name="save_api" value="1">
                    <div class="form-group"><label>Domain Panel</label><input type="text" name="ptero_domain" value="<?= htmlspecialchars(getSetting($pdo, 'ptero_domain')) ?>"></div>
                    <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;"><div class="form-group"><label>PTLA</label><input type="text" name="ptla" value="<?= htmlspecialchars(getSetting($pdo, 'ptla')) ?>"></div><div class="form-group"><label>PTLC</label><input type="text" name="ptlc" value="<?= htmlspecialchars(getSetting($pdo, 'ptlc')) ?>"></div></div>
                    <div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;"><div class="form-group"><label>Location ID</label><input type="number" name="location_id" value="<?= htmlspecialchars(getSetting($pdo, 'location_id')) ?>"></div><div class="form-group"><label>Egg ID</label><input type="number" name="egg_id" value="<?= htmlspecialchars(getSetting($pdo, 'egg_id')) ?>"></div></div>
                    <div class="form-group" style="background:rgba(245,158,11,0.1); padding:15px; border-radius:12px; border:1px solid var(--warning);"><label style="color:var(--warning);"><i class="fas fa-dice"></i> Gacha Win Rate (0% - 100%)</label><input type="range" name="gacha_winrate" min="0" max="100" value="<?= htmlspecialchars(getSetting($pdo, 'gacha_winrate', '50')) ?>" oninput="this.nextElementSibling.innerText = this.value + '%'"><div style="text-align:center; font-weight:800; color:var(--warning); margin-top:5px;"><?= htmlspecialchars(getSetting($pdo, 'gacha_winrate', '50')) ?>%</div></div>
                    <button class="btn btn-primary"><i class="fas fa-save"></i> Simpan</button>
                </form>
            </div>
        </div>
        <div id="tab-users" class="tab-content">
            <h1 style="font-size:1.5em; margin-bottom:20px;">Users</h1>
            <?php foreach ($allUsers as $u): ?>
                <div class="card" style="padding:16px; margin-bottom:10px;">
                    <div style="display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;">
                        <div><b>@<?= htmlspecialchars($u['username']) ?></b> <span class="badge badge-<?= $u['status'] ?>"><?= $u['status'] ?></span><br><span style="font-size:0.8em; color:var(--text-muted);">Saldo: Rp <?= number_format($u['balance'], 0, ',', '.') ?></span></div>
                        <div style="display:flex; gap:5px;">
                            <form method="POST" style="display:flex; gap:3px;"><input type="hidden" name="uid" value="<?= $u['id'] ?>"><input type="number" name="amount" placeholder="Nominal" required style="width:80px; padding:5px; border-radius:5px; border:1px solid var(--glass-border); background:var(--bg); color:var(--text); font-size:0.8em;"><button name="add_balance" class="btn btn-sm btn-success" title="Tambah Saldo"><i class="fas fa-plus"></i></button><button name="nerf_balance" class="btn btn-sm btn-warning" title="Kurangi Saldo"><i class="fas fa-minus"></i></button></form>
                            <form method="POST"><input type="hidden" name="uid" value="<?= $u['id'] ?>"><input type="hidden" name="current_status" value="<?= $u['status'] ?>"><button name="toggle_ban" class="btn btn-sm <?= $u['status']=='active'?'btn-danger':'btn-success' ?>"><i class="fas fa-<?= $u['status']=='active'?'ban':'check' ?>"></i></button></form>
                            <form method="POST" onsubmit="return confirm('Hapus?')"><input type="hidden" name="uid" value="<?= $u['id'] ?>"><button name="delete_user" class="btn btn-sm btn-danger"><i class="fas fa-trash"></i></button></form>
                        </div>
                    </div>
                </div>
            <?php endforeach; ?>
        </div>
        <div id="tab-reqs" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Req PW</h1><?php foreach ($reqs as $r): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between;"><div>@<?= $r['username'] ?></div><form method="POST"><input type="hidden" name="req_id" value="<?= $r['id'] ?>"><button name="approve_reset" class="btn btn-success btn-sm">Approve</button></form></div><?php endforeach; ?></div>
        <div id="tab-verif" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Verified</h1><?php foreach ($vreqs as $vr): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between;"><div>@<?= $vr['username'] ?></div><form method="POST"><input type="hidden" name="req_id" value="<?= $vr['id'] ?>"><button name="approve_verify" class="btn btn-success btn-sm">Approve</button></form></div><?php endforeach; ?></div>
        <div id="tab-wd" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Withdraw Requests</h1><?php foreach ($wdreqs as $wd): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px;"><div><b>@<?= htmlspecialchars($wd['username']) ?></b><br><span style="font-size:0.85em;">Rp <?= number_format($wd['amount'], 0, ',', '.') ?> ke DANA: <b><?= htmlspecialchars($wd['dana_number']) ?></b></span></div><div style="display:flex; gap:5px;"><form method="POST"><input type="hidden" name="wd_id" value="<?= $wd['id'] ?>"><button name="approve_wd" class="btn btn-sm btn-success">Approve</button></form><form method="POST"><input type="hidden" name="wd_id" value="<?= $wd['id'] ?>"><input type="hidden" name="uid" value="<?= $wd['user_id'] ?>"><input type="hidden" name="amount" value="<?= $wd['amount'] ?>"><button name="reject_wd" class="btn btn-sm btn-danger">Reject</button></form></div></div><?php endforeach; ?></div>
        <div id="tab-servers" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Servers</h1><?php foreach ($servers as $s): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; border-left:4px solid <?= $s['status']=='suspended'?'var(--danger)':'var(--success)' ?>;"><div><b><?= htmlspecialchars($s['server_name']) ?></b> (@<?= htmlspecialchars($s['username']) ?>)<br><span style="font-size:0.8em; color:var(--text-muted);"><?= strtoupper($s['status']) ?></span></div><div style="display:flex; gap:6px;"><?php if($s['status'] == 'active'): ?><form method="POST" style="display:flex; gap:5px;"><input type="hidden" name="srv_id" value="<?= $s['id'] ?>"><input type="text" name="reason" placeholder="Alasan..." required style="width:100px; padding:5px; border-radius:5px; border:1px solid var(--glass-border); background:var(--bg); color:var(--text); font-size:0.8em;"><button name="suspend_srv" class="btn btn-sm btn-warning"><i class="fas fa-ban"></i></button></form><?php else: ?><form method="POST"><input type="hidden" name="srv_id" value="<?= $s['id'] ?>"><button name="unsuspend_srv" class="btn btn-sm btn-success"><i class="fas fa-check"></i></button></form><?php endif; ?></div></div><?php endforeach; ?></div>
        <div id="tab-bc" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Broadcast</h1><div class="card"><form method="POST"><input type="hidden" name="broadcast" value="1"><div class="form-group"><textarea name="message" rows="4" required></textarea></div><button class="btn btn-primary btn-block">Kirim</button></form></div></div>
        <div id="tab-security" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px; color:var(--danger);"><i class="fas fa-user-secret"></i> Security Logs</h1><?php if(empty($hacks)): ?><div class="card" style="text-align:center; color:var(--success);">Aman! Belum ada percobaan hack.</div><?php endif; ?><?php foreach ($hacks as $h): ?><div class="card" style="padding:16px; border-left:4px solid var(--danger);"><div style="font-size:0.85em;"><b>IP:</b> <?= htmlspecialchars($h['ip_address']) ?> | <b>User:</b> <?= htmlspecialchars($h['username']) ?></div><div style="font-size:0.8em; color:var(--text-muted); margin-top:5px;">Action: <span style="color:var(--danger);"><?= htmlspecialchars($h['action']) ?></span></div></div><?php endforeach; ?></div>
    </div>
    <div class="admin-right-panel"><h3 style="font-size:1.1em; margin-bottom:15px;"><i class="fas fa-bell"></i> Recent Users</h3><?php foreach($users as $u): ?><div style="padding:10px 0; border-bottom:1px solid var(--glass-border); font-size:0.85em;"><b>@<?= htmlspecialchars($u['username']) ?></b><br><span style="font-size:0.8em; color:var(--text-muted);"><?= date('d M Y', strtotime($u['created_at'])) ?></span></div><?php endforeach; ?></div>
</div>
<script>
function showTab(name, event) { document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active')); document.querySelectorAll('.admin-nav-item').forEach(el => el.classList.remove('active')); document.getElementById('tab-' + name).classList.add('active'); event.currentTarget.classList.add('active'); }
document.querySelectorAll('.stat-value').forEach(el => { const target = parseFloat(el.dataset.count); let current = 0; const step = target / 30; if(target === 0) return; const timer = setInterval(() => { current += step; if (current >= target) { current = target; clearInterval(timer); } el.textContent = Math.round(current); }, 30); });
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

echo -e "${GREEN}  ✅ Semua Halaman OK${NC}\n"

# ============================================
# 7. NGINX & SSL
# ============================================
echo -e "${CYAN}[7/7] Setup Nginx & SSL...${NC}"
cat > "$NGINX_CONF" << NGINXEOF
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;
    root $WEB_ROOT;
    index index.php index.html;
    client_max_body_size 10M;
    location ~ /includes/ { deny all; }
    location / { try_files \$uri \$uri/ =404; }
    location ~ \.php\$ { include snippets/fastcgi-php.conf; fastcgi_pass unix:/var/run/php/php8.3-fpm.sock; }
}
NGINXEOF

ln -sf "$NGINX_CONF" /etc/nginx/sites-enabled/ 2>/dev/null
nginx -t >/dev/null 2>&1 && systemctl reload nginx
chown -R www-data:www-data "$WEB_ROOT"
chmod -R 755 "$WEB_ROOT"
chmod -R 775 "$WEB_ROOT/uploads"
systemctl restart php8.3-fpm

SERVER_IP=$(curl -4 -s --max-time 5 ifconfig.me 2>/dev/null)
DOMAIN_IP=$(dig +short A "$DOMAIN" @8.8.8.8 2>/dev/null | head -1)
if [[ "$SERVER_IP" == "$DOMAIN_IP" ]]; then certbot --nginx -d "$DOMAIN" --non-interactive --agree-tos -m "$EMAIL" --redirect >/dev/null 2>&1; fi
PROTO="https"; [[ ! -f "/etc/letsencrypt/live/$DOMAIN/fullchain.pem" ]] && PROTO="http"

clear
echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ INSTALLASI v36.0 BERHASIL!             ║${NC}"
echo -e "${GREEN}║  👑 CASINO • GACHA • WAF • FULL SYSTEM     ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${CYAN}🔗 URL Web:${NC} $PROTO://$DOMAIN"
echo -e "${MAGENTA}🔒 Admin Panel:${NC} $PROTO://$DOMAIN/admin/"
echo ""
echo -e "${WHITE}🔑 Admin Secret:${NC}"
echo -e "   Username : ${WHITE}aulia${NC}"
echo -e "   Password : ${WHITE}aulia55${NC}"
echo ""
echo -e "${CYAN}📌 Fitur Baru v36.0:${NC}"
echo -e "  ✅ Referral Code Acak (Text+Angka)"
echo -e "  ✅ Auto-Check Panel (Down = Create Disabled)"
echo -e "  ✅ Admin Balance Manager (Add/Nerf)"
echo -e "  ✅ Gacha System + Slider Win Rate di Admin"
echo -e "  ✅ Log WD Berjalan di Landing Page (Sensor)"
echo -e "  ✅ TOS & Split Login/Register UI"
echo -e "  ✅ WAF (Anti SQLi) & Anti-Hack /admin"
echo ""
echo -e "${YELLOW}⚠️  Coba akses /admin tanpa login, bakal keluar tulisan 'LU SIAPA NGENTOD'!${NC}"
echo -e "${GREEN}🚀 Login sebagai admin buat setting API Pterodactyl!${NC}"
