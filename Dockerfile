FROM nvidia/cuda:11.8.0-devel-ubuntu20.04

SHELL ["/bin/bash", "-lc"]

ENV DEBIAN_FRONTEND=noninteractive \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DEFAULT_TIMEOUT=180 \
    PIP_RETRIES=10 \
    TORCH_CUDA_ARCH_LIST="8.6+PTX" \
    CMAKE_ARGS="-DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc -DCMAKE_CUDA_ARCHITECTURES=86" \
    PATH="/opt/conda/condabin:/opt/conda/bin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
    NVIDIA_VISIBLE_DEVICES=all \
    NVIDIA_DRIVER_CAPABILITIES=all

WORKDIR /opt

RUN apt-get update && apt-get install -y \
    software-properties-common \
    build-essential \
    git \
    wget \
    curl \
    ca-certificates \
    tmux \
    vim \
    ffmpeg \
    pkg-config \
    ninja-build \
    openssh-server \
    nginx \
    lsb-release \
    gnupg2 \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libglvnd0 \
    libglvnd-dev \
    libegl1 \
    libegl1-mesa-dev \
    libgl1-mesa-dev \
    libx11-6 \
    libxext6 \
    libxi6 \
    libxrender1 \
    libxrandr-dev \
    libxinerama-dev \
    libxcursor-dev \
    libxi-dev \
    python3 \
    python3-dev \
    python3-pip \
    python3-venv \
    python3-netifaces \
    && rm -rf /var/lib/apt/lists/*

RUN update-alternatives --install /usr/bin/python python /usr/bin/python3 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1

RUN wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh && \
    bash /tmp/miniconda.sh -b -p /opt/conda && \
    rm -f /tmp/miniconda.sh && \
    source /opt/conda/etc/profile.d/conda.sh && \
    conda config --system --set auto_activate_base false

RUN rm -f /etc/ssh/ssh_host_*

COPY proxy/nginx.conf /etc/nginx/nginx.conf
COPY proxy/readme.html /usr/share/nginx/html/readme.html

RUN mkdir -p /opt/activesplat_ws/src && \
    cd /opt/activesplat_ws/src && \
    git clone https://github.com/Li-Yuetao/ActiveSplat.git && \
    cd ActiveSplat && \
    git submodule update --init --progress --recursive

WORKDIR /opt/activesplat_ws/src/ActiveSplat

RUN source /opt/conda/etc/profile.d/conda.sh && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main && \
    conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r && \
    conda env create -f environment.yaml

ENV PATH="/opt/conda/envs/ActiveSplat/bin:/opt/conda/condabin:/usr/local/cuda/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

RUN /opt/conda/envs/ActiveSplat/bin/python -m pip install --upgrade pip && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install \
      "setuptools==65.7.0" \
      "packaging==24.2" \
      "cmake==3.27.9" && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install \
      torch==2.0.1+cu118 \
      torchvision==0.15.2+cu118 \
      torchaudio==2.0.2+cu118 \
      --extra-index-url https://download.pytorch.org/whl/cu118 && \
    /opt/conda/envs/ActiveSplat/bin/python -c "import torch; print(torch.__version__, torch.version.cuda)" && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install -r requirements.txt && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install \
      jupyterlab \
      open3d \
      trimesh \
      "matplotlib==3.7.5"

RUN cd /opt/activesplat_ws/src/ActiveSplat/submodules/diff-gaussian-rasterization && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install --no-build-isolation .

RUN cd /opt/activesplat_ws/src/ActiveSplat/submodules/habitat/habitat-lab && \
    git checkout tags/v0.2.3 && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install -e habitat-lab && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install -e habitat-baselines

RUN cd /opt/activesplat_ws/src/ActiveSplat/submodules/habitat/habitat-sim && \
    git checkout tags/v0.2.3 && \
    git submodule update --init --progress --recursive && \
    export MAX_JOBS=2 && \
    export CMAKE_BUILD_PARALLEL_LEVEL=2 && \
    /opt/conda/envs/ActiveSplat/bin/python setup.py install --with-cuda && \
    /opt/conda/envs/ActiveSplat/bin/python -c "import habitat_sim; print(habitat_sim.__file__)"

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
    && rm -rf /var/lib/apt/lists/*

RUN /opt/conda/envs/ActiveSplat/bin/python -m pip uninstall -y empy || true && \
    /opt/conda/envs/ActiveSplat/bin/python -m pip install \
      "empy==3.3.4" \
      catkin_pkg \
      rospkg

WORKDIR /opt/activesplat_ws

RUN source /opt/ros/noetic/setup.bash && \
    catkin_make -DPYTHON_EXECUTABLE=/opt/conda/envs/ActiveSplat/bin/python

RUN echo 'source /opt/conda/etc/profile.d/conda.sh' >> /root/.bashrc && \
    echo 'conda activate ActiveSplat' >> /root/.bashrc && \
    echo 'source /opt/ros/noetic/setup.bash' >> /root/.bashrc && \
    echo 'source /opt/activesplat_ws/devel/setup.bash' >> /root/.bashrc && \
    echo 'cd /opt/activesplat_ws/src/ActiveSplat' >> /root/.bashrc

COPY scripts/start.sh /start.sh
RUN chmod 755 /start.sh

WORKDIR /opt/activesplat_ws/src/ActiveSplat

CMD ["/start.sh"]