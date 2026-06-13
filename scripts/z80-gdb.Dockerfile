FROM debian:stable-slim
RUN apt-get update -qq && \
    apt-get install -y -qq --no-install-recommends gdb-multiarch && \
    rm -rf /var/lib/apt/lists/*
