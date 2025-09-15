# 📜 Scripts

Tập hợp các script cài đặt MIVA, MIRA
---
SSH vào IP mặc định 192.168.11.102

## 🚀 Cài đặt Miva
Chạy lệnh sau trong terminal:

```bash
bash -c "$(wget -qO- https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_setup.sh)"

Chạy lệnh để kiểm tra quá trình cài đặt lần đầu:

```bash
journalctl -u miva-setup.service -f
