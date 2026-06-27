FROM node:20-slim

# kubectl
ARG KUBECTL_VERSION=v1.34.1
RUN apt-get update && apt-get install -y curl ca-certificates bash && \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
      -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# talosctl
ARG TALOS_VERSION=v1.12.6
RUN curl -fsSL https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64 \
      -o /usr/local/bin/talosctl && chmod +x /usr/local/bin/talosctl

# openclaw
ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION}

# Non-root user for the gateway process
RUN useradd -m -u 1000 openclaw
USER openclaw
WORKDIR /home/openclaw

ENV HOME=/home/openclaw

EXPOSE 18789

CMD ["openclaw", "gateway", "--port", "18789"]
