#!/bin/bash

# Docker File Generator Installer
# This script installs the Dockerfile generator utility

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Installing Dockerfile Generator...${NC}"

# Create the directory for the script
INSTALL_DIR="$HOME/.dockerfile-generator"
mkdir -p "$INSTALL_DIR"

# Create the main script
SCRIPT_PATH="$INSTALL_DIR/dockerfile-generator.js"
cat > "$SCRIPT_PATH" << 'EOF'
#!/usr/bin/env node

const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Get app directory from command line argument
const appPath = process.argv[2];

if (!appPath) {
  console.error('Error: Please provide a path to your application.');
  console.log('Usage: dockerfile-gen /path/to/your/app');
  process.exit(1);
}

// Normalize path and check if it exists
const absolutePath = path.resolve(appPath);
if (!fs.existsSync(absolutePath)) {
  console.error(`Error: Directory does not exist: ${absolutePath}`);
  process.exit(1);
}

// Determine app type based on files present
function detectAppType() {
  // Check for package.json (Node.js app)
  const hasPackageJson = fs.existsSync(path.join(absolutePath, 'package.json'));
  
  if (hasPackageJson) {
    // Read package.json to get more info
    const packageJsonPath = path.join(absolutePath, 'package.json');
    const packageJson = JSON.parse(fs.readFileSync(packageJsonPath, 'utf8'));
    
    // Check dependencies
    const deps = { ...packageJson.dependencies, ...packageJson.devDependencies };
    
    if (deps.react) {
      return {
        type: 'react',
        packageJson
      };
    }
    
    if (deps.express || deps.koa || deps.hapi || deps.fastify) {
      return {
        type: 'node',
        packageJson
      };
    }
    
    // Default Node.js
    return {
      type: 'node',
      packageJson
    };
  }
  
  // Check for Python
  const hasPythonFiles = fs.readdirSync(absolutePath).some(file => file.endsWith('.py'));
  const hasRequirements = fs.existsSync(path.join(absolutePath, 'requirements.txt'));
  
  if (hasPythonFiles || hasRequirements) {
    return {
      type: 'python'
    };
  }
  
  // Default to generic
  return {
    type: 'generic'
  };
}

// Generate Dockerfile based on app type
function generateDockerfile(appType) {
  let dockerfileContent = '';
  
  switch (appType.type) {
    case 'react':
      dockerfileContent = generateReactDockerfile(appType);
      break;
    case 'node':
      dockerfileContent = generateNodeDockerfile(appType);
      break;
    case 'python':
      dockerfileContent = generatePythonDockerfile();
      break;
    default:
      dockerfileContent = generateGenericDockerfile();
  }
  
  return dockerfileContent;
}

function generateReactDockerfile(appType) {
  // Find scripts from package.json
  const startScript = appType.packageJson.scripts?.start || 'react-scripts start';
  const buildScript = appType.packageJson.scripts?.build || 'react-scripts build';
  
  return `# Multi-stage build for React application
FROM node:16-alpine AS build

# Set working directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy the rest of the code
COPY . .

# Build the application
RUN npm run ${buildScript.split(' ')[0]}

# Production stage
FROM nginx:alpine AS production

# Copy build files from previous stage
COPY --from=build /app/build /usr/share/nginx/html

# Copy nginx configuration if it exists
COPY nginx.conf /etc/nginx/conf.d/default.conf 2>/dev/null || :

# Expose port
EXPOSE 80

# Start Nginx
CMD ["nginx", "-g", "daemon off;"]
`;
}

function generateNodeDockerfile(appType) {
  // Find start script from package.json
  const startScript = appType.packageJson.scripts?.start || 'node server.js';
  const devScript = appType.packageJson.scripts?.dev || appType.packageJson.scripts?.develop;
  
  // Determine main file and port
  const mainFile = appType.packageJson.main || 'index.js';
  let port = 3000; // Default port
  
  // Try to find port in package.json scripts
  if (appType.packageJson.scripts) {
    const scriptValues = Object.values(appType.packageJson.scripts).join(' ');
    const portMatch = scriptValues.match(/PORT=(\d+)/);
    if (portMatch) {
      port = portMatch[1];
    }
  }
  
  return `# Dockerfile for Node.js application
FROM node:16-alpine

# Create app directory
WORKDIR /app

# Copy package.json and package-lock.json
COPY package*.json ./

# Install dependencies
RUN npm ci

# Copy the rest of the code
COPY . .

# Expose the port the app will run on
EXPOSE ${port}

# Start the application
CMD ["npm", "run", "${startScript.split(' ')[0]}"]
`;
}

function generatePythonDockerfile() {
  return `# Dockerfile for Python application
FROM python:3.9-slim

# Set working directory
WORKDIR /app

# Copy requirements
COPY requirements.txt .

# Install dependencies
RUN pip install --no-cache-dir -r requirements.txt

# Copy the rest of the code
COPY . .

# Expose port
EXPOSE 8000

# Start the application
CMD ["python", "app.py"]
`;
}

function generateGenericDockerfile() {
  return `# Generic Dockerfile
FROM ubuntu:20.04

# Set working directory
WORKDIR /app

# Copy application files
COPY . .

# Install dependencies
# RUN apt-get update && apt-get install -y some-package

# Expose port
# EXPOSE 8080

# Start the application
# CMD ["./start.sh"]
`;
}

// Generate .dockerignore file
function generateDockerignore(appType) {
  let dockerignoreContent = `# .dockerignore
.git
.gitignore
.github
.vscode
.idea
*.md
!README.md
`;

  switch (appType.type) {
    case 'react':
    case 'node':
      dockerignoreContent += `node_modules
npm-debug.log
Dockerfile
.dockerignore
build
dist
coverage
`;
      break;
    case 'python':
      dockerignoreContent += `__pycache__/
*.py[cod]
*$py.class
*.so
.Python
env/
build/
develop-eggs/
dist/
downloads/
eggs/
.eggs/
lib/
lib64/
parts/
sdist/
var/
*.egg-info/
.installed.cfg
*.egg
venv/
ENV/
`;
      break;
  }

  return dockerignoreContent;
}

// Main execution
const appType = detectAppType();
console.log(`Detected application type: ${appType.type}`);

// Generate Dockerfile content
const dockerfileContent = generateDockerfile(appType);
const dockerfilePath = path.join(absolutePath, 'Dockerfile');

// Write Dockerfile
fs.writeFileSync(dockerfilePath, dockerfileContent);
console.log(`Created Dockerfile at: ${dockerfilePath}`);

// Generate .dockerignore
const dockerignoreContent = generateDockerignore(appType);
const dockerignorePath = path.join(absolutePath, '.dockerignore');

// Write .dockerignore
fs.writeFileSync(dockerignorePath, dockerignoreContent);
console.log(`Created .dockerignore at: ${dockerignorePath}`);

// Optional: Try to create a sample docker-compose file
function generateDockerCompose(appType) {
  let port = '3000';
  
  if (appType.type === 'react') {
    port = '80';
  } else if (appType.type === 'python') {
    port = '8000';
  }
  
  const appName = path.basename(absolutePath).toLowerCase().replace(/[^a-z0-9]/g, '-');
  
  return `version: '3'
services:
  ${appName}:
    build: .
    ports:
      - "${port}:${port}"
    volumes:
      - .:/app
    # environment:
    #   - NODE_ENV=development
`;
}

// Write docker-compose.yml
const dockerComposeContent = generateDockerCompose(appType);
const dockerComposePath = path.join(absolutePath, 'docker-compose.yml');
fs.writeFileSync(dockerComposePath, dockerComposeContent);
console.log(`Created docker-compose.yml at: ${dockerComposePath}`);

console.log('\nDockerization complete! You can now build and run your Docker container with:');
console.log(`  cd ${appPath}`);
console.log('  docker build -t my-app .');
console.log('  docker run -p 3000:3000 my-app');
console.log('\nOr use Docker Compose:');
console.log('  docker-compose up');
EOF

# Create executable
chmod +x "$SCRIPT_PATH"

# Create symlink in /usr/local/bin or ~/.local/bin
if [ -d "/usr/local/bin" ] && [ -w "/usr/local/bin" ]; then
    # Create global symlink if /usr/local/bin is writable
    ln -sf "$SCRIPT_PATH" "/usr/local/bin/dockerfile-gen"
    echo -e "${GREEN}Installed globally to /usr/local/bin/dockerfile-gen${NC}"
else
    # Create user symlink
    mkdir -p "$HOME/.local/bin"
    ln -sf "$SCRIPT_PATH" "$HOME/.local/bin/dockerfile-gen"
    
    # Add to PATH if not already there
    if [[ ":$PATH:" != *":$HOME/.local/bin:"* ]]; then
        echo -e "${YELLOW}Adding ~/.local/bin to PATH in your profile${NC}"
        
        # Determine shell profile file
        if [ -f "$HOME/.bash_profile" ]; then
            PROFILE="$HOME/.bash_profile"
        elif [ -f "$HOME/.profile" ]; then
            PROFILE="$HOME/.profile"
        elif [ -f "$HOME/.bashrc" ]; then
            PROFILE="$HOME/.bashrc"
        elif [ -f "$HOME/.zshrc" ]; then
            PROFILE="$HOME/.zshrc"
        else
            PROFILE="$HOME/.bash_profile"
            touch "$PROFILE"
        fi
        
        # Add to PATH in profile
        echo 'export PATH="$HOME/.local/bin:$PATH"' >> "$PROFILE"
        echo -e "${YELLOW}Added to $PROFILE. Please restart your terminal or run:${NC}"
        echo -e "${YELLOW}source $PROFILE${NC}"
    fi
    
    echo -e "${GREEN}Installed locally to ~/.local/bin/dockerfile-gen${NC}"
fi

echo -e "\n${GREEN}Installation complete!${NC}"
echo -e "You can now run the tool with: ${YELLOW}dockerfile-gen /path/to/your/app${NC}"
