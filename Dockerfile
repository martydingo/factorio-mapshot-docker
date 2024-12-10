FROM debian:bookworm-slim

RUN apt update && apt install --yes \
        jq \
        curl \
        xz-utils \
        xvfb
RUN rm --recursive --force /var/lib/apt/lists/*

RUN MAPSHOT_VERSION="$(curl --silent https://api.github.com/repos/Palats/mapshot/releases/latest | jq --raw-output .tag_name)" && \
        curl --location --silent --output /usr/local/bin/mapshot "https://github.com/Palats/mapshot/releases/download/${MAPSHOT_VERSION}/mapshot-linux" && \
        chmod +x /usr/local/bin/mapshot

RUN groupadd --gid 1001 mapshot && \
        useradd --uid 1001 --gid 1001 --home /opt/mapshot --shell /usr/sbin/nologin mapshot && \
        mkdir --parents /opt/mapshot && \
        chown --recursive mapshot:mapshot /opt/mapshot

COPY src/entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh

USER mapshot

WORKDIR /opt/mapshot

ENTRYPOINT ["/bin/bash", "-ceuo", "pipefail", "/entrypoint.sh"]
