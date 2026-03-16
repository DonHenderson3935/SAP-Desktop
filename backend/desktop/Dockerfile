FROM lscr.io/linuxserver/webtop:ubuntu-xfce

# hadolint ignore=DL3008,DL3009
RUN apt-get update \
    && apt-get install -y --no-install-recommends \
       curl \
       gnupg \
       ca-certificates \
    && install -d /etc/apt/keyrings \
    && curl -fsSL https://dl.google.com/linux/linux_signing_key.pub \
       | gpg --dearmor -o /etc/apt/keyrings/google-chrome.gpg \
    && echo "deb [arch=amd64 signed-by=/etc/apt/keyrings/google-chrome.gpg] \
       https://dl.google.com/linux/chrome/deb/ stable main" \
       > /etc/apt/sources.list.d/google-chrome.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       google-chrome-stable \
       firefox \
    && rm -rf /var/lib/apt/lists/* \
    && mkdir -p /defaults/Desktop \
    && printf '[Desktop Entry]\nType=Application\nName=Google Chrome\nExec=google-chrome-stable --no-sandbox --disable-dev-shm-usage --disable-gpu --disable-software-rasterizer --disable-oom-score-adjustment %%U\nIcon=google-chrome\nCategories=Network;WebBrowser;\n' \
       > /defaults/Desktop/chrome.desktop \
    && printf '[Desktop Entry]\nType=Application\nName=Firefox\nExec=firefox %%U\nIcon=firefox\nCategories=Network;WebBrowser;\n' \
       > /defaults/Desktop/firefox.desktop \
    && chmod +x /defaults/Desktop/chrome.desktop /defaults/Desktop/firefox.desktop
