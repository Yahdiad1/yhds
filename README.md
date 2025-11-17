# yhds
# 🚀 YHDS VPS PREMIUM
Full VPS Manager • SSH/WS • Trojan-WS • UDP Custom • Auto-Fix • Auto-Restart • Dashboard

Script ini dibuat khusus untuk mempermudah instalasi layanan VPN premium berbasis:
- **SSH / WebSocket**
- **Trojan-WS (TLS / Non-TLS)**
- **UDP Custom (Stable)**
- **Nginx + Xray (Auto Fix & Auto Restart)**
- **Full Menu Control**

Semua layanan berjalan otomatis tanpa perlu domain.  
Kompatibel untuk **Debian 10 / 11 / 12** dan VPS RAM kecil.

---

## ✨ Fitur Utama
- Full menu (dashboard + create akun + delete + trial + list)
- SSH / WS Premium
- Trojan-WS TLS
- UDP Custom stable
- Auto perbaikan Xray & Nginx
- Auto reload menu setelah close
- Telegram bot notification
- Anti error & lengkap dengan auto-clean service
- Sistem database lokal `/etc/yhds/users.db`

---

## 📥 Cara Install
Jalankan perintah berikut di VPS:

```bash
wget -O install_yhds.sh https://raw.githubusercontent.com/Yahdiad1/yhds/main/install_yhds.sh
chmod +x install_yhds.sh
bash install_yhds.sh
