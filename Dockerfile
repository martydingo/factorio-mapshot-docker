FROM debian:bookworm
RUN apt update && apt install -y jq curl xz-utils xvfb
RUN MAPSHOT_VERSION=`curl -s https://api.github.com/repos/Palats/mapshot/releases/latest | jq .tag_name | sed 's/\"//g'` && curl -s -L -o /usr/local/bin/mapshot https://github.com/Palats/mapshot/releases/download/$MAPSHOT_VERSION/mapshot-linux && chmod +x /usr/local/bin/mapshot
RUN mkdir -p /mapshot
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh
ENTRYPOINT [ "/bin/bash", "-c", "/entrypoint.sh" ]