#!/bin/bash
# ============================================
#   🔥 RENDZZ PANEL v31.1 HOTFIX (MOBILE UI)
#   Fix Admin Layout Overlap & Z-Index
# ============================================

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; NC='\033[0m'

read -p "👉 Masukkan Domain Web kamu (contoh: webpanelkita.rendzz-panelku.biz.id): " DOMAIN
[[ -z "$DOMAIN" ]] && { echo -e "${RED}❌ Domain tidak boleh kosong!${NC}"; exit 1; }

WEB_ROOT="/var/www/$DOMAIN"

if [ ! -d "$WEB_ROOT" ]; then
    echo -e "${RED}❌ Folder web tidak ditemukan!${NC}"; exit 1
fi

echo -e "${CYAN}[1/3] Memperbaiki Layout CSS (Mobile Responsive)...${NC}"

# Inject CSS perbaikan di paling bawah style.css (biar menimpa yang lama)
cat >> "$WEB_ROOT/assets/css/style.css" << 'CSSEOF'

/* ==========================================
   FIX MOBILE ADMIN LAYOUT & Z-INDEX
   ========================================== */

/* 1. Bikin layout 3 bar jadi 1 kolom rapi di HP */
@media (max-width: 1000px) {
    .admin-layout {
        display: flex;
        flex-direction: column;
        padding: 15px;
        gap: 15px;
    }
    .admin-sidebar, .admin-right-panel {
        position: static; /* Biar ga ngegantung */
        width: 100%;
    }
    /* Rapihin menu biar horizontal di HP */
    .admin-sidebar {
        display: flex;
        flex-wrap: wrap;
        gap: 8px;
        padding: 10px;
    }
    .admin-sidebar h3 { width: 100%; margin-bottom: 5px; }
    .admin-nav-item {
        margin-bottom: 0;
        padding: 8px 12px;
        font-size: 0.85em;
        flex: 1 1 auto;
        justify-content: center;
    }
    .admin-nav-item span { margin-left: 5px !important; }
}

/* 2. Benerin Kontrol Cepat yang ketutupan / abu-abu */
#tab-dash .card {
    background: var(--card) !important;
    backdrop-filter: blur(20px);
    border: 1px solid var(--glass-border) !important;
}
#tab-dash .card > div[style*="background:rgba(0,0,0,0.2)"] {
    background: rgba(255, 255, 255, 0.05) !important; /* Warna agak terang biar kelihatan */
    border: 1px solid rgba(255, 255, 255, 0.1);
    margin-bottom: 10px;
    padding: 15px !important;
    flex-wrap: wrap; /* Biar tombol turun ke bawah kalau layar sempit */
    gap: 10px;
}

/* 3. Fix Z-Index (Tombol WA & Tawk.to jangan nutupin konten) */
.floating-wa {
    bottom: 80px !important; /* Naikin dikit biar ga nabrak bottom nav */
    z-index: 9990 !important;
}
/* Tawk.to widget biasanya di pojok kanan bawah, kita geser dikit */
.widget-visible #tawkchat-container {
    bottom: 140px !important; 
}
CSSEOF

echo -e "${CYAN}[2/3] Memperbaiki Tombol Toggle (Biar Gak Muter)...${NC}"
# Hapus tombol toggle yang lama di admin/index.php, ganti pakai form yang rapi
cat > /tmp/fix_admin.php << 'PHPEOF'
<?php
require_once __DIR__ . '/../includes/config.php';
requireAdmin();
$msg = '';
if ($_SERVER['REQUEST_METHOD'] === 'POST') {
    if (isset($_POST['save_api'])) { foreach (['ptero_domain', 'ptla', 'ptlc', 'location_id', 'egg_id', 'wa_support'] as $k) if (isset($_POST[$k])) $pdo->prepare("UPDATE settings SET v=? WHERE k=?")->execute([trim($_POST[$k]), $k]); $msg = 'Disimpan.'; }
    if (isset($_POST['toggle_ptero'])) { $new = getSetting($pdo, 'ptero_create_status') == 'on' ? 'off' : 'on'; $pdo->prepare("UPDATE settings SET v=? WHERE k='ptero_create_status'")->execute([$new]); $msg = "Ptero: ".strtoupper($new); }
    if (isset($_POST['toggle_maintenance'])) { $new = getSetting($pdo, 'maintenance') == '1' ? '0' : '1'; $pdo->prepare("UPDATE settings SET v=? WHERE k='maintenance'")->execute([$new]); $msg = "Maint: ".($new=='1'?'ON':'OFF'); }
    if (isset($_POST['approve_verify']) && isset($_POST['req_id'])) { $reqId = (int)$_POST['req_id']; $req = $pdo->prepare("SELECT user_id FROM verify_requests WHERE id=?"); $req->execute([$reqId]); $u = $req->fetch(); $pdo->prepare("UPDATE users SET is_verified=1 WHERE id=?")->execute([$u['user_id']]); $pdo->prepare("UPDATE verify_requests SET status='approved' WHERE id=?")->execute([$reqId]); $msg = 'Verified!'; }
    if (isset($_POST['approve_reset']) && isset($_POST['req_id'])) { $reqId = (int)$_POST['req_id']; $newPass = "NewPass" . rand(1000,9999); $req = $pdo->prepare("SELECT user_id FROM password_requests WHERE id=?"); $req->execute([$reqId]); $u = $req->fetch(); $pdo->prepare("UPDATE users SET password=? WHERE id=?")->execute([password_hash($newPass, PASSWORD_BCRYPT), $u['user_id']]); $pdo->prepare("UPDATE password_requests SET status='approved', new_password=? WHERE id=?")->execute([$newPass, $reqId]); $msg = 'PW: ' . $newPass; }
    if (isset($_POST['toggle_ban']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $new = $_POST['current_status'] === 'active' ? 'banned' : 'active'; $pdo->prepare("UPDATE users SET status=? WHERE id=?")->execute([$new, $uid]); $msg = 'Status diubah.'; }
    if (isset($_POST['delete_user']) && isset($_POST['uid'])) { $uid = (int)$_POST['uid']; $pdo->prepare("DELETE FROM users WHERE id=? AND role='user'")->execute([$uid]); $pdo->prepare("DELETE FROM servers WHERE user_id=?")->execute([$uid]); $msg = 'User dihapus.'; }
    if (isset($_POST['suspend_srv'])) { $srvId = (int)$_POST['srv_id']; $reason = trim($_POST['reason']); $pdo->prepare("UPDATE servers SET status='suspended', abuse_reason=? WHERE id=?")->execute([$reason, $srvId]); $msg = 'Suspended!'; }
    if (isset($_POST['unsuspend_srv'])) { $srvId = (int)$_POST['srv_id']; $pdo->prepare("UPDATE servers SET status='active', abuse_reason=NULL WHERE id=?")->execute([$srvId]); $msg = 'Unsuspended!'; }
    if (isset($_POST['broadcast'])) { $bc = trim($_POST['message']); if ($bc) { $pdo->prepare("INSERT INTO announcements (message) VALUES (?)")->execute([$bc]); $msg = 'Broadcast terkirim.'; } }
}
$totalUsers = $pdo->query("SELECT COUNT(*) FROM users WHERE role='user'")->fetchColumn();
$totalServers = $pdo->query("SELECT COUNT(*) FROM servers")->fetchColumn();
$totalRam = $pdo->query("SELECT SUM(ram) FROM servers")->fetchColumn() ?: 0;
$users = $pdo->query("SELECT * FROM users WHERE role='user' ORDER BY id DESC LIMIT 5")->fetchAll();
$servers = $pdo->query("SELECT s.*, u.username FROM servers s JOIN users u ON s.user_id=u.id ORDER BY s.id DESC")->fetchAll();
$reqs = $pdo->query("SELECT r.*, u.username FROM password_requests r JOIN users u ON r.user_id=u.id WHERE r.status='pending' ORDER BY r.id DESC")->fetchAll();
$vreqs = $pdo->query("SELECT r.*, u.username FROM verify_requests r JOIN users u ON r.user_id=u.id WHERE r.status='pending' ORDER BY r.id DESC")->fetchAll();
$pageTitle = 'X-Admin'; include __DIR__ . '/../includes/header.php';
?>
<div class="admin-layout">
    <div class="admin-sidebar">
        <h3 style="font-size:1.1em; margin-bottom:15px; padding-left:10px;"><i class="fas fa-shield-halved" style="color:var(--warning)"></i> Admin</h3>
        <div class="admin-nav-item active" onclick="showTab('dash', event)"><i class="fas fa-chart-pie"></i> <span>Overview</span></div>
        <div class="admin-nav-item" onclick="showTab('api', event)"><i class="fas fa-cog"></i> <span>Pengaturan</span></div>
        <div class="admin-nav-item" onclick="showTab('reqs', event)"><i class="fas fa-key"></i> <span>Req PW</span> <span style="margin-left:auto; background:var(--danger); color:#fff; padding:2px 8px; border-radius:10px; font-size:0.8em;"><?= count($reqs) ?></span></div>
        <div class="admin-nav-item" onclick="showTab('verif', event)"><i class="fas fa-check-circle"></i> <span>Verified</span> <span style="margin-left:auto; background:var(--primary); color:#fff; padding:2px 8px; border-radius:10px; font-size:0.8em;"><?= count($vreqs) ?></span></div>
        <div class="admin-nav-item" onclick="showTab('servers', event)"><i class="fas fa-server"></i> <span>Servers</span></div>
        <div class="admin-nav-item" onclick="showTab('bc', event)"><i class="fas fa-bullhorn"></i> <span>Broadcast</span></div>
        <a href="/logout.php" class="admin-nav-item" style="color:var(--danger); margin-top:20px;"><i class="fas fa-sign-out-alt"></i> <span>Logout</span></a>
    </div>
    <div>
        <?php if ($msg): ?><div class="alert alert-success"><i class="fas fa-check-circle"></i> <?= $msg ?></div><?php endif; ?>
        
        <div id="tab-dash" class="tab-content active">
            <h1 style="font-size:1.5em; margin-bottom:20px;">Overview</h1>
            <div style="display:grid; grid-template-columns:repeat(auto-fit, minmax(120px, 1fr)); gap:15px; margin-bottom:20px;">
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">Users</div><div class="stat-value" data-count="<?= $totalUsers ?>">0</div></div>
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">Servers</div><div class="stat-value" data-count="<?= $totalServers ?>">0</div></div>
                <div class="card" style="margin:0; padding:20px;"><div style="font-size:0.75em; color:var(--text-muted); text-transform:uppercase;">RAM (GB)</div><div class="stat-value" data-count="<?= round($totalRam/1024, 1) ?>">0</div></div>
            </div>
            <div class="card">
                <h3 style="margin-bottom:15px;"><i class="fas fa-toggle-on"></i> Kontrol Cepat</h3>
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:15px; border-radius:12px; margin-bottom:10px; border:1px solid rgba(255,255,255,0.1);">
                    <div><b>Create Server</b></div>
                    <form method="POST"><button name="toggle_ptero" class="btn btn-sm <?= getSetting($pdo,'ptero_create_status')=='on'?'btn-success':'btn-danger' ?>"><?= getSetting($pdo,'ptero_create_status')=='on'?'ON':'OFF' ?></button></form>
                </div>
                <div style="display:flex; justify-content:space-between; align-items:center; background:rgba(255,255,255,0.05); padding:15px; border-radius:12px; border:1px solid rgba(255,255,255,0.1);">
                    <div><b>Maintenance</b></div>
                    <form method="POST"><button name="toggle_maintenance" class="btn btn-sm <?= getSetting($pdo,'maintenance')=='1'?'btn-danger':'btn-success' ?>"><?= getSetting($pdo,'maintenance')=='1'?'ON':'OFF' ?></button></form>
                </div>
            </div>
        </div>

        <div id="tab-api" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Pengaturan</h1><div class="card"><form method="POST"><input type="hidden" name="save_api" value="1"><div class="form-group"><label>Domain Panel</label><input type="text" name="ptero_domain" value="<?= htmlspecialchars(getSetting($pdo, 'ptero_domain')) ?>"></div><div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;"><div class="form-group"><label>PTLA</label><input type="text" name="ptla" value="<?= htmlspecialchars(getSetting($pdo, 'ptla')) ?>"></div><div class="form-group"><label>PTLC</label><input type="text" name="ptlc" value="<?= htmlspecialchars(getSetting($pdo, 'ptlc')) ?>"></div></div><div style="display:grid; grid-template-columns:1fr 1fr; gap:12px;"><div class="form-group"><label>Location ID</label><input type="number" name="location_id" value="<?= htmlspecialchars(getSetting($pdo, 'location_id')) ?>"></div><div class="form-group"><label>Egg ID</label><input type="number" name="egg_id" value="<?= htmlspecialchars(getSetting($pdo, 'egg_id')) ?>"></div></div><div class="form-group"><label>WA Support</label><input type="text" name="wa_support" value="<?= htmlspecialchars(getSetting($pdo, 'wa_support')) ?>"></div><button class="btn btn-primary"><i class="fas fa-save"></i> Simpan</button></form></div></div>
        
        <div id="tab-servers" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Servers</h1><?php foreach ($servers as $s): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between; align-items:center; flex-wrap:wrap; gap:10px; border-left:4px solid <?= $s['status']=='suspended'?'var(--danger)':'var(--success)' ?>;"><div><b><?= htmlspecialchars($s['server_name']) ?></b> (@<?= htmlspecialchars($s['username']) ?>)<br><span style="font-size:0.8em; color:var(--text-muted);"><?= strtoupper($s['status']) ?></span></div><div style="display:flex; gap:6px;"><?php if($s['status'] == 'active'): ?><form method="POST" style="display:flex; gap:5px;"><input type="hidden" name="srv_id" value="<?= $s['id'] ?>"><input type="text" name="reason" placeholder="Alasan..." required style="width:100px; padding:5px; border-radius:5px; border:1px solid var(--glass-border); background:var(--bg); color:var(--text); font-size:0.8em;"><button name="suspend_srv" class="btn btn-sm btn-warning"><i class="fas fa-ban"></i></button></form><?php else: ?><form method="POST"><input type="hidden" name="srv_id" value="<?= $s['id'] ?>"><button name="unsuspend_srv" class="btn btn-sm btn-success"><i class="fas fa-check"></i></button></form><?php endif; ?></div></div><?php endforeach; ?></div>
        
        <div id="tab-reqs" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Req PW</h1><?php foreach ($reqs as $r): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between;"><div>@<?= $r['username'] ?></div><form method="POST"><input type="hidden" name="req_id" value="<?= $r['id'] ?>"><button name="approve_reset" class="btn btn-success btn-sm">Approve</button></form></div><?php endforeach; ?></div>
        <div id="tab-verif" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Verified</h1><?php foreach ($vreqs as $vr): ?><div class="card" style="padding:16px; display:flex; justify-content:space-between;"><div>@<?= $vr['username'] ?></div><form method="POST"><input type="hidden" name="req_id" value="<?= $vr['id'] ?>"><button name="approve_verify" class="btn btn-success btn-sm">Approve</button></form></div><?php endforeach; ?></div>
        <div id="tab-bc" class="tab-content"><h1 style="font-size:1.5em; margin-bottom:20px;">Broadcast</h1><div class="card"><form method="POST"><input type="hidden" name="broadcast" value="1"><div class="form-group"><textarea name="message" rows="4" required></textarea></div><button class="btn btn-primary btn-block">Kirim</button></form></div></div>
    </div>
    <div class="admin-right-panel"><h3 style="font-size:1.1em; margin-bottom:15px;"><i class="fas fa-bell"></i> Recent Users</h3><?php foreach($users as $u): ?><div style="padding:10px 0; border-bottom:1px solid var(--glass-border); font-size:0.85em;"><b>@<?= htmlspecialchars($u['username']) ?></b><br><span style="font-size:0.8em; color:var(--text-muted);"><?= date('d M Y', strtotime($u['created_at'])) ?></span></div><?php endforeach; ?></div>
</div>
<script>
function showTab(name, event) { document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('active')); document.querySelectorAll('.admin-nav-item').forEach(el => el.classList.remove('active')); document.getElementById('tab-' + name).classList.add('active'); event.currentTarget.classList.add('active'); }
document.querySelectorAll('.stat-value').forEach(el => { const target = parseFloat(el.dataset.count); let current = 0; const step = target / 30; if(target === 0) return; const timer = setInterval(() => { current += step; if (current >= target) { current = target; clearInterval(timer); } el.textContent = Math.round(current); }, 30); });
</script>
<?php include __DIR__ . '/../includes/footer.php'; ?>
PHPEOF

cp /tmp/fix_admin.php "$WEB_ROOT/admin/index.php"
rm /tmp/fix_admin.php

# Fix CSS Global biar Tawk.to ga nabrak tombol bawah
sed -i 's/bottom: 90px; right: 20px;/bottom: 100px; right: 20px;/g' "$WEB_ROOT/assets/css/style.css"

systemctl restart nginx php8.3-fpm

echo -e "${GREEN}╔════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  ✅ BUG TAMPILAN ADMIN BERHASIL DIPERBAIKI!║${NC}"
echo -e "${GREEN}║  📱 Layout HP Sekarang Rapi & Responsif    ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════╝${NC}"
