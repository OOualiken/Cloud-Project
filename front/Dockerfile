FROM node:10.13.0-alpine

# Create app directory
WORKDIR /app

# Install app dependencies
COPY package*.json ./
RUN npm install

# Bundle app source
COPY . ./
RUN npm run build

EXPOSE 80
CMD [ "npm", "run", "start" ]
