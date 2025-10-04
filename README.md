# 📜 Scripts

Tập hợp các script cài đặt **MIVA**, **MIRA**.
---
## 🔑 Truy cập mặc định
- SSH vào thiết bị với IP: **192.168.11.102**
---
## 🚀 MIVA, kiểm tra nhanh phần cứng: HDMI, Audio output 3.5 jack, Relays
Chạy lệnh sau trong terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_hw_test -o /usr/local/bin/hw_test && chmod +x /usr/local/bin/hw_test
hw_test
