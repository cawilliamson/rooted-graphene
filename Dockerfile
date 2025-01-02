FROM ubuntu:latest

# set variables
ARG PUP_VERSION="0.4.0" \
    AVBROOT_VERSION="3.11.0" \
    CUSTOTA_TOOL_VERSION="5.4" \
    DEBIAN_FRONTEND=noninteractive

# install apt dependencies
RUN apt update && apt dist-upgrade -y && \
    apt install -y \
    bison \
    build-essential \
    curl \
    expect \
    flex \
    git \
    git-lfs \
    jq \
    libncurses-dev \
    libssl-dev \
    lz4 \
    openjdk-21-jdk-headless \
    python3 \
    python3-googleapi \
    python3-protobuf \
    rsync \
    ssh \
    unzip \
    yarnpkg \
    zip && \
    apt clean && \
    rm -rf /var/lib/apt/lists/*

# install avbroot
RUN curl -o /var/tmp/avbroot.zip -L "https://github.com/chenxiaolong/avbroot/releases/download/v${AVBROOT_VERSION}/avbroot-${AVBROOT_VERSION}-x86_64-unknown-linux-gnu.zip" && \
    unzip /var/tmp/avbroot.zip -d /usr/bin -x LICENSE README.md && \
    chmod +x /usr/bin/avbroot && \
    rm -f /var/tmp/avbroot.zip

# install custota-tool
RUN curl -o /var/tmp/custota-tool.zip -L "https://github.com/chenxiaolong/Custota/releases/download/v${CUSTOTA_TOOL_VERSION}/custota-tool-${CUSTOTA_TOOL_VERSION}-x86_64-unknown-linux-gnu.zip" && \
    unzip /var/tmp/custota-tool.zip -d /usr/bin && \
    chmod +x /usr/bin/custota-tool && \
    rm -f /var/tmp/custota-tool.zip

# install pup command
RUN curl -o /var/tmp/pup.zip -L "https://github.com/ericchiang/pup/releases/download/v${PUP_VERSION}/pup_v${PUP_VERSION}_linux_amd64.zip" && \
    unzip /var/tmp/pup.zip -d /usr/bin && \
    chmod +x /usr/bin/pup && \
    rm -f /var/tmp/pup.zip

    # install repo command
RUN curl -s https://storage.googleapis.com/git-repo-downloads/repo > /usr/bin/repo && \
    chmod +x /usr/bin/repo

# install libncurses5
RUN cd /var/tmp && \
    curl -O http://launchpadlibrarian.net/648013231/libtinfo5_6.4-2_amd64.deb && \
    dpkg -i libtinfo5_6.4-2_amd64.deb && \
    curl -LO http://launchpadlibrarian.net/648013227/libncurses5_6.4-2_amd64.deb && \
    dpkg -i libncurses5_6.4-2_amd64.deb && \
    rm -f ./*.deb

# configure git
RUN git config --global color.ui false && \
    git config --global user.email "androidbuild@localhost" && \
    git config --global user.name "Android Build"
