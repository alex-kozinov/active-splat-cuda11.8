FROM nvidia/cuda:11.8.0-devel-ubuntu20.04

# Use bash for RUN so we can `source` ROS and use `&&` safely
SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    TORCH_CUDA_ARCH_LIST="8.6+PTX" \
    HF_HUB_ENABLE_HF_TRANSFER=1 \
    PIP_NO_CACHE_DIR=1 \
    PYTHONUNBUFFERED=1 \
    # Make sure basic bins + CUDA are always visible (you had PATH issues at runtime)
    PATH="/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    # CMake args for habitat-sim CUDA build (adjust 86 if your GPU is not RTX30/A10)
    CMAKE_ARGS="-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=86 -DCMAKE_EXPORT_COMPILE_COMMANDS=ON"
# --------------------------------------------------------
# 1. Base system packages
# --------------------------------------------------------
RUN apt-get update && apt-get install -y \
    software-properties-common \
    python3 python3-dev python3-venv python3-pip \
    git tmux wget curl ca-certificates openssh-server nginx \
    libgl1-mesa-glx libglib2.0-0 \
    build-essential ninja-build pkg-config \
    libegl1-mesa-dev libgl1-mesa-dev \
    libx11-6 libxext6 libxi6 libxrender1 \
    # GLFW/X11 deps needed by habitat-sim build
    libxrandr-dev libxinerama-dev libxcursor-dev libxi-dev \
    ffmpeg vim \
    lsb-release gnupg2 \
    && rm -rf /var/lib/apt/lists/*

# Make python/pip the default commands
# NOTE: On Ubuntu 20.04 + ROS Noetic, we must keep the system Python (3.8) as default.
RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 && \
    python3 -m pip install --upgrade pip wheel && \
    # Pin setuptools to keep older extension builds happy
    python3 -m pip install "setuptools==65.7.0" "packaging==24.2"

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
RUN python3 -m pip install torch==2.0.1 torchvision==0.15.2 torchaudio==2.0.2 --index-url https://download.pytorch.org/whl/cu118

# --------------------------------------------------------
# 4. Install JupyterLab
# --------------------------------------------------------
RUN python3 -m pip install jupyterlab

# --------------------------------------------------------
# 5. Clone some project repository
# --------------------------------------------------------
WORKDIR /workspace

# --------------------------------------------------------
# 6. Install project dependencies
# --------------------------------------------------------
# 6.1 Install CMake via pip (your runtime had /usr/bin/cmake missing/overlaid)
RUN python3 -m pip install "cmake==3.27.9"

# 6.2 Clone ActiveSplat + submodules
RUN mkdir -p /workspace/activesplat_ws/src && \
    cd /workspace/activesplat_ws/src && \
    git clone https://github.com/Li-Yuetao/ActiveSplat.git && \
    cd ActiveSplat && \
    git submodule update --init --progress --recursive

# 6.3 Install diff-gaussian-rasterization (needs torch in current env; avoid build isolation)
RUN cd /workspace/activesplat_ws/src/ActiveSplat/submodules/diff-gaussian-rasterization && \
    python3 setup.py install && \
    python3 -m pip install --no-build-isolation .

# 6.4 Install Habitat-Lab/Baselines v0.2.3
RUN cd /workspace/activesplat_ws/src/ActiveSplat/submodules/habitat/habitat-lab && \
    git checkout tags/v0.2.3 && \
    python3 -m pip install -e habitat-lab && \
    python3 -m pip install -e habitat-baselines

# 6.5 Python runtime deps that easy_install choked on (matplotlib)
RUN python3 -m pip install "matplotlib==3.7.5"

# 6.6 Build/Install habitat-sim v0.2.3 with CUDA
#     - First build via setup.py (as in README)
#     - Then ensure it's importable in our /usr/local python by pip install --no-build-isolation .
RUN cd /workspace/activesplat_ws/src/ActiveSplat/submodules/habitat/habitat-sim && \
    git checkout tags/v0.2.3 && \
    git submodule update --init --progress --recursive && \
    rm -rf build && \
    export PATH="/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" && \
    export MAX_JOBS=2 && \
    export CMAKE_BUILD_PARALLEL_LEVEL=2 && \
    export CMAKE_ARGS="-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=86" && \
    python3 setup.py install --with-cuda && \
    python3 -m pip install --no-build-isolation .

# 6.7 Install ROS Noetic + catkin + required ROS deps (cv_bridge, tf, etc.)
RUN apt-get update && \
    sh -c 'echo "deb http://packages.ros.org/ros/ubuntu $(lsb_release -sc) main" > /etc/apt/sources.list.d/ros1-latest.list' && \
    curl -sSL https://raw.githubusercontent.com/ros/rosdistro/master/ros.asc | apt-key add - && \
    apt-get update && \
    apt-get install -y \
      ros-noetic-ros-base \
      ros-noetic-catkin \
      ros-noetic-cv-bridge \
      ros-noetic-image-transport \
      ros-noetic-sensor-msgs \
      ros-noetic-tf \
      # roslaunch requires netifaces; on focal this is built for system Python 3.8
      python3-netifaces \
    && rm -rf /var/lib/apt/lists/*

# 6.8 Build catkin workspace (activesplat package)
RUN source /opt/ros/noetic/setup.bash && \
    cd /workspace/activesplat_ws && \
    catkin_make -DPYTHON_EXECUTABLE=/usr/bin/python3

# 6.9 Convenience: auto-source ROS + workspace for interactive shells
RUN echo "export PATH=/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:\$PATH" >> /root/.bashrc && \
    echo "source /opt/ros/noetic/setup.bash" >> /root/.bashrc && \
    echo "source /workspace/activesplat_ws/devel/setup.bash" >> /root/.bashrc && \
    echo "cd /workspace/activesplat_ws/src/ActiveSplat" >> /root/.bashrc

# --------------------------------------------------------
# 7. Default working directory and entrypoint
# --------------------------------------------------------
# Start Script
COPY scripts/start.sh /start.sh
RUN chmod 755 /start.sh
WORKDIR /workspace/activesplat_ws/src/ActiveSplat
CMD ["/start.sh"]
