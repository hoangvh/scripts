# MIRA Docker runtime recovery

Script [`setup-mira-runtime.sh`](../setup-mira-runtime.sh) tăng khả năng MIRA tự chạy lại sau khi host khởi động bất thường:

- đổi `/home/mira/docker/docker-compose.yml` từ `restart: unless-stopped` thành `restart: always`;
- cập nhật restart policy của container `mira` đang tồn tại;
- cài `mira-runtime.service`, chờ Docker và thử khởi động MIRA tối đa 24 lần, cách nhau 5 giây;
- nếu container chưa tồn tại, chạy `docker compose up -d mira`;
- không thay đổi `mira-autostart.service` và `mira-install.sh`.

Script có thể chạy lại nhiều lần. Khi cần sửa Compose, script tạo file sao lưu có hậu tố `.bak.YYYYmmdd-HHMMSS`.

## Cài online từ GitHub

Đăng nhập thiết bị bằng SSH, chuyển sang `root`, sau đó tải script về trước khi chạy:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/hoangvh/scripts/main/setup-mira-runtime.sh \
  -o /tmp/setup-mira-runtime.sh
chmod 0755 /tmp/setup-mira-runtime.sh
sh -n /tmp/setup-mira-runtime.sh
/tmp/setup-mira-runtime.sh
```

Lệnh rút gọn (chỉ dùng khi đã kiểm tra nội dung script):

```bash
curl -fsSL https://raw.githubusercontent.com/hoangvh/scripts/main/setup-mira-runtime.sh | sh
```

## Cài offline khi thiết bị không có Internet

Trên máy quản trị có sẵn file script:

```bash
scp setup-mira-runtime.sh root@192.168.11.102:/tmp/setup-mira-runtime.sh
ssh root@192.168.11.102
```

Trên thiết bị:

```bash
chmod 0755 /tmp/setup-mira-runtime.sh
sh -n /tmp/setup-mira-runtime.sh
/tmp/setup-mira-runtime.sh
```

Nếu máy quản trị có Internet nhưng thiết bị không có Internet, tải file trên máy quản trị trước:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/hoangvh/scripts/main/setup-mira-runtime.sh \
  -o setup-mira-runtime.sh
scp setup-mira-runtime.sh root@192.168.11.102:/tmp/setup-mira-runtime.sh
ssh root@192.168.11.102 'chmod 0755 /tmp/setup-mira-runtime.sh && sh -n /tmp/setup-mira-runtime.sh && /tmp/setup-mira-runtime.sh'
```

## Kiểm tra sau khi cài

```bash
systemctl is-enabled mira-runtime.service
systemctl is-active mira-runtime.service
systemctl --no-pager --full status mira-runtime.service
docker inspect -f 'status={{.State.Status}} restart={{.HostConfig.RestartPolicy.Name}}' mira
grep -n 'restart:' /home/mira/docker/docker-compose.yml
```

Kết quả mong đợi là service `enabled`, `active`, container `running` và restart policy `always`.

## Xem log khi có lỗi

```bash
journalctl -u mira-runtime.service -b --no-pager
journalctl -u docker.service -b --no-pager
docker ps -a --filter name=mira
```

## Lưu ý triển khai nhiều thiết bị

Nên cập nhật thử một nhóm nhỏ, reboot kiểm tra, rồi mới triển khai toàn bộ. Không lưu mật khẩu SSH hoặc GitHub token trong script.
