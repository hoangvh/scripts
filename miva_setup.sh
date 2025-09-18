#!/bin/bash

# Check if the /home/miva directory exists
if [ -d "/home/miva" ]; then
    # If directory exists, check for setup flag
    if [ -f "/home/miva/.setup_done" ]; then
        echo "Miva đã được setup trước đó. Không thực hiện lại."
        exit 0
    else
        echo "Thư mục miva tồn tại nhưng chưa có flag setup_done. Tiếp tục setup..."
    fi
else
    echo "Thư mục miva chưa tồn tại. Bắt đầu setup..."
fi

# Change to /home directory
cd /home || { echo "Lỗi: Không thể cd vào /home"; exit 1; }

# Clone the repository
git clone https://github.com/smatecvn/miva.git miva || { echo "Lỗi: Không thể clone repository"; exit 1; }

# Change to setup directory
cd /home/miva/setup || { echo "Lỗi: Không thể cd vào /home/miva/setup"; exit 1; }

# Make the setup script executable
chmod +x setup_miva.sh || { echo "Lỗi: Không thể chmod setup_miva.sh"; exit 1; }

# Run the setup script
./setup_miva.sh || { echo "Lỗi: Thực thi setup_miva.sh thất bại"; exit 1; }

# Change to docker directory
cd /home/miva/docker || { echo "Lỗi: Không thể cd vào /home/miva/docker"; exit 1; }

# Export TAG variable
export TAG=latest

# Run Docker Compose
docker compose up -d || { echo "Lỗi: Docker Compose up thất bại"; exit 1; }

######################################
# Cài đặt NetBird client
######################################

echo "Bắt đầu setup NetBird client..."

# Lấy MAC eth0
mac=$(< /sys/class/net/eth0/address)
hex=${mac//:/}
hex=${hex^^}
dec=$((16#$hex))

# Tạo peer name
peer_name="880${dec}"

echo "NetBird peer name (hostname): $peer_name"

# Xóa container cũ nếu có
docker rm -f netbird-client >/dev/null 2>&1 || true

# Chạy NetBird client
docker run -d \
  --cap-add=NET_ADMIN \
  -e NB_SETUP_KEY=158CB298-1B3E-4296-B366-A1F05A6F02E7 \
  -v netbird-client:/var/lib/netbird \
  --hostname "${peer_name}" \
  --name netbird-client \
  netbirdio/netbird:latest up || { echo "Lỗi: Chạy NetBird client thất bại"; exit 1; }

######################################

# Create setup flag file to mark completion
touch /home/miva/.setup_done

echo "Setup miva + netbird hoàn tất."
