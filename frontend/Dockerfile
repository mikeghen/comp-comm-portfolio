FROM node:18-alpine

# Install Python and build dependencies
RUN apk add --no-cache python3 make g++ gcc

# Install vite globally
RUN npm install -g vite

# Set working directory
WORKDIR /app

# Copy package files and install dependencies
COPY package*.json ./
RUN npm install

# Copy the rest of the application
COPY . .

# Build the application (in production)
# RUN npm run build

# Expose port 3000 (the port where Vite dev server runs)
EXPOSE 3000

# Environment variables to enable hot reloading
ENV CHOKIDAR_USEPOLLING=true
ENV HOST=0.0.0.0

# Start the development server
CMD ["npm", "start"]