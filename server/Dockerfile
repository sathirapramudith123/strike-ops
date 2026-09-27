# Dedicated server image. Build the "Linux Server" export first
# (tools/build_release.sh), then from the repository root:
#   docker build -f server/Dockerfile -t fpsgame-server builds/server
#   docker run -d -p 7777:7777/udp --name fpsgame fpsgame-server --mode tdm --map warehouse
FROM debian:bookworm-slim
RUN useradd --create-home --shell /usr/sbin/nologin fps
WORKDIR /home/fps/server
COPY --chown=fps:fps FPSGame-server.x86_64 libopus_voice.linux.x86_64.so THIRD_PARTY_LICENSES.txt run_server.sh ./
USER fps
EXPOSE 7777/udp
ENTRYPOINT ["./run_server.sh"]
CMD ["--port", "7777", "--max-players", "16", "--mode", "ffa"]
