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
export TAG=v3.0.5p8

# Run Docker Compose
docker compose up -d || { echo "Lỗi: Docker Compose up thất bại"; exit 1; }

# Create setup flag file to mark completion
touch /home/miva/.setup_done

echo "Setup miva hoàn tất."
