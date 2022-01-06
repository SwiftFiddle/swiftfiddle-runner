FROM denoland/deno:ubuntu-1.17.2

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update && apt-get -q dist-upgrade -y \
    && apt-get install -y --no-install-recommends \
      ca-certificates curl gnupg lsb-release \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /usr/share/keyrings/docker-archive-keyring.gpg \
    && echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/docker-archive-keyring.gpg] https://download.docker.com/linux/ubuntu \
      $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
    && rm -r /var/lib/apt/lists/*

WORKDIR /app

COPY deps.ts .
RUN deno cache --unstable deps.ts

ADD . .
RUN deno cache --unstable main.ts

EXPOSE 8080
CMD ["run", "--allow-env", "--allow-net", "--allow-run", "--allow-read", "--allow-write", "--unstable", "main.ts"]
