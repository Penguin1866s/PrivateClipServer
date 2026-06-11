FROM debian:bookworm-slim

# Install WireGuard, iptables, and networking tools
RUN apt-get update && apt-get install -y wireguard-tools iptables iproute2 bash && rm -rf /var/lib/apt/lists/*

# Copy the initialization script
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

# The script handles config generation and keeps the container alive
CMD ["/entrypoint.sh"]