# syntax=docker/dockerfile:1.7
FROM ubuntu:24.04

RUN apt-get update && apt-get install -y \
    ca-certificates curl gnupg lsb-release \
    openssh-server sudo \
 && rm -rf /var/lib/apt/lists/*

# Install Docker CLI only. The daemon is expected on the host.
RUN install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg \
 && chmod a+r /etc/apt/keyrings/docker.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo ${VERSION_CODENAME}) stable" > /etc/apt/sources.list.d/docker.list \
 && apt-get update \
 && apt-get install -y docker-ce-cli docker-buildx-plugin docker-compose-plugin \
 && rm -rf /var/lib/apt/lists/*

# SSH needs this dir
RUN mkdir -p /var/run/sshd

# Create a user (change as you like)
ARG USERNAME
ENV DEV_USERNAME=${USERNAME}
RUN --mount=type=secret,id=user_password \
 useradd -m -s /bin/bash ${USERNAME} \
 && USER_PASSWORD="$(cat /run/secrets/user_password)" \
 && echo "${USERNAME}:${USER_PASSWORD}" | chpasswd \
 && unset USER_PASSWORD \
 && usermod -aG sudo ${USERNAME}

# Allow password SSH (simple for local dev)
RUN sed -i 's/#PasswordAuthentication yes/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/PasswordAuthentication no/PasswordAuthentication yes/' /etc/ssh/sshd_config \
 && sed -i 's/#PermitRootLogin prohibit-password/PermitRootLogin no/' /etc/ssh/sshd_config

COPY scripts/onboard.sh /usr/local/bin/onboard
COPY scripts/onboard-banner.sh /etc/profile.d/onboard-banner.sh
COPY scripts/start-sshd.sh /usr/local/bin/start-sshd
RUN chmod 755 /usr/local/bin/onboard /etc/profile.d/onboard-banner.sh /usr/local/bin/start-sshd

EXPOSE 22

CMD ["/usr/local/bin/start-sshd"]
