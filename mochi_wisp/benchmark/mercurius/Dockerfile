FROM node:22-alpine
WORKDIR /app
COPY package.json .
RUN npm install
COPY index.js .
EXPOSE 4001
CMD ["node", "index.js"]
