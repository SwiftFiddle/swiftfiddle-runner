FROM swift:5.4-focal as build

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update && apt-get -q dist-upgrade -y \
    && apt-get install -y --no-install-recommends libsqlite3-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /build
COPY ./Package.* ./
RUN swift package resolve
COPY . .
RUN swift build -c release

WORKDIR /staging
RUN cp "$(swift build --package-path /build -c release --show-bin-path)/Run" ./ \
    && mv /build/Resources ./Resources && chmod -R a-w ./Resources \
    && cp /build/entrypoint.sh .

FROM swift:5.4-focal-slim

RUN export DEBIAN_FRONTEND=noninteractive DEBCONF_NONINTERACTIVE_SEEN=true \
    && apt-get -q update && apt-get -q dist-upgrade -y \
    && apt-get update && apt-get install -y --no-install-recommends \
    apt-transport-https ca-certificates curl gnupg-agent software-properties-common \
    && curl -fsSL https://download.docker.com/linux/ubuntu/gpg | apt-key add - \ 
    && add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable" \
    && apt-get update && apt-get install -y --no-install-recommends docker-ce docker-ce-cli containerd.io \
    && rm -r /var/lib/apt/lists/*

WORKDIR /app
COPY --from=build /staging /app

EXPOSE 8080

ARG username
ARG access_token
ARG version
ENV DOCKER_HUB_USERNAME=${username}
ENV DOCKER_HUB_ACCESS_TOKEN=${access_token}
ENV RUNNER_VERSIONS=${versions}
ENTRYPOINT ["/bin/bash", "entrypoint.sh"]
CMD ["serve", "--env", "production", "--hostname", "0.0.0.0", "--port", "8080"]
