FROM debian:bookworm-slim

# Install curl to download the binary
RUN apt-get update && apt-get install -y curl && rm -rf /var/lib/apt/lists/*

# --- FileBrowser install ---
# Install latest tested version tested for this project (v2.63.5), pinned for reproducibility..
RUN curl -fsSL https://github.com/filebrowser/filebrowser/releases/download/v2.63.5/linux-amd64-filebrowser.tar.gz \
    | tar -xz -C /usr/local/bin filebrowser \
    && chmod +x /usr/local/bin/filebrowser

# Alternative -- always install the newest upstream release (not pinned, may be untested).
# RUN curl -fsSL https://raw.githubusercontent.com/filebrowser/get/master/get.sh | bash

# Expose the port so we can access it
EXPOSE 8081

# Run FileBrowser pointing to our mapped directories
CMD ["filebrowser", "-d", "/config/filebrowser.db", "-r", "/data", "-a", "0.0.0.0", "-p", "8081"]