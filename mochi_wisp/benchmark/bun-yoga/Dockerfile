FROM oven/bun:1-alpine
WORKDIR /app
COPY package.json .
RUN bun install
COPY index.js .
EXPOSE 4004
CMD ["bun", "run", "index.js"]
