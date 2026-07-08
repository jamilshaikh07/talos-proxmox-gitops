FROM node:22-slim

# kubectl
ARG KUBECTL_VERSION=v1.34.1
RUN apt-get update && apt-get install -y curl ca-certificates bash bsdextrautils && \
    curl -fsSL https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl \
      -o /usr/local/bin/kubectl && chmod +x /usr/local/bin/kubectl

# talosctl
ARG TALOS_VERSION=v1.12.6
RUN curl -fsSL https://github.com/siderolabs/talos/releases/download/${TALOS_VERSION}/talosctl-linux-amd64 \
      -o /usr/local/bin/talosctl && chmod +x /usr/local/bin/talosctl

# openclaw
ARG OPENCLAW_VERSION=latest
RUN npm install -g openclaw@${OPENCLAW_VERSION} @openclaw/mattermost@latest

# node:22-slim already has a 'node' user at uid 1000 — reuse it
USER node
WORKDIR /home/node

ENV HOME=/home/node

EXPOSE 18789

CMD ["openclaw", "gateway", "--port", "18789"]
