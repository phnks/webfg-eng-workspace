# Multi-stage Dockerfile for agent containers
FROM ubuntu:24.04 AS base

# Prevent interactive prompts during package installation
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=UTC

# Install base system packages
RUN apt-get update || true && apt-get install -y --allow-unauthenticated \
    curl \
    wget \
    git \
    build-essential \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    sudo \
    vim \
    nano \
    tmux \
    htop \
    net-tools \
    iputils-ping \
    jq \
    unzip \
    python3 \
    python3-pip \
    python3-venv \
    python3-dev \
    openssh-client \
    procps \
    && rm -rf /var/lib/apt/lists/*

# Install Node.js v22
RUN curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2
RUN curl "https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip" -o "awscliv2.zip" \
    && unzip awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

# Install GitHub CLI
RUN curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg | dd of=/usr/share/keyrings/githubcli-archive-keyring.gpg \
    && chmod go+r /usr/share/keyrings/githubcli-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | tee /etc/apt/sources.list.d/github-cli.list > /dev/null \
    && apt-get update \
    && apt-get install -y gh \
    && rm -rf /var/lib/apt/lists/*

# Install Docker CLI (for Docker-in-Docker support if needed)
RUN curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update \
    && apt-get install -y docker-ce-cli \
    && rm -rf /var/lib/apt/lists/*

# Create base directory structure
RUN mkdir -p /app /workspace /home/agent

# Set working directory
WORKDIR /home/agent

# Stage for AutoGen agent
FROM base AS autogen-agent

# Create user for the agent
ARG USER_UID=1000
ARG USER_GID=$USER_UID

# Check if user/group with UID/GID already exist and handle accordingly
RUN if ! getent group $USER_GID >/dev/null 2>&1; then \
        groupadd --gid $USER_GID agent; \
    else \
        groupadd agent; \
    fi \
    && if ! getent passwd $USER_UID >/dev/null 2>&1; then \
        useradd --uid $USER_UID --gid agent -m -s /bin/bash agent; \
    else \
        useradd --gid agent -m -s /bin/bash agent; \
    fi \
    && echo "agent ALL=(ALL) NOPASSWD:ALL" >> /etc/sudoers.d/agent \
    && chmod 0440 /etc/sudoers.d/agent \
    && mkdir -p /home/agent/workspace \
    && chown -R agent:agent /home/agent

# Copy autogen agent files with proper ownership
COPY --chown=agent:agent autogen_agent /home/agent/autogen_agent
COPY --chown=agent:agent mcp_servers/discord-mcp /home/agent/discord-mcp
COPY --chown=agent:agent vm_cli /home/agent/vm_cli

# Install Python dependencies
WORKDIR /home/agent/autogen_agent
RUN python3 -m venv venv \
    && . venv/bin/activate \
    && pip install --upgrade pip \
    && pip install -r requirements.txt

# Install Discord MCP dependencies
WORKDIR /home/agent/discord-mcp
RUN npm ci && npm run build

# Install devchat CLI
WORKDIR /home/agent/vm_cli
RUN npm ci && npm link

# Copy setup script
COPY --chown=agent:agent docker/scripts/setup_container.sh /usr/local/bin/setup_container.sh
RUN chmod +x /usr/local/bin/setup_container.sh

# Switch to non-root user
USER agent
WORKDIR /home/agent

# Run setup script
RUN AGENT_TYPE=autogen /usr/local/bin/setup_container.sh

# Copy entrypoint script
COPY --chown=root:root docker/docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN sudo chmod +x /usr/local/bin/docker-entrypoint.sh

# Set entrypoint
ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]

# Default command (can be overridden)
CMD ["/bin/bash"]