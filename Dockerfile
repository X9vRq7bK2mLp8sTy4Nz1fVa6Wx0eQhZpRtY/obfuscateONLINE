FROM node:18-bullseye

# install luajit and utilities
RUN apt-get update && apt-get install -y luajit unzip ca-certificates --no-install-recommends && \
    rm -rf /var/lib/apt/lists/*

WORKDIR /usr/src/app

# copy package and install node deps
COPY package.json package-lock.json* ./
RUN npm ci --only=production || npm install --production

# copy project files (including src and runner.lua and public)
COPY . .

# expose port
ENV PORT=3000
EXPOSE 3000

# start server
CMD ["npm", "start"]
