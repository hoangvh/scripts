# 📜 Scripts MIVA, MIRA, SGW (Allwiner H618)
---
## 🔑 Remote SSH
- Địa chỉ IP mặc định: **192.168.11.102**
---
## 🚀 MIVA, kiểm tra nhanh phần cứng: HDMI, Audio output 3.5 jack, Relays
Chạy lệnh sau trong terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_hw_test -o /usr/local/bin/hw_test && chmod +x /usr/local/bin/hw_test
hw_test```

## 🚀 MIVA, patch HDMI hot plug
Chạy lệnh sau trong terminal:
```bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_hdmi_hotplug_patch.sh)```
