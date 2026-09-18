# 📜 Scripts MIVA, MIRA, SGW (Allwiner H618, RK3328)
---
## 🔑 Remote SSH
- Địa chỉ IP mặc định: **192.168.11.102**
---
## 🚀 MIVA H618, kiểm tra nhanh phần cứng: HDMI, Audio output 3.5 jack, Relays
Chạy lệnh sau trong terminal:
```bash
curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_hw_test -o /usr/local/bin/hw_test && chmod +x /usr/local/bin/hw_test
hw_test
```
## 🚀 MIVA H618, patch HDMI hot plug
Chạy lệnh sau trong terminal:
```
bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/miva_hdmi_hotplug_patch.sh)
```
## 🚀 MIRA RK3328, AD-B01 setup script
Chạy lệnh sau trong terminal:
```
bash -c "$(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/mira-rk3328adb01)"
```
## 🚀 MIVA H618, cài application MIVA (one-line installer)
Chạy trên firmware MIVA DSDZ-H618 đã boot production:
```
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/install-miva.sh)
```
Chọn Docker image tag:
```
TAG=<tag> bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/refs/heads/main/install-miva.sh)
```
Default: `TAG=latest`. Script tự clone upstream `smatecvn/miva` vào `/home/miva`, cài service/udev/cron, chuyển network sang netplan upstream (`01/02/03-netcfg.yaml`), `generate-devices.sh`, `docker compose pull` + `up -d`, rồi verify container.

## 🚀 MIVA H618 LPDDR3, setup + chuẩn bị cài eMMC
```bash
sudo -i
bash <(curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/main/miva-h618-lpddr3_setup.sh)
```
Script clone/cập nhật MIVA vào `/home/miva`, bỏ `--no-audio`, chạy `setup_miva.sh`, tạo `docker-compose.override.yml`, bỏ mapping `/dev/ttyS0`, pull image `TAG=latest`, rồi mở `armbian-install` để chọn eMMC.
