FROM debian:trixie-slim
# We move from bookworm to trixie because the N150 (Twin Lake) is very new silicon:
# its iGPU needs a recent Intel media driver that bookworm does not have.

# Enable the non-free components (the Intel encode driver lives there).
RUN sed -i 's/Components: main/Components: main contrib non-free non-free-firmware/' /etc/apt/sources.list.d/debian.sources

# Install ffmpeg, inotify-tools, docker (to restart the VPN(WireGuard)) and the Intel iGPU driver + vainfo (for the vaapi hardware encoder)
RUN apt-get update && apt-get install -y inotify-tools ffmpeg bash docker.io grep intel-media-va-driver-non-free vainfo && rm -rf /var/lib/apt/lists/*

# Copy all scripts to /app
COPY . /app/
RUN chmod +x /app/*.sh

# Run the main script
CMD ["/app/entrypoint.sh"]