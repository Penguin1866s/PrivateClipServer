# Tested version (1.31.1).
FROM nginx:1.31.1-alpine

# Alternative -- always install the LATEST version.
# FROM nginx:alpine

COPY nginx.conf /etc/nginx/conf.d/default.conf
COPY injection_custom_progress_bar.js /branding/injection_custom_progress_bar.js