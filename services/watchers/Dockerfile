FROM debian:bookworm-slim

# Install ffmpeg, inotify-tools and docker (to restart the VPN(WireGuard))
RUN apt-get update && apt-get install -y inotify-tools ffmpeg bash docker.io grep && rm -rf /var/lib/apt/lists/*

# Copy all scripts to /app
COPY . /app/
RUN chmod +x /app/*.sh

# Run the main script
CMD ["/app/entrypoint.sh"]