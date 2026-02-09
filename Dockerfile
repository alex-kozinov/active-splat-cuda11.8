FROM nvidia/cuda:11.8.0-devel-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive \
    TORCH_CUDA_ARCH_LIST="8.6+PTX" \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1
# --------------------------------------------------------
# 1. Base system packages
# --------------------------------------------------------
RUN apt-get update && apt-get install -y \
    software-properties-common \
    python3.9 python3.9-dev python3.9-venv python3-pip \
    git tmux wget curl ca-certificates openssh-server nginx \
    libgl1-mesa-glx libglib2.0-0 \
    build-essential cmake ninja-build pkg-config \
    libegl1-mesa-dev libgl1-mesa-dev \
    libx11-6 libxext6 libxi6 libxrender1 \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

# Make python/pip the default commands
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3.9 1 && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.9 1 && \
    python -m pip install --upgrade pip && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

# --------------------------------------------------------
# 2. Prepare host (SSH, NGINX)
# --------------------------------------------------------
RUN rm -f /etc/ssh/ssh_host_*

# NGINX Proxy
COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/readme.html /usr/share/nginx/html/readme.html

# --------------------------------------------------------
# 3. Install PyTorch with CUDA 12.1 support
# --------------------------------------------------------
RUN pip install --upgrade pip setuptools wheel
RUN pip install torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cu118

# --------------------------------------------------------
# 4. Install JupyterLab
# --------------------------------------------------------
RUN pip install jupyterlab

# --------------------------------------------------------
# 5. Clone some project repository
# --------------------------------------------------------
WORKDIR /workspace

# --------------------------------------------------------
# 6. Install project dependencies
# --------------------------------------------------------


# --------------------------------------------------------
# 7. Default working directory and entrypoint
# --------------------------------------------------------
# Start Script
COPY scripts/start.sh /start.sh
RUN chmod 755 /start.sh
WORKDIR /workspace
CMD ["/start.sh"]
