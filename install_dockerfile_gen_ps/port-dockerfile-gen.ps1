# Simple PowerShell Dockerfile Generator
# Usage: powershell -ExecutionPolicy Bypass -File .\dockerfile-gen.ps1 C:\path\to\your\app

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$AppPath
)

# Check if path exists
if (-not (Test-Path $AppPath)) {
    Write-Host "Error: Directory does not exist: $AppPath" -ForegroundColor Red
    exit 1
}

# Get absolute path
$absolutePath = Resolve-Path $AppPath

# Output with color
function Write-ColorText {
    param (
        [string]$Text,
        [string]$Color = "White"
    )
    Write-Host $Text -ForegroundColor $Color
}

# Detect app type
$appType = "generic"
$packageJson = $null

# Check for package.json (Node.js app)
$packageJsonPath = Join-Path -Path $absolutePath -ChildPath "package.json"
if (Test-Path $packageJsonPath) {
    $packageJsonContent = Get-Content -Path $packageJsonPath -Raw
    $packageJson = $packageJsonContent | ConvertFrom-Json
    
    # Check dependencies
    $hasDeps = $false
    $hasReact = $false
    $hasNodeFramework = $false
    
    if ($packageJson.dependencies -ne $null) {
        $hasDeps = $true
        if ($packageJson.dependencies.react -ne $null) {
            $hasReact = $true
        }
        if (($packageJson.dependencies.express -ne $null) -or
            ($packageJson.dependencies.koa -ne $null) -or
            ($packageJson.dependencies.hapi -ne $null) -or
            ($packageJson.dependencies.fastify -ne $null)) {
            $hasNodeFramework = $true
        }
    }
    
    if ($packageJson.devDependencies -ne $null) {
        $hasDeps = $true
        if ($packageJson.devDependencies.react -ne $null) {
            $hasReact = $true
        }
        if (($packageJson.devDependencies.express -ne $null) -or
            ($packageJson.devDependencies.koa -ne $null) -or
            ($packageJson.devDependencies.hapi -ne $null) -or
            ($packageJson.devDependencies.fastify -ne $null)) {
            $hasNodeFramework = $true
        }
    }
    
    if ($hasReact) {
        $appType = "react"
    } elseif ($hasNodeFramework) {
        $appType = "node"
    } elseif ($hasDeps) {
        $appType = "node"
    }
} else {
    # Check for Python
    $pythonFiles = Get-ChildItem -Path $absolutePath -Filter "*.py" -File
    $requirementsFile = Join-Path -Path $absolutePath -ChildPath "requirements.txt"
    
    if (($pythonFiles.Count -gt 0) -or (Test-Path $requirementsFile)) {
        $appType = "python"
    }
}

Write-ColorText "Detected application type: $appType" "Cyan"

# Create Dockerfile based on app type
$dockerfileContent = ""

if ($appType -eq "react") {
    # Find scripts from package.json
    $startScript = "react-scripts start"
    $buildScript = "react-scripts build"
    
    if ($packageJson.scripts -ne $null) {
        if ($packageJson.scripts.start -ne $null) {
            $startScript = $packageJson.scripts.start
        }
        if ($packageJson.scripts.build -ne $null) {
            $buildScript = $packageJson.scripts.build
        }
    }
    
    $buildCmd = ($buildScript -split ' ')[0]
    
    $dockerfileContent = @"
# Multi-stage build for React application
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
RUN npm run $buildCmd

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
"@
} elseif ($appType -eq "node") {
    # Find start script from package.json
    $startScript = "node server.js"
    $port = 3000
    
    if ($packageJson.scripts -ne $null -and $packageJson.scripts.start -ne $null) {
        $startScript = $packageJson.scripts.start
        
        # Try to find port in scripts
        $allScripts = $packageJson.scripts | Out-String
        if ($allScripts -match "PORT=(\d+)") {
            $port = $matches[1]
        }
    }
    
    $startCmd = ($startScript -split ' ')[0]
    
    $dockerfileContent = @"
# Dockerfile for Node.js application
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
EXPOSE $port

# Start the application
CMD ["npm", "run", "$startCmd"]
"@
} elseif ($appType -eq "python") {
    $dockerfileContent = @"
# Dockerfile for Python application
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
"@
} else {
    $dockerfileContent = @"
# Generic Dockerfile
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
"@
}

# Create .dockerignore content
$dockerignoreContent = @"
# .dockerignore
.git
.gitignore
.github
.vscode
.idea
*.md
!README.md
"@

if ($appType -eq "react" -or $appType -eq "node") {
    $dockerignoreContent += @"

node_modules
npm-debug.log
Dockerfile
.dockerignore
build
dist
coverage
"@
} elseif ($appType -eq "python") {
    $dockerignoreContent += @"

__pycache__/
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
"@
}

# Create docker-compose.yml content
$port = "3000"
if ($appType -eq "react") {
    $port = "80"
} elseif ($appType -eq "python") {
    $port = "8000"
}

$appName = (Get-Item $absolutePath).Name.ToLower() -replace '[^a-z0-9]', '-'

$dockerComposeContent = @"
version: '3'
services:
  $appName`:
    build: .
    ports:
      - "$port`:$port"
    volumes:
      - .:/app
    # environment:
    #   - NODE_ENV=development
"@

# Write the files
$dockerfilePath = Join-Path -Path $absolutePath -ChildPath "Dockerfile"
$dockerfileContent | Out-File -FilePath $dockerfilePath -Encoding utf8
Write-Host "Created Dockerfile at: $dockerfilePath"

$dockerignorePath = Join-Path -Path $absolutePath -ChildPath ".dockerignore"
$dockerignoreContent | Out-File -FilePath $dockerignorePath -Encoding utf8
Write-Host "Created .dockerignore at: $dockerignorePath"

$dockerComposePath = Join-Path -Path $absolutePath -ChildPath "docker-compose.yml"
$dockerComposeContent | Out-File -FilePath $dockerComposePath -Encoding utf8
Write-Host "Created docker-compose.yml at: $dockerComposePath"

# Display success message
Write-ColorText "`nDockerization complete! You can now build and run your Docker container with:" "Green"
Write-Host "  cd '$AppPath'"
Write-Host "  docker build -t my-app ."
Write-Host "  docker run -p $port`:$port my-app"
Write-Host "`nOr use Docker Compose:"
Write-Host "  docker-compose up"
