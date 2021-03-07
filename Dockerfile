FROM nvidia/cuda:11.1.1-devel-ubuntu20.04

ENV DEBIAN_FRONTEND=noninteractive

#### System package (uses Python 3.8)
RUN apt-get update -y && \
    apt-get install -y \
        git python3 python3-dev libpython3-dev  python3-pip sudo pdsh \
        htop llvm-9-dev tmux zstd software-properties-common build-essential autotools-dev \
        nfs-common pdsh cmake g++ gcc curl wget tmux less unzip htop iftop iotop ca-certificates ssh \
        rsync iputils-ping net-tools libcupti-dev && \
    update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.8 1 && \
    update-alternatives --install /usr/bin/python python /usr/bin/python3.8 1 && \
    update-alternatives --install /usr/bin/pip pip /usr/bin/pip3 1 && \
    pip install --upgrade pip && \
    pip install gpustat

### SSH
# Set password
RUN echo 'password' >> password.txt && \
    mkdir /var/run/sshd && \
    echo "root:`cat password.txt`" | chpasswd && \
    # Allow root login with password
    sed -i 's/PermitRootLogin without-password/PermitRootLogin yes/' /etc/ssh/sshd_config && \
    # Prevent user being kicked off after login
    sed -i 's@session\s*required\s*pam_loginuid.so@session optional pam_loginuid.so@g' /etc/pam.d/sshd && \
    echo 'AuthorizedKeysFile     .ssh/authorized_keys' >> /etc/ssh/sshd_config && \
    echo 'PasswordAuthentication yes' >> /etc/ssh/sshd_config && \
    # Clean up
    rm password.txt
# Expose SSH port
EXPOSE 22
# Add CUDA back to path during SSH
RUN echo "export PATH=$PATH:/usr/local/cuda/bin" >> /etc/profile
# Copy SSH script to set up LD_LIBRARY_PATH
COPY ssh.sh /opt/

#### User account
RUN useradd --create-home --uid 1000 --shell /bin/bash mchorse && \
    usermod -aG sudo mchorse && \
    echo "mchorse ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers

## SSH config and bashrc
RUN mkdir -p /home/mchorse/.ssh /job && \
    echo 'Host *' > /home/mchorse/.ssh/config && \
    echo '    StrictHostKeyChecking no' >> /home/mchorse/.ssh/config && \
    echo 'export PDSH_RCMD_TYPE=ssh' >> /home/mchorse/.bashrc && \
    echo 'export PATH=/home/mchorse/.local/bin:$PATH' >> /home/mchorse/.bashrc && \
    echo 'export PATH=/usr/local/mpi/bin:$PATH' >> /home/mchorse/.bashrc && \
    echo 'export LD_LIBRARY_PATH=/usr/local/lib:/usr/local/mpi/lib:/usr/local/mpi/lib64:$LD_LIBRARY_PATH' >> /home/mchorse/.bashrc

#### Python packages
RUN pip install torch==1.8.0+cu111

COPY requirements.txt $STAGE_DIR
RUN pip install -r $STAGE_DIR/requirements.txt
RUN pip install -e git+git://github.com/EleutherAI/DeeperSpeed.git@cac19a86b67e6e98b9dca37128bc01e50424d9e9#egg=deepspeed
RUN pip install -v --disable-pip-version-check --no-cache-dir --global-option="--cpp_ext" --global-option="--cuda_ext" git+https://github.com/NVIDIA/apex.git@e2083df5eb96643c61613b9df48dd4eea6b07690

# Clear staging
RUN mkdir -p /tmp && chmod 0777 /tmp

#### SWITCH TO mchorse USER
USER mchorse
WORKDIR /home/mchorse
ENV PATH="/home/mchorse/.local/bin:${PATH}"
