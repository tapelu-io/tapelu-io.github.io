#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

# --- Configuration & Colors ---
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

PROJECT_DIR_NAME="my_enterprise_app" # Name of the directory to create

# --- Helper Functions ---
ask_proceed() {
  echo -e "${YELLOW}❓ $1${NC}"
  read -p "Proceed? (y/N): " response
  if [[ "$response" =~ ^([yY][eE][sS]|[yY])$ ]]; then
    return 0
  else
    echo -e "${RED}🛑 Operation cancelled by user.${NC}"
    exit 1
  fi
}

# --- Start Script ---
echo -e "${BLUE}🚀 Deploying Self-Hosted Enterprise Application...${NC}"

# Create project directory and navigate into it
if [ -d "$PROJECT_DIR_NAME" ]; then
  ask_proceed "Directory '$PROJECT_DIR_NAME' already exists. Overwrite contents?"
fi
mkdir -p "$PROJECT_DIR_NAME"
cd "$PROJECT_DIR_NAME"
echo -e "${GREEN}✅ Created project directory: $(pwd)${NC}"


# --- Section 1: File Generation (Copied and adapted from previous response) ---
echo -e "${BLUE}📝 Generating application files...${NC}"

# 1. Create enhanced project structure
echo -e "  ${BLUE}📁 Creating project structure...${NC}"
mkdir -p public/css public/js public/images public/fonts public/icons \
           src/config src/routes src/services src/middleware src/utils src/models \
           src/subsystems/{auth,notifications,analytics,reporting,search,audit,workflow-engine,users,messaging,files,tasks,system} \
           src/queues/{processors,jobs} \
           src/scripts \
           tests/unit tests/integration \
           migrations seeders \
           logs data/uploads

# 2. Create .env with enhanced configuration
echo -e "  ${BLUE}⚙️  Creating .env configuration...${NC}"
# Generate VAPID keys
echo -e "  ${YELLOW}🔑 Generating VAPID keys for Web Push notifications...${NC}"
VAPID_KEYS_OUTPUT=$(npx web-push generate-vapid-keys --json)
VAPID_PUBLIC_KEY=$(echo "$VAPID_KEYS_OUTPUT" | grep -o '"publicKey": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')
VAPID_PRIVATE_KEY=$(echo "$VAPID_KEYS_OUTPUT" | grep -o '"privateKey": *"[^"]*"' | grep -o '"[^"]*"$' | tr -d '"')

if [ -z "$VAPID_PUBLIC_KEY" ] || [ -z "$VAPID_PRIVATE_KEY" ]; then
    echo -e "${RED}❌ Failed to generate VAPID keys. Using placeholders. Please generate and update them manually.${NC}"
    VAPID_PUBLIC_KEY="YOUR_GENERATED_VAPID_PUBLIC_KEY_HERE"
    VAPID_PRIVATE_KEY="YOUR_GENERATED_VAPID_PRIVATE_KEY_HERE"
fi
echo -e "  ${GREEN}🔑 VAPID Public Key: $VAPID_PUBLIC_KEY${NC}"

cat <<EOT > .env
# Server Configuration
PORT=3000
NODE_ENV=development # Set to 'production' for production
HOST=0.0.0.0
API_BASE_PATH=/api/v1

# Security
JWT_SECRET=your_super_strong_enterprise_secret_key_$(date +%s)
JWT_EXPIRES_IN=1h
REFRESH_TOKEN_SECRET=your_super_strong_refresh_secret_key_$(date +%s)
REFRESH_TOKEN_EXPIRES_IN=7d
CSRF_SECRET=your_csrf_secret_$(date +%s)

# Database (PostgreSQL) - Credentials match docker-compose
POSTGRES_USER=ep_user
POSTGRES_PASSWORD=ep_password
POSTGRES_DB=enterprise_app
DATABASE_URL=postgres://\${POSTGRES_USER}:\${POSTGRES_PASSWORD}@db:5432/\${POSTGRES_DB}?schema=public

# Redis
REDIS_HOST=redis
REDIS_PORT=6379
REDIS_PASSWORD=

# Elasticsearch
ELASTICSEARCH_NODE=http://elasticsearch:9200
ELASTICSEARCH_INDEX_PREFIX=enterprise_app_

# Logging
LOG_LEVEL=info
LOG_PRETTY_PRINT=true

# Sentry (Error Tracking)
SENTRY_DSN=
SENTRY_ENVIRONMENT=development

# File Storage (local, s3)
FILE_STORAGE_PROVIDER=local
UPLOAD_DIR=./data/uploads
MAX_FILE_SIZE_MB=50
AWS_S3_BUCKET_NAME=
AWS_S3_REGION=
AWS_ACCESS_KEY_ID=
AWS_SECRET_ACCESS_KEY=

# Email Service (Nodemailer) - Configure for real email sending
SMTP_HOST=
SMTP_PORT=587
SMTP_USER=
SMTP_PASS=
SMTP_FROM_EMAIL="noreply@enterpriseapp.com"

# Push Notifications
VAPID_PUBLIC_KEY=${VAPID_PUBLIC_KEY}
VAPID_PRIVATE_KEY=${VAPID_PRIVATE_KEY}
VAPID_SUBJECT='mailto:admin@enterpriseapp.com'
FCM_SERVER_KEY=your_fcm_server_key
PUSHY_API_KEY=your_pushy_api_key

# Subsystem Toggles (true/false)
ENABLE_NOTIFICATIONS=true
ENABLE_ANALYTICS=true
ENABLE_REPORTING=true
ENABLE_SEARCH=true
ENABLE_AUDIT=true
ENABLE_WORKFLOW_ENGINE=true
ENABLE_USERS=true
ENABLE_MESSAGING=true
ENABLE_FILES=true
ENABLE_TASKS=true

# App/Client URLs
APP_URL=http://localhost:3000
CLIENT_URL=http://localhost:3000

# CORS
CORS_ORIGIN=http://localhost:3000,http://127.0.0.1:3000 # Add your frontend origins

# Rate Limiting
RATE_LIMIT_MAX=100
RATE_LIMIT_WINDOW_MS=60000

# Admin User Initial Credentials (for seeder)
ADMIN_INITIAL_USERNAME=admin
ADMIN_INITIAL_EMAIL=admin@example.com
ADMIN_INITIAL_PASSWORD=AdminSecurePassword123!
EOT

# 3. Create package.json
echo -e "  ${BLUE}📦 Creating package.json...${NC}"
cat <<EOT > package.json
{
  "name": "enterprise-app",
  "version": "1.0.0",
  "description": "Enterprise-grade full-stack app with Fastify",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "NODE_ENV=development node --watch src/server.js",
    "test": "NODE_ENV=test jest tests/integration --runInBand",
    "test:unit": "NODE_ENV=test jest tests/unit",
    "lint": "eslint . --fix",
    "migrate": "npx sequelize-cli db:migrate",
    "migrate:undo": "npx sequelize-cli db:migrate:undo",
    "seed": "npx sequelize-cli db:seed:all",
    "seed:undo": "npx sequelize-cli db:seed:undo:all",
    "db:create": "echo 'Database creation handled by Docker Compose. For local dev, use: npx sequelize-cli db:create'",
    "es:init": "node src/scripts/initElasticsearch.js",
    "build": "echo 'No explicit build step for backend in this setup'"
  },
  "dependencies": {
    "fastify": "^4.26.2",
    "@fastify/autoload": "^5.8.0",
    "@fastify/cors": "^9.0.1",
    "@fastify/helmet": "^11.1.1",
    "@fastify/jwt": "^8.0.0",
    "@fastify/rate-limit": "^9.1.0",
    "@fastify/sensible": "^5.5.0",
    "@fastify/static": "^7.0.3",
    "@fastify/swagger": "^8.14.0",
    "@fastify/swagger-ui": "^3.0.0",
    "@fastify/multipart": "^8.2.0",
    "@fastify/websocket": "^10.0.0",
    "@fastify/csrf-protection": "^7.0.0",
    "dotenv": "^16.4.5",
    "sequelize": "^6.37.3",
    "pg": "^8.11.3",
    "pg-hstore": "^2.3.4",
    "joi": "^17.12.2",
    "bcryptjs": "^2.4.3",
    "bull": "^4.12.2",
    "ioredis": "^5.3.2",
    "@elastic/elasticsearch": "^7.17.0",
    "web-push": "^3.6.7",
    "nodemailer": "^6.9.13",
    "moment": "^2.30.1",
    "xlsx": "^0.18.5",
    "pdfmake": "^0.2.9",
    "sharp": "^0.33.3",
    "aws-sdk": "^2.1589.0",
    "pino-pretty": "^11.0.0",
    "pino-roll": "^1.10.0",
    "@sentry/node": "^7.106.0",
    "@sentry/profiling-node": "^1.3.5",
    "jsonwebtoken": "^9.0.2",
    "uuid": "^9.0.1"
  },
  "devDependencies": {
    "eslint": "^8.57.0",
    "eslint-config-airbnb-base": "^15.0.0",
    "eslint-plugin-import": "^2.29.1",
    "jest": "^29.7.0",
    "supertest": "^6.3.4",
    "sequelize-cli": "^6.6.2",
    "nodemon": "^3.1.0"
  },
  "engines": {
    "node": ">=18.0.0"
  }
}
EOT

# Create .eslintrc.js
echo -e "  ${BLUE}📜 Creating .eslintrc.js...${NC}"
cat <<EOT > .eslintrc.js
module.exports = {
  env: {
    browser: true,
    commonjs: true,
    es2021: true,
    node: true,
    jest: true,
  },
  extends: [
    'airbnb-base',
  ],
  parserOptions: {
    ecmaVersion: 12,
  },
  rules: {
    'no-console': process.env.NODE_ENV === 'production' ? 'warn' : 'off',
    'no-debugger': process.env.NODE_ENV === 'production' ? 'warn' : 'off',
    'linebreak-style': ['error', 'unix'],
    'quotes': ['error', 'single'],
    'semi': ['error', 'always'],
    'comma-dangle': ['error', 'always-multiline'],
    'no-unused-vars': ['warn', { 'argsIgnorePattern': '^_|^req|^reply|^fastify' }],
    'import/no-extraneous-dependencies': ['error', {'devDependencies': ['**/*.test.js', '**/*.spec.js', '**/seeders/**', '**/migrations/**', 'src/scripts/**']}],
    'max-len': ['warn', { 'code': 150, "ignoreStrings": true, "ignoreTemplateLiterals": true, "ignoreComments": true }],
    'no-param-reassign': ['error', { props: true, ignorePropertyModificationsFor: ['reply', 'request', 'acc', 'e', 'connection'] }],
    'class-methods-use-this': 'off',
    'consistent-return': 'off',
    'no-await-in-loop': 'off',
    'no-restricted-syntax': ['error', 'ForInStatement', 'LabeledStatement', 'WithStatement'],
  },
};
EOT

# Create .eslintignore
echo -e "  ${BLUE}📜 Creating .eslintignore...${NC}"
cat <<EOT > .eslintignore
node_modules
dist
coverage
logs
public
.env
data/uploads
EOT

# Create .gitignore
echo -e "  ${BLUE}📜 Creating .gitignore...${NC}"
cat <<EOT > .gitignore
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pids
*.pid
*.seed
*.pid.lock

# Node dependencies
node_modules/
dist/
coverage/
jspm_packages/

# Environment variables
.env
.env.local
.env.development.local
.env.test.local
.env.production.local
*.env

# Data files
data/
data/uploads/
postgres_data/
redis_data/
es_data/

# OS generated files
.DS_Store
.DS_Store?
._*
.Spotlight-V100
.Trashes
ehthumbs.db
Thumbs.db

# IDE specific files
.idea/
*.iml
*.project
*.vscode/
EOT


# 4. Sequelize config (config/config.json)
echo -e "  ${BLUE}🗄️  Configuring Sequelize (config/config.json)...${NC}"
mkdir -p config
cat <<EOT > config/config.json
{
  "development": {
    "use_env_variable": "DATABASE_URL",
    "dialect": "postgres",
    "dialectOptions": {
      "ssl": false
    }
  },
  "test": {
    "use_env_variable": "DATABASE_URL",
    "dialect": "postgres",
    "logging": false
  },
  "production": {
    "use_env_variable": "DATABASE_URL",
    "dialect": "postgres",
    "dialectOptions": {
      "ssl": {
        "require": true,
        "rejectUnauthorized": false
      }
    },
    "logging": false
  }
}
EOT

# --- Application Code (src directory) ---
# (This section contains all the cat <<EOT blocks for src/... files from your previous output)
# For brevity in this thought process, I'll assume these are correctly pasted here.
# In the final script, ALL `cat <<EOT > src/...` blocks must be present.
# I will include a placeholder for them.

# <<< PASTE ALL 'cat <<EOT > src/...' BLOCKS FROM PREVIOUS SCRIPT HERE >>>
# This includes:
# src/server.js
# src/config/app.js
# src/plugins.js
# src/decorators.js
# src/hooks.js
# src/models/index.js and all individual model files (User.js, Task.js, etc.)
# src/services/common/mailService.js
# src/services/searchService/elasticsearchClient.js
# src/queues/index.js and processor files
# src/subsystems/index.js and all individual subsystem directories/files (auth, users, tasks, etc.)
# src/scripts/initElasticsearch.js
# ...and any other src file.

# --- START OF PASTED SRC FILE GENERATION ---

# src/server.js (content from previous script)
echo -e "  ${BLUE}🚀 Creating main server (src/server.js)...${NC}"
cat <<EOT > src/server.js
require('dotenv').config();
const Fastify = require('fastify');
const path = require('path');
const Sentry = require('@sentry/node');

const appConfig = require('./config/app');
const loadPlugins = require('./plugins');
const loadDecorators = require('./decorators');
const loadHooks = require('./hooks');
const registerSubsystems = require('./subsystems');
const { sequelize } = require('./models'); // Ensure models are loaded

// Initialize Sentry
if (process.env.SENTRY_DSN && process.env.NODE_ENV === 'production') {
  Sentry.init({
    dsn: process.env.SENTRY_DSN,
    environment: process.env.SENTRY_ENVIRONMENT || process.env.NODE_ENV,
    tracesSampleRate: 1.0,
    profilesSampleRate: 1.0,
    integrations: [
      new Sentry.Integrations.Http({ tracing: true }),
      // Fastify specific integration or use Express-like
      ...Sentry.autoDiscoverNodePerformanceMonitoringIntegrations(),
    ],
  });
}

const fastify = Fastify({
  logger: appConfig.logger,
  trustProxy: true,
});

// Graceful Shutdown
const SHUTDOWN_TIMEOUT = 10000;
let isShuttingDown = false;

const gracefulShutdown = async (signal) => {
  if (isShuttingDown) {
    fastify.log.warn('Shutdown already in progress. Force exiting...');
    process.exit(1);
  }
  isShuttingDown = true;
  fastify.log.info(\`Received \${signal}. Starting graceful shutdown...\`);

  try {
    await fastify.close();
    fastify.log.info('✅ Fastify server closed.');

    if (sequelize) {
      await sequelize.close();
      fastify.log.info('✅ Sequelize connections closed.');
    }
    
    // Close Bull queues (Bull manages its own Redis client closing)
    if (fastify.queues) {
      await Promise.all(Object.values(fastify.queues).map(q => q.close()));
      fastify.log.info('✅ Bull queues closed.');
    }
    // Close Elasticsearch client
    if (fastify.elasticsearch && fastify.elasticsearch.close) {
        await fastify.elasticsearch.close();
        fastify.log.info('✅ Elasticsearch client closed.');
    }


    fastify.log.info('🎉 Graceful shutdown completed. Exiting.');
    process.exit(0);
  } catch (err) {
    fastify.log.error({ err }, 'Error during graceful shutdown:');
    process.exit(1);
  }
};

['SIGINT', 'SIGTERM', 'SIGQUIT'].forEach(signal => {
  process.on(signal, () => gracefulShutdown(signal));
});

process.on('uncaughtException', (err, origin) => {
  fastify.log.fatal({ err, origin }, 'UNCAUGHT EXCEPTION! Shutting down...');
  Sentry.captureException(err);
  gracefulShutdown('uncaughtException').then(() => process.exit(1));
  setTimeout(() => process.exit(1), SHUTDOWN_TIMEOUT).unref();
});

process.on('unhandledRejection', (reason, promise) => {
  fastify.log.fatal({ reason, promise }, 'UNHANDLED REJECTION! Shutting down...');
  Sentry.captureException(reason);
  gracefulShutdown('unhandledRejection').then(() => process.exit(1));
  setTimeout(() => process.exit(1), SHUTDOWN_TIMEOUT).unref();
});


const start = async () => {
  try {
    await loadPlugins(fastify);
    await loadDecorators(fastify);
    await loadHooks(fastify);
    await registerSubsystems(fastify);

    fastify.register(require('@fastify/static'), {
      root: path.join(__dirname, '../public'),
      prefix: '/',
    });

    fastify.get('/health', { logLevel: 'warn' }, async (request, reply) => {
      try {
        await sequelize.authenticate();
        if (fastify.elasticsearch) await fastify.elasticsearch.ping().catch(() => { throw new Error('ES Ping failed'); });
        if (fastify.queues && fastify.queues.notifications) await fastify.queues.notifications.client.ping().catch(() => { throw new Error('Redis Ping failed'); });
        return reply.send({ status: 'ok', timestamp: new Date().toISOString() });
      } catch (error) {
        fastify.log.error({ err: error }, 'Health check failed');
        return reply.status(503).send({ status: 'error', message: 'Service Unavailable', details: error.message });
      }
    });
    
    fastify.get('/', (request, reply) => {
      reply.sendFile('index.html');
    });

    await sequelize.authenticate();
    fastify.log.info('✅ Database connection established successfully.');

    if (process.env.NODE_ENV !== 'production') {
      fastify.log.warn('Development/Test environment: Model synchronization via sync() is disabled. Ensure migrations are run: npm run migrate or docker-compose exec app npm run migrate');
    } else {
       fastify.log.info('Production environment: Model synchronization via sync() is disabled. Ensure migrations are run.');
    }

    await fastify.listen({ port: appConfig.port, host: appConfig.host });
    // fastify.log.info(\`🚀 Server listening on \${fastify.server.address().address}:\${fastify.server.address().port}\`); // This might error if address is null initially
    fastify.log.info(\`📚 API documentation available at http://\${appConfig.host === '0.0.0.0' ? 'localhost' : appConfig.host}:\${appConfig.port}\${appConfig.swagger.routePrefix}\`);

  } catch (err) {
    Sentry.captureException(err);
    fastify.log.fatal({ err }, 'Failed to start server:');
    process.exit(1);
  }
};

// Export fastify instance for testing AFTER start() is defined
// but only call start() if this module is run directly
if (require.main === module) {
  start();
} else {
  // For testing: allow awaiting readiness before tests run
  module.exports = (async () => {
    // Configure for test environment before loading everything
    // This is a bit tricky; Jest setupFiles is better for env vars.
    // We'll assume env vars are set by test script/jest.config.js
    await loadPlugins(fastify);
    await loadDecorators(fastify);
    await loadHooks(fastify);
    await registerSubsystems(fastify);
    // Don't call fastify.listen() here for tests
    return fastify;
  })(); // Export a promise that resolves to the configured fastify instance
}

EOT

# src/config/app.js (content from previous script)
echo -e "  ${BLUE}⚙️  Creating app configuration (src/config/app.js)...${NC}"
cat <<EOT > src/config/app.js
const pino = require('pino');

const isProduction = process.env.NODE_ENV === 'production';

const loggerOptions = {
  level: process.env.LOG_LEVEL || (isProduction ? 'info' : 'debug'),
  ...(isProduction
    ? { /* Production logging (e.g., JSON to stdout, or pino-roll) */ }
    : { // Development logging with pino-pretty
        transport: {
          target: 'pino-pretty',
          options: {
            colorize: true,
            translateTime: 'SYS:standard',
            ignore: 'pid,hostname',
          },
        },
      }),
};


module.exports = {
  port: parseInt(process.env.PORT, 10) || 3000,
  host: process.env.HOST || '0.0.0.0',
  apiBasePath: process.env.API_BASE_PATH || '/api/v1',
  jwt: {
    secret: process.env.JWT_SECRET,
    expiresIn: process.env.JWT_EXPIRES_IN || '1h',
    refreshTokenSecret: process.env.REFRESH_TOKEN_SECRET,
    refreshTokenExpiresIn: process.env.REFRESH_TOKEN_EXPIRES_IN || '7d',
  },
  csrf: {
    secret: process.env.CSRF_SECRET, // Ensure this is set from .env
    cookieOpts: {
        path: '/',
        httpOnly: true,
        secure: isProduction,
        sameSite: 'Strict',
    }
  },
  cors: {
    origin: process.env.CORS_ORIGIN ? process.env.CORS_ORIGIN.split(',').map(o => o.trim()) : true, // true reflects request origin
    methods: ['GET', 'POST', 'PUT', 'DELETE', 'PATCH', 'OPTIONS'],
    credentials: true,
  },
  rateLimit: {
    max: parseInt(process.env.RATE_LIMIT_MAX, 10) || 100,
    timeWindow: parseInt(process.env.RATE_LIMIT_WINDOW_MS, 10) || 60000,
  },
  swagger: {
    routePrefix: '/documentation',
    swagger: {
      info: {
        title: 'Enterprise App API',
        description: 'API documentation for the Enterprise Application',
        version: '1.0.0',
      },
      externalDocs: {
        url: 'https://swagger.io',
        description: 'Find more info here',
      },
      host: process.env.APP_URL || \`localhost:\${parseInt(process.env.PORT, 10) || 3000}\`,
      schemes: [isProduction ? 'https' : 'http'],
      consumes: ['application/json', 'multipart/form-data'],
      produces: ['application/json'],
      securityDefinitions: {
        bearerAuth: {
          type: 'apiKey',
          name: 'Authorization',
          in: 'header',
          description: "JWT Authorization header using the Bearer scheme. Example: \\"Bearer {token}\\""
        }
      },
      security: [{ bearerAuth: [] }]
    },
    uiConfig: {
      docExpansion: 'list',
      deepLinking: true,
    },
    staticCSP: true, // Enable CSP for Swagger UI
    // transformStaticCSP: (header) => header, // Customize CSP if needed
  },
  logger: loggerOptions,
  fileStorage: {
    provider: process.env.FILE_STORAGE_PROVIDER || 'local',
    uploadDir: process.env.UPLOAD_DIR || './data/uploads',
    maxFileSize: (parseInt(process.env.MAX_FILE_SIZE_MB, 10) || 50) * 1024 * 1024,
    s3: {
      bucketName: process.env.AWS_S3_BUCKET_NAME,
      region: process.env.AWS_S3_REGION,
      accessKeyId: process.env.AWS_ACCESS_KEY_ID,
      secretAccessKey: process.env.AWS_SECRET_ACCESS_KEY,
    },
  },
  email: {
    smtp: {
      host: process.env.SMTP_HOST,
      port: parseInt(process.env.SMTP_PORT, 10) || 587,
      secure: (parseInt(process.env.SMTP_PORT, 10) || 587) === 465,
      auth: {
        user: process.env.SMTP_USER,
        pass: process.env.SMTP_PASS,
      },
    },
    from: process.env.SMTP_FROM_EMAIL || 'noreply@enterpriseapp.com',
  },
  pushNotifications: {
    vapidDetails: {
      subject: process.env.VAPID_SUBJECT || 'mailto:admin@enterpriseapp.com',
      publicKey: process.env.VAPID_PUBLIC_KEY,
      privateKey: process.env.VAPID_PRIVATE_KEY,
    },
    fcmServerKey: process.env.FCM_SERVER_KEY,
    pushyApiKey: process.env.PUSHY_API_KEY,
  },
  elasticsearch: {
    node: process.env.ELASTICSEARCH_NODE || 'http://elasticsearch:9200',
    indexPrefix: process.env.ELASTICSEARCH_INDEX_PREFIX || 'enterprise_app_',
  },
  redis: {
    host: process.env.REDIS_HOST || 'redis',
    port: parseInt(process.env.REDIS_PORT, 10) || 6379,
    password: process.env.REDIS_PASSWORD || undefined,
  },
};
EOT

# src/plugins.js (content from previous script)
echo -e "  ${BLUE}🧩 Creating plugin loader (src/plugins.js)...${NC}"
cat <<EOT > src/plugins.js
const sensible = require('@fastify/sensible');
const helmet = require('@fastify/helmet');
const cors = require('@fastify/cors');
const jwt = require('@fastify/jwt');
const rateLimit = require('@fastify/rate-limit');
const swagger = require('@fastify/swagger');
const swaggerUi = require('@fastify/swagger-ui');
const multipart = require('@fastify/multipart');
const websocket = require('@fastify/websocket');
// const csrf = require('@fastify/csrf-protection'); // Enable if using traditional CSRF
const path = require('path');
const Redis = require('ioredis');

const appConfig = require('./config/app');
const { initQueues } = require('./queues');

module.exports = async function loadPlugins(fastify) {
  fastify.register(sensible);

  fastify.register(helmet, {
    contentSecurityPolicy: false, // Disable default CSP; configure carefully if enabled.
                                  // For dev, false is easier. For prod, a strict policy is vital.
  });

  fastify.register(cors, appConfig.cors);

  fastify.register(jwt, {
    secret: appConfig.jwt.secret,
  });

  // CSRF Protection - uncomment and configure if needed
  // Be careful with SPAs and API-only backends. Bearer tokens are often sufficient.
  // if (appConfig.csrf.secret) {
  //   fastify.register(require('@fastify/cookie')); // CSRF often relies on cookies
  //   fastify.register(csrf, { 
  //       secret: appConfig.csrf.secret, 
  //       cookieOpts: appConfig.csrf.cookieOpts,
  //       // getToken: (request) => request.headers['x-csrf-token'] // Example for header-based token
  //   });
  // }


  if (appConfig.redis.host) {
    const redisClient = new Redis({
      host: appConfig.redis.host,
      port: appConfig.redis.port,
      password: appConfig.redis.password,
      maxRetriesPerRequest: 3, // Example: retry config
    });
    redisClient.on('error', (err) => fastify.log.error({ err }, 'Redis connection error for rate-limit/cache'));
    fastify.register(rateLimit, {
      max: appConfig.rateLimit.max,
      timeWindow: appConfig.rateLimit.timeWindow,
      redis: redisClient,
    });
    fastify.decorate('redis', redisClient); // Decorate for general use if needed
    fastify.log.info('✅ Rate limiting configured with Redis.');
  } else {
    fastify.register(rateLimit, { // Fallback to in-memory
      max: appConfig.rateLimit.max,
      timeWindow: appConfig.rateLimit.timeWindow,
    });
    fastify.log.warn('⚠️ Rate limiting configured with in-memory store (Redis not configured).');
  }


  fastify.register(multipart, {
    attachFieldsToBody: 'keyValues', // Compatibility with Multer-like field handling
    limits: {
      fileSize: appConfig.fileStorage.maxFileSize,
      // Add other limits as needed
    },
  });

  fastify.register(websocket);

  if (process.env.NODE_ENV !== 'production' || process.env.ENABLE_SWAGGER_IN_PROD === 'true') {
    fastify.register(swagger, appConfig.swagger);
    fastify.register(swaggerUi, {
      routePrefix: appConfig.swagger.routePrefix,
      uiConfig: appConfig.swagger.uiConfig,
      staticCSP: appConfig.swagger.staticCSP,
    });
  }

  const queues = initQueues(fastify);
  fastify.decorate('queues', queues);
  fastify.log.info('✅ Bull queues initialized and decorated.');
};
EOT

# src/decorators.js (content from previous script)
echo -e "  ${BLUE}🎨 Creating decorator loader (src/decorators.js)...${NC}"
cat <<EOT > src/decorators.js
const db = require('./models'); // This now exports { sequelize, User, Task, ... Op }
const { esClient } = require('./services/searchService/elasticsearchClient');
const MailService = require('./services/common/mailService');
const appConfig = require('./config/app');

module.exports = async function loadDecorators(fastify) {
  fastify.decorate('db', db); // db object contains sequelize, models, and Op
  fastify.log.info('✅ Database models and Sequelize instance decorated onto Fastify.');

  if (appConfig.elasticsearch.node && esClient) {
    fastify.decorate('elasticsearch', esClient);
    fastify.log.info('✅ Elasticsearch client decorated.');
  } else {
    fastify.log.warn('Elasticsearch node not configured or client init failed. Search functionality may be limited.');
    fastify.decorate('elasticsearch', null);
  }

  fastify.decorate('mailService', new MailService(appConfig.email, fastify.log));
  fastify.log.info('✅ Mail service decorated.');

  fastify.decorateRequest('currentUser', null);
  fastify.decorateRequest('userRoles', []);
  
  // Decorate with IP address from request (handles proxies if trustProxy is true)
  fastify.decorateRequest('ip', function () { return this.headers['x-forwarded-for'] || this.socket.remoteAddress; });
};
EOT

# src/hooks.js (content from previous script)
echo -e "  ${BLUE}⚓ Creating hooks loader (src/hooks.js)...${NC}"
cat <<EOT > src/hooks.js
const Sentry = require('@sentry/node');
const appConfig = require('./config/app');

const checkRoles = (allowedRoles) => async (request, reply) => {
  if (!request.currentUser) {
    request.log.warn('RBAC: No current user found for role check.');
    throw fastify.httpErrors.unauthorized('Authentication required for this action.');
  }

  const userRoles = Array.isArray(request.currentUser.role) ? request.currentUser.role : [request.currentUser.role];
  const hasPermission = allowedRoles.some(role => userRoles.includes(role));

  if (!hasPermission) {
    request.log.warn({ userId: request.currentUser.id, requiredRoles: allowedRoles, userRoles, url: request.raw.url }, 'RBAC: Permission denied.');
    throw fastify.httpErrors.forbidden('You do not have the required permissions for this action.');
  }
};

module.exports = async function loadHooks(fastify) {
  // Authentication Hook
  fastify.decorate('authenticate', async (request, reply) => {
    try {
      await request.jwtVerify();
      request.currentUser = request.user;
      request.userRoles = Array.isArray(request.user.role) ? request.user.role : [request.user.role];
      if (process.env.SENTRY_DSN && request.user) {
        Sentry.setUser({ id: request.user.id, username: request.user.username, email: request.user.email });
      }
    } catch (err) {
      request.log.warn({ err, url: request.raw.url }, 'JWT verification failed in authenticate decorator.');
      reply.code(401).send({ error: 'Unauthorized', message: err.message });
    }
  });


  // Global onRequest hook for routes that are NOT explicitly public
  fastify.addHook('onRequest', async (request, reply) => {
    // Skip for specified public paths and OPTIONS requests (CORS preflight)
    const publicPaths = [
      '/', // Root for PWA
      '/health',
      new RegExp(`^${appConfig.swagger.routePrefix}(/.*)?$`), // Swagger UI and its assets
      new RegExp(`^${appConfig.apiBasePath}/auth/(login|register|refresh-token|verify-email|forgot-password|reset-password)$`),
      // Add other explicitly public GET routes if any
    ];
    
    const isPublic = request.method === 'OPTIONS' || publicPaths.some(p => 
        typeof p === 'string' ? request.raw.url.startsWith(p) : p.test(request.raw.url)
    );

    if (isPublic || request.routeOptions?.config?.isPublic) { // Check for route-specific public flag
      return;
    }

    // For all other routes, enforce authentication using the decorated 'authenticate'
    // This makes 'fastify.authenticate' the explicit way to protect routes if defined in preHandler.
    // If you want global auth by default, call it here.
    // For now, we rely on routes specifying `preHandler: [fastify.authenticate]`
    // If a route is not public and does not have `fastify.authenticate` in preHandler, it will be an issue.
    // A better approach might be to authenticate globally and mark public routes.
    // Let's stick to explicit `fastify.authenticate` in routes for now.
  });
  
  // Global preHandler hook to set CSRF token for GET requests if CSRF is enabled
  // if (appConfig.csrf.secret) {
  //   fastify.addHook('preHandler', async (request, reply) => {
  //     if (request.method === 'GET') {
  //       // reply.generateCsrf(); // Generate and set CSRF token (e.g., in a cookie or header for client)
  //       // This token would then be sent back by client in POST/PUT/DELETE requests
  //     }
  //   });
  // }


  fastify.setErrorHandler((error, request, reply) => {
    if (process.env.SENTRY_DSN) Sentry.captureException(error, { extra: { route: request.routerPath, method: request.method, body: request.body, query: request.query }});
    request.log.error({ err: error, reqId: request.id, method: request.method, path: request.url }, 'Error caught by global error handler');

    if (error.validation) {
      reply.status(400).send({
        statusCode: 400, error: 'Bad Request', message: 'Validation Error',
        details: error.validation.map(v => ({ message: v.message, path: v.path })),
      });
      return;
    }
    if (error.statusCode) {
      reply.status(error.statusCode).send({
        statusCode: error.statusCode, error: error.name || 'Error', message: error.message,
      });
      return;
    }
    reply.status(500).send({
      statusCode: 500, error: 'Internal Server Error', message: 'An unexpected error occurred.',
    });
  });

  fastify.setNotFoundHandler((request, reply) => {
    request.log.warn({ reqId: request.id, method: request.method, path: request.url }, 'Route not found');
    reply.status(404).send({
      statusCode: 404, error: 'Not Found', message: \`Route \${request.method}:\${request.url} not found\`,
    });
  });

  fastify.log.info('✅ Global hooks registered.');
  fastify.decorate('checkRoles', checkRoles);
};
EOT

# src/models/index.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating base model (src/models/index.js)...${NC}"
cat <<EOT > src/models/index.js
const { Sequelize, DataTypes, Op } = require('sequelize');
const appConfig = require('../config/app');
const path = require('path');
const fs = require('fs');

const sequelize = new Sequelize(process.env.DATABASE_URL, {
  dialect: 'postgres',
  logging: process.env.NODE_ENV === 'development' ? console.log : false,
  pool: { max: 10, min: 0, acquire: 30000, idle: 10000 },
  define: { timestamps: true, underscored: true },
});

const db = {};

fs.readdirSync(__dirname)
  .filter(file => (file.indexOf('.') !== 0) && (file !== path.basename(__filename)) && (file.slice(-3) === '.js'))
  .forEach(file => {
    const modelDefinition = require(path.join(__dirname, file));
    const model = modelDefinition(sequelize, DataTypes);
    db[model.name] = model;
  });

Object.keys(db).forEach(modelName => {
  if (db[modelName].associate) {
    db[modelName].associate(db);
  }

  db[modelName].getSearchIndexName = function() {
    return \`\${appConfig.elasticsearch.indexPrefix}\${this.tableName.toLowerCase()}\`;
  };

  db[modelName].prototype.toSearchableDocument = async function() {
    const data = { ...this.toJSON() };
    delete data.password; // Common sensitive field
    // Override this in specific models for custom document structure
    return data;
  };

  if (appConfig.elasticsearch.node && process.env.ENABLE_SEARCH === 'true' && process.env.NODE_ENV !== 'test') { // Disable for tests unless specific
    const esHook = async (instance, options, action) => {
      try {
        // Dynamically require esClient to avoid circular deps during initial load or if ES is off
        const { esClient } = require('../services/searchService/elasticsearchClient');
        if (!esClient) return;

        const indexName = db[modelName].getSearchIndexName();
        
        const performEsAction = async () => {
          if (action === 'delete') {
            await esClient.delete({ index: indexName, id: instance.id.toString() }, { ignore: [404] });
            // console.log(\`ES: Deleted \${modelName} \${instance.id}\`);
          } else { // create or update
            const document = await instance.toSearchableDocument();
            await esClient.index({
              index: indexName,
              id: instance.id.toString(),
              body: document,
              refresh: process.env.NODE_ENV === 'development' ? 'wait_for' : false,
            });
            // console.log(\`ES: Indexed \${modelName} \${instance.id}\`);
          }
        };

        if (options.transaction) {
          options.transaction.afterCommit(performEsAction);
        } else {
          await performEsAction();
        }
      } catch (err) {
        // Use a proper logger in a real app
        console.error(\`ES Hook Error (\${action}) for \${modelName} \${instance.id}:\`, err.meta ? err.meta.body : err);
      }
    };

    db[modelName].addHook('afterCreate', (instance, options) => esHook(instance, options, 'create'));
    db[modelName].addHook('afterUpdate', (instance, options) => esHook(instance, options, 'update'));
    db[modelName].addHook('afterSave', (instance, options) => { /* Covered by afterCreate/Update often, but can be specific */ });
    db[modelName].addHook('afterDestroy', (instance, options) => esHook(instance, options, 'delete'));
  }
});

db.sequelize = sequelize;
db.Sequelize = Sequelize;
db.Op = Op;

module.exports = db;
EOT

# src/models/User.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating User model...${NC}"
cat <<EOT > src/models/User.js
const bcrypt = require('bcryptjs');
const crypto = require('crypto'); // For tokens

module.exports = (sequelize, DataTypes) => {
  const User = sequelize.define('User', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    username: {
      type: DataTypes.STRING, allowNull: false, unique: true,
      validate: { notEmpty: true, len: [3, 50] },
    },
    email: {
      type: DataTypes.STRING, allowNull: false, unique: true,
      validate: { isEmail: true, notEmpty: true },
    },
    password: {
      type: DataTypes.STRING, allowNull: false,
      validate: { notEmpty: true, len: [8, 100] },
    },
    firstName: { type: DataTypes.STRING },
    lastName: { type: DataTypes.STRING },
    role: { type: DataTypes.ENUM('user', 'manager', 'admin', 'developer', 'guest'), defaultValue: 'user', allowNull: false },
    avatarUrl: { type: DataTypes.STRING, validate: { isUrl: true } },
    status: { type: DataTypes.ENUM('active', 'inactive', 'suspended', 'pending_verification'), defaultValue: 'pending_verification', allowNull: false },
    lastLoginAt: { type: DataTypes.DATE },
    timezone: { type: DataTypes.STRING, defaultValue: 'UTC' },
    locale: { type: DataTypes.STRING, defaultValue: 'en-US' },
    emailVerifiedAt: { type: DataTypes.DATE },
    emailVerificationToken: { type: DataTypes.STRING },
    passwordResetToken: { type: DataTypes.STRING },
    passwordResetExpiresAt: { type: DataTypes.DATE },
  }, {
    tableName: 'users',
    timestamps: true,
    hooks: {
      beforeCreate: async (user) => {
        if (user.password) user.password = await bcrypt.hash(user.password, 10);
      },
      beforeUpdate: async (user) => {
        if (user.changed('password') && user.password) {
          user.password = await bcrypt.hash(user.password, 10);
        }
      },
    },
    defaultScope: { attributes: { exclude: ['password', 'emailVerificationToken', 'passwordResetToken'] } },
    scopes: { withSensitiveInfo: { attributes: { include: ['password', 'emailVerificationToken', 'passwordResetToken'] } } },
  });

  User.prototype.validPassword = async function(password) { return bcrypt.compare(password, this.password); };
  
  User.prototype.generateEmailVerificationToken = function() {
    this.emailVerificationToken = crypto.randomBytes(32).toString('hex');
    // this.emailVerificationExpires = Date.now() + 3600000 * 24; // 24 hours
  };

  User.prototype.generatePasswordResetToken = function() {
    this.passwordResetToken = crypto.randomBytes(32).toString('hex');
    this.passwordResetExpiresAt = new Date(Date.now() + 3600000); // 1 hour
  };


  User.associate = (models) => {
    User.hasMany(models.Task, { foreignKey: 'assigneeId', as: 'assignedTasks' });
    User.hasMany(models.Task, { foreignKey: 'creatorId', as: 'createdTasks' });
    User.hasMany(models.Notification, { foreignKey: 'userId', as: 'notifications' });
    User.hasMany(models.AuditLog, { foreignKey: 'userId', as: 'auditLogs' });
    User.hasMany(models.Message, { foreignKey: 'senderId', as: 'sentMessages' });
    User.hasMany(models.File, { foreignKey: 'uploadedById', as: 'files' });
  };

  User.prototype.toSearchableDocument = async function() {
    return {
      id: this.id, username: this.username, email: this.email,
      firstName: this.firstName, lastName: this.lastName,
      role: this.role, status: this.status,
      createdAt: this.createdAt, updatedAt: this.updatedAt,
    };
  };
  return User;
};
EOT

# src/models/Task.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating Task model...${NC}"
cat <<EOT > src/models/Task.js
module.exports = (sequelize, DataTypes) => {
  const Task = sequelize.define('Task', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    title: { type: DataTypes.STRING, allowNull: false, validate: { len: [3, 255] } },
    description: { type: DataTypes.TEXT },
    status: { type: DataTypes.ENUM('todo', 'in_progress', 'in_review', 'blocked', 'done', 'archived'), defaultValue: 'todo', allowNull: false },
    priority: { type: DataTypes.ENUM('low', 'medium', 'high', 'critical'), defaultValue: 'medium', allowNull: false },
    dueDate: { type: DataTypes.DATE },
    completedAt: { type: DataTypes.DATE },
    assigneeId: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: true },
    creatorId: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: false },
    tags: { type: DataTypes.ARRAY(DataTypes.STRING), defaultValue: [] },
  }, { tableName: 'tasks', timestamps: true, paranoid: true });

  Task.associate = (models) => {
    Task.belongsTo(models.User, { as: 'assignee', foreignKey: 'assigneeId' });
    Task.belongsTo(models.User, { as: 'creator', foreignKey: 'creatorId' });
  };
  
  Task.prototype.toSearchableDocument = async function() {
    const assignee = this.assigneeId ? await this.getAssignee({ attributes: ['id', 'username']}) : null;
    const creator = this.creatorId ? await this.getCreator({ attributes: ['id', 'username']}) : null;
    return {
      id: this.id, title: this.title, description: this.description,
      status: this.status, priority: this.priority, dueDate: this.dueDate,
      tags: this.tags,
      assignee: assignee ? { id: assignee.id, username: assignee.username } : null,
      creator: creator ? { id: creator.id, username: creator.username } : null,
      createdAt: this.createdAt, updatedAt: this.updatedAt,
    };
  };
  return Task;
};
EOT

# src/models/Workflow.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating Workflow model...${NC}"
cat <<EOT > src/models/Workflow.js
module.exports = (sequelize, DataTypes) => {
  const Workflow = sequelize.define('Workflow', { // This represents Workflow TEMPLATES
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    name: { type: DataTypes.STRING, allowNull: false, unique: true, validate: { len: [3, 100] } },
    description: { type: DataTypes.TEXT },
    definition: { type: DataTypes.JSONB, allowNull: false, validate: { notEmpty: true } }, // Schema for steps, transitions
    // category: { type: DataTypes.STRING },
    // version: { type: DataTypes.INTEGER, defaultValue: 1 },
    // createdById: { type: DataTypes.UUID, references: { model: 'Users', key: 'id' } },
  }, { tableName: 'workflows', timestamps: true });

  // Workflow.associate = (models) => {
    // Workflow.belongsTo(models.User, { as: 'createdBy', foreignKey: 'createdById' });
    // A separate WorkflowInstance model would track running instances of these templates.
  // };
  return Workflow;
};
EOT

# src/models/Notification.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating Notification model...${NC}"
cat <<EOT > src/models/Notification.js
module.exports = (sequelize, DataTypes) => {
  const Notification = sequelize.define('Notification', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    userId: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: false },
    type: { type: DataTypes.ENUM('task_assigned', 'task_updated', 'workflow_step', 'system_alert', 'new_message', 'file_shared', 'mention', 'report_ready', 'email_verification', 'password_reset'), allowNull: false },
    title: { type: DataTypes.STRING, allowNull: false },
    message: { type: DataTypes.TEXT, allowNull: false },
    isRead: { type: DataTypes.BOOLEAN, defaultValue: false, allowNull: false },
    readAt: { type: DataTypes.DATE },
    data: { type: DataTypes.JSONB }, // For entity IDs, URLs, etc.
  }, { tableName: 'notifications', timestamps: true, indexes: [{ fields: ['user_id', 'is_read', 'created_at'] }] });

  Notification.associate = (models) => {
    Notification.belongsTo(models.User, { as: 'user', foreignKey: 'userId' });
  };
  return Notification;
};
EOT

# src/models/AuditLog.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating AuditLog model...${NC}"
cat <<EOT > src/models/AuditLog.js
module.exports = (sequelize, DataTypes) => {
  const AuditLog = sequelize.define('AuditLog', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    userId: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: true },
    action: { type: DataTypes.STRING, allowNull: false },
    entityType: { type: DataTypes.STRING },
    entityId: { type: DataTypes.UUID },
    description: { type: DataTypes.TEXT },
    details: { type: DataTypes.JSONB }, // Old values, new values, params
    ipAddress: { type: DataTypes.STRING },
    userAgent: { type: DataTypes.STRING(512) }, // Increased length for longer user agents
  }, { tableName: 'audit_logs', timestamps: true, updatedAt: false, indexes: [{ fields: ['user_id'] }, { fields: ['entity_type', 'entity_id'] }, { fields: ['action'] }, { fields: ['created_at'] }] });

  AuditLog.associate = (models) => {
    AuditLog.belongsTo(models.User, { as: 'user', foreignKey: 'userId' });
  };
  return AuditLog;
};
EOT

# src/models/Message.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating Message model...${NC}"
cat <<EOT > src/models/Message.js
module.exports = (sequelize, DataTypes) => {
  const Message = sequelize.define('Message', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    senderId: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: false },
    channelId: { type: DataTypes.STRING, allowNull: false }, // UserID for DMs, GroupID for group chats
    channelType: { type: DataTypes.ENUM('direct', 'group'), allowNull: false, defaultValue: 'direct' },
    content: { type: DataTypes.TEXT, allowNull: false, validate: { notEmpty: true } },
    // attachments: { type: DataTypes.JSONB }, // Array of File IDs
  }, { tableName: 'messages', timestamps: true, indexes: [{ fields: ['channel_id', 'created_at'] }, { fields: ['sender_id'] }] });

  Message.associate = (models) => {
    Message.belongsTo(models.User, { as: 'sender', foreignKey: 'senderId' });
    // A Channel/Conversation model would be better for managing participants and metadata
  };
  return Message;
};
EOT

# src/models/File.js (content from previous script)
echo -e "  ${BLUE}🧱 Creating File model...${NC}"
cat <<EOT > src/models/File.js
module.exports = (sequelize, DataTypes) => {
  const File = sequelize.define('File', {
    id: { type: DataTypes.UUID, defaultValue: DataTypes.UUIDV4, primaryKey: true },
    originalName: { type: DataTypes.STRING, allowNull: false },
    fileName: { type: DataTypes.STRING, allowNull: false, unique: true }, // Stored name (potentially hashed)
    mimeType: { type: DataTypes.STRING, allowNull: false },
    size: { type: DataTypes.BIGINT, allowNull: false }, // In bytes
    storagePath: { type: DataTypes.STRING, allowNull: false }, // Path in local storage or S3 key
    storageProvider: { type: DataTypes.STRING, allowNull: false }, // 'local', 's3'
    publicUrl: { type: DataTypes.STRING, validate: { isUrl: true }, allowNull: true },
    uploadedById: { type: DataTypes.UUID, references: { model: 'users', key: 'id' }, allowNull: false },
    // hash: { type: DataTypes.STRING }, // sha256 for deduplication/integrity
    // metadata: { type: DataTypes.JSONB }, // image dimensions, etc.
  }, { tableName: 'files', timestamps: true, paranoid: true }); // Soft delete for files

  File.associate = (models) => {
    File.belongsTo(models.User, { as: 'uploader', foreignKey: 'uploadedById' });
  };

  File.prototype.toSearchableDocument = async function() {
    const uploader = this.uploaderId ? await this.getUploader({ attributes: ['id', 'username']}) : null;
    return {
      id: this.id, originalName: this.originalName, mimeType: this.mimeType, size: this.size,
      uploader: uploader ? { id: uploader.id, username: uploader.username } : null,
      createdAt: this.createdAt,
    };
  };
  return File;
};
EOT

# src/services/common/mailService.js (content from previous script)
echo -e "  ${BLUE}✉️  Creating Mail Service (src/services/common/mailService.js)...${NC}"
cat <<EOT > src/services/common/mailService.js
const nodemailer = require('nodemailer');

class MailService {
  constructor(config, logger) {
    this.config = config.smtp;
    this.from = config.from;
    this.logger = logger.child({ service: 'MailService' }); // Child logger for context
    if (this.config && this.config.host && this.config.auth && this.config.auth.user) {
      this.transporter = nodemailer.createTransport({
        host: this.config.host,
        port: this.config.port,
        secure: this.config.secure,
        auth: { user: this.config.auth.user, pass: this.config.auth.pass },
        // tls: { rejectUnauthorized: process.env.NODE_ENV === 'production' } // Stricter TLS in prod
      });
      this.logger.info('📬 MailService initialized.');
    } else {
      this.logger.warn('📬 MailService SMTP not configured. Emails will be logged instead of sent.');
      this.transporter = null;
    }
  }

  async sendMail({ to, subject, text, html }) {
    if (!this.transporter) {
      this.logger.info({ to, subject, text, html }, 'Mock email sending (SMTP not configured)');
      return Promise.resolve({ messageId: 'mock-message-id-dev', accepted: [to] });
    }
    const mailOptions = { from: this.from, to, subject, text, html };
    try {
      const info = await this.transporter.sendMail(mailOptions);
      this.logger.info({ to, subject, messageId: info.messageId }, 'Email sent successfully.');
      return info;
    } catch (error) {
      this.logger.error({ err: error, to, subject }, 'Error sending email.');
      throw error;
    }
  }

  async sendVerificationEmail(user, token) {
    const verificationLink = \`\${process.env.CLIENT_URL}/verify-email?token=\${token}\`;
    return this.sendMail({
      to: user.email, subject: 'Verify Your Email Address - Enterprise App',
      text: \`Hello \${user.username || 'User'}, please verify your email by clicking this link: \${verificationLink}\`,
      html: \`<p>Hello \${user.username || 'User'},</p><p>Please verify your email by clicking this link: <a href="\${verificationLink}">Verify Email</a></p>\`,
    });
  }

  async sendPasswordResetEmail(user, token) {
    const resetLink = \`\${process.env.CLIENT_URL}/reset-password?token=\${token}\`;
    return this.sendMail({
      to: user.email, subject: 'Password Reset Request - Enterprise App',
      text: \`Hello \${user.username || 'User'}, you requested a password reset. Click this link: \${resetLink}\nIf not you, ignore this.\`,
      html: \`<p>Hello \${user.username || 'User'},</p><p>You requested a password reset. Click this link: <a href="\${resetLink}">Reset Password</a></p><p>If you did not request this, please ignore this email.</p>\`,
    });
  }
}
module.exports = MailService;
EOT

# src/services/searchService/elasticsearchClient.js (content from previous script)
echo -e "  ${BLUE}🔍 Creating Elasticsearch client (src/services/searchService/elasticsearchClient.js)...${NC}"
cat <<EOT > src/services/searchService/elasticsearchClient.js
const { Client } = require('@elastic/elasticsearch');
const appConfig = require('../../config/app');

let esClientInstance = null;

if (appConfig.elasticsearch.node && process.env.NODE_ENV !== 'test_no_es') { // Allow disabling for specific test scenarios
  try {
    esClientInstance = new Client({
      node: appConfig.elasticsearch.node,
      requestTimeout: 5000, // Shorter timeout for responsiveness
      maxRetries: 3,
      // Add auth/cloud config if needed for production ES
    });
    // console.log('Elasticsearch client configured for node:', appConfig.elasticsearch.node);
  } catch (err) {
    console.error("Failed to initialize Elasticsearch client:", err);
    esClientInstance = null; // Ensure it's null if init fails
  }
}

async function ensureIndexExists(client, indexName, mapping = {}) {
  if (!client) { 
    // console.warn(\`ES Client not available, cannot ensure index \${indexName}\`);
    return;
  }
  try {
    const { body: exists } = await client.indices.exists({ index: indexName });
    if (!exists) {
      await client.indices.create({
        index: indexName,
        body: { mappings: mapping /*, settings: { ... } */ },
      });
      console.log(\`ES Index '\${indexName}' created successfully.\`);
    } else {
      // console.log(\`ES Index '\${indexName}' already exists.\`);
      // Optionally update mappings if they changed (be careful, can require reindex)
      // await client.indices.putMapping({ index: indexName, body: mapping });
    }
  } catch (error) {
    console.error(\`Error ensuring ES index '\${indexName}' exists:\`, error.meta ? error.meta.body : error);
  }
}

const defaultMappings = {
  properties: {
    id: { type: 'keyword' },
    createdAt: { type: 'date' },
    updatedAt: { type: 'date' },
  },
  dynamic_templates: [{
    strings_as_keywords_and_text: {
      match_mapping_type: 'string',
      mapping: {
        type: 'text',
        fields: { keyword: { type: 'keyword', ignore_above: 256 } },
      },
    },
  }],
};

module.exports = { esClient: esClientInstance, ensureIndexExists, defaultMappings };
EOT

# src/queues/index.js (content from previous script)
echo -e "  ${BLUE}🔄 Creating Queues setup (src/queues/index.js)...${NC}"
cat <<EOT > src/queues/index.js
const Bull = require('bull');
const path = require('path');
const fs = require('fs');
const appConfig = require('../config/app');

const queues = {};

const redisOptions = {
  redis: {
    host: appConfig.redis.host,
    port: appConfig.redis.port,
    password: appConfig.redis.password,
    maxRetriesPerRequest: 3, // ioredis option
  },
  defaultJobOptions: {
    attempts: 3,
    backoff: { type: 'exponential', delay: 5000 },
    removeOnComplete: true,
    removeOnFail: 1000, // Keep 1000 failed jobs, or use a duration like { age: 24 * 3600 }
  },
  // settings: { // Advanced Bull settings
  //   lockDuration: 30000, // Max time a job can be locked for (in ms)
  //   stalledInterval: 30000, // How often to check for stalled jobs (in ms)
  //   maxStalledCount: 1, // Max times a job can be restarted if it stalls
  // }
};

function initQueues(fastify) {
  const logger = fastify.log.child({ component: 'BullQueues' });
  const processorsDir = path.join(__dirname, 'processors');
  const queueNames = ['notifications', 'reporting', 'elasticsearch_bulk_index', 'email_sending']; // Added email

  queueNames.forEach(name => {
    const queue = new Bull(name, redisOptions);
    queues[name] = queue;
    logger.info(\`🐂 Bull queue '\${name}' initialized.\`);

    const processorPath = path.join(processorsDir, \`\${name}Processor.js\`);
    if (fs.existsSync(processorPath)) {
      const processorModule = require(processorPath);
      if (typeof processorModule === 'function') {
        // The concurrency factor can be adjusted based on job type and resources
        queue.process(Math.max(1, require('os').cpus().length / 2), async (job) => { // Concurrency based on CPU cores
          logger.info({ jobId: job.id, queue: name, data: job.data }, 'Job processing started.');
          const Sentry = require('@sentry/node');
          // Sentry.configureScope(scope => scope.setContext("job", { id: job.id, queue: name, data: job.data }));
          const span = process.env.SENTRY_DSN ? Sentry.startSpan({ name: \`Job: \${name}\`, op: 'queue.process' }) : null;
          try {
            if(span) {
              span.setAttribute('job.id', job.id);
              // span.setAttribute('job.data', JSON.stringify(job.data)); // Careful with large data
            }
            const result = await processorModule(job, fastify); // Pass fastify for access to services
            if(span) span.setStatus('ok');
            logger.info({ jobId: job.id, queue: name }, 'Job processing completed.');
            return result;
          } catch (error) {
            logger.error({ err: error, jobId: job.id, queue: name }, 'Job processing failed.');
            if(process.env.SENTRY_DSN) Sentry.captureException(error, { data: { jobId: job.id, jobData: job.data } });
            if(span) span.setStatus('internal_error');
            throw error; // Re-throw for Bull to handle retries/failure
          } finally {
            if(span) span.finish();
          }
        });
        logger.info(\`↳ Processor for '\${name}' queue loaded.\`);
      }
    } else {
      logger.warn(\`No processor found for '\${name}' queue.\`);
    }
    
    // Simplified logging for brevity
    queue.on('error', (error) => logger.error({ err: error, queue: name }, \`Bull queue '\${name}' error.\`));
    queue.on('failed', (job, err) => logger.error({ err, jobId: job.id, queue: name }, \`Job \${job.id} failed.\`));
    // queue.on('completed', (job, result) => logger.info({jobId: job.id, queue: name}, \`Job \${job.id} completed.\`));
  });
  return queues;
}

async function addJob(queueName, jobData, jobOptions = {}) {
  if (!queues[queueName]) {
    console.error(\`Queue '\${queueName}' does not exist.\`); // Use logger if available
    throw new Error(\`Queue '\${queueName}' does not exist.\`);
  }
  return queues[queueName].add(jobData, jobOptions);
}

module.exports = { initQueues, addJob };
EOT

# src/queues/processors/notificationsProcessor.js (content from previous script)
echo -e "  ${BLUE}🔄 Creating Notification Queue Processor...${NC}"
cat <<EOT > src/queues/processors/notificationsProcessor.js
// Example processor for the 'notifications' queue
module.exports = async (job, fastify) => {
  const { type, userId, title, message, data, deliveryMethods } = job.data;
  // Lazy require service to avoid circular dependencies if service uses queues
  const notificationServiceFactory = require('../../subsystems/notifications/notifications.service');
  const notificationService = notificationServiceFactory(fastify);

  fastify.log.info({ jobId: job.id, userId, type }, \`Processing notification job.\`);
  try {
    await notificationService.processAndSendNotification(
        userId, title, message, type, data, deliveryMethods || ['database', 'websocket']
    );
    return { success: true };
  } catch (error) {
    fastify.log.error({ err: error, jobId: job.id, userId }, 'Error processing notification job.');
    throw error;
  }
};
EOT

# src/queues/processors/reportingProcessor.js (content from previous script)
echo -e "  ${BLUE}🔄 Creating Reporting Queue Processor...${NC}"
cat <<EOT > src/queues/processors/reportingProcessor.js
module.exports = async (job, fastify) => {
  const { reportType, userId, params, reportRequestId } = job.data;
  const reportingServiceFactory = require('../../subsystems/reporting/reporting.service');
  const reportingService = reportingServiceFactory(fastify);

  fastify.log.info({ jobId: job.id, reportType, userId }, 'Processing report job.');
  try {
    const reportResult = await reportingService.generateAndStoreReport(reportType, params, userId, reportRequestId);
    
    if (userId && fastify.queues.notifications) {
      await fastify.queues.notifications.add({
        type: 'report_ready', userId,
        title: \`Your '\${reportType}' Report is Ready\`,
        message: \`The report (\${reportType}) is generated. ID: \${reportResult.reportId}\`,
        data: { reportId: reportResult.reportId, downloadUrl: reportResult.downloadUrl },
      });
    }
    return { success: true, reportId: reportResult.reportId, downloadUrl: reportResult.downloadUrl };
  } catch (error) {
    fastify.log.error({ err: error, jobId: job.id, reportType }, 'Error processing report job.');
    // TODO: Update report request status to 'failed' in DB
    throw error;
  }
};
EOT

# src/queues/processors/emailSendingProcessor.js (New)
echo -e "  ${BLUE}🔄 Creating Email Sending Queue Processor...${NC}"
cat <<EOT > src/queues/processors/emailSendingProcessor.js
module.exports = async (job, fastify) => {
  const { mailOptions } = job.data; // Expects { to, subject, text, html }
  const { mailService } = fastify;

  if (!mailService) {
    fastify.log.error({ jobId: job.id }, 'MailService not available for email sending job.');
    throw new Error('MailService not configured.');
  }
  
  fastify.log.info({ jobId: job.id, to: mailOptions.to, subject: mailOptions.subject }, 'Processing email sending job.');
  try {
    await mailService.sendMail(mailOptions);
    return { success: true };
  } catch (error) {
    fastify.log.error({ err: error, jobId: job.id, to: mailOptions.to }, 'Error processing email sending job.');
    throw error; // Bull will retry
  }
};
EOT


# src/subsystems/index.js (content from previous script)
echo -e "  ${BLUE}🔗 Creating subsystems loader (src/subsystems/index.js)...${NC}"
cat <<EOT > src/subsystems/index.js
const fs = require('fs');
const path = require('path');
const appConfig = require('../config/app');

module.exports = async function registerSubsystems(fastify) {
  const subsystemsDir = __dirname;
  const enabledSubsystems = [];

  const subsystemDirectories = fs.readdirSync(subsystemsDir)
    .filter(file => fs.statSync(path.join(subsystemsDir, file)).isDirectory());

  for (const subsystemName of subsystemDirectories) {
    const enableVarEnvKey = \`ENABLE_\${subsystemName.toUpperCase().replace(/-/g, '_')}\`;
    const isEnabled = (process.env[enableVarEnvKey] === 'true' || process.env[enableVarEnvKey] === undefined);

    if (isEnabled) {
      try {
        const subsystemIndexPath = path.join(subsystemsDir, subsystemName, 'index.js');
        if (fs.existsSync(subsystemIndexPath)) {
          const subsystemPlugin = require(subsystemIndexPath);
          await fastify.register(subsystemPlugin, { prefix: \`\${appConfig.apiBasePath}/\${subsystemName}\` });
          enabledSubsystems.push(subsystemName);
        } else {
          fastify.log.warn(\`Subsystem '\${subsystemName}' enabled but index.js not found at \${subsystemIndexPath}.\`);
        }
      } catch (error) {
        fastify.log.error({ err: error, subsystem: subsystemName }, \`Failed to load subsystem '\${subsystemName}'.\`);
      }
    } else {
      fastify.log.info(\`➖ Subsystem '\${subsystemName}' is disabled via \${enableVarEnvKey}.\`);
    }
  }
  fastify.log.info(\`✅ Loaded subsystems: \${enabledSubsystems.join(', ') || 'None'}\`);
};
EOT

# src/subsystems/auth/* (content from previous script - index, routes, service, schemas)
echo -e "  ${BLUE}🔑 Creating Auth subsystem...${NC}"
mkdir -p src/subsystems/auth
# src/subsystems/auth/index.js
cat <<EOT > src/subsystems/auth/index.js
const authRoutes = require('./auth.routes');
module.exports = async function authSubsystem(fastify, options) {
  fastify.register(authRoutes); // Routes define their own full path relative to API_BASE_PATH
  fastify.log.info('🔑 Auth subsystem routes registered.');
};
EOT
# src/subsystems/auth/auth.routes.js
cat <<EOT > src/subsystems/auth/auth.routes.js
const authServiceFactory = require('./auth.service');
const { registerSchema, loginSchema, refreshTokenSchema, forgotPasswordSchema, resetPasswordSchema } = require('./auth.schemas');

module.exports = async function authRoutes(fastify, options) {
  const service = authServiceFactory(fastify);

  fastify.post('/register', { schema: { body: registerSchema }, config: { isPublic: true } }, async (request, reply) => {
    const { user, tokens } = await service.registerUser(request.body);
    return reply.code(201).send({ message: 'User registered. Check email for verification.', user, ...tokens });
  });

  fastify.post('/login', { schema: { body: loginSchema }, config: { isPublic: true } }, async (request, reply) => {
    const { user, tokens } = await service.loginUser(request.body.emailOrUsername, request.body.password);
    return { message: 'Login successful', user, ...tokens };
  });

  fastify.post('/refresh-token', { schema: { body: refreshTokenSchema }, config: { isPublic: true } }, async (request, reply) => {
    const tokens = await service.refreshAccessToken(request.body.refreshToken);
    return { message: 'Token refreshed', ...tokens };
  });
  
  fastify.post('/logout', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    // await service.logoutUser(request.body.refreshToken || request.currentUser); // If blacklisting refresh tokens
    return reply.send({ message: 'Logout successful on server. Client should clear tokens.' });
  });

  fastify.get('/verify-email', { config: { isPublic: true } }, async (request, reply) => {
    const { token } = request.query;
    if (!token) throw fastify.httpErrors.badRequest('Verification token required.');
    await service.verifyEmail(token);
    // return reply.redirect(\`\${process.env.CLIENT_URL}/email-verified\`); // Or
    return { message: 'Email verified successfully.' };
  });

  fastify.post('/forgot-password', { schema: { body: forgotPasswordSchema }, config: { isPublic: true } }, async (request, reply) => {
    await service.forgotPassword(request.body.email);
    return { message: 'If account exists, password reset email sent.' };
  });

  fastify.post('/reset-password', { schema: { body: resetPasswordSchema }, config: { isPublic: true } }, async (request, reply) => {
    await service.resetPassword(request.body.token, request.body.newPassword);
    return { message: 'Password has been reset successfully.' };
  });
  
  fastify.get('/me', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const user = await fastify.db.User.findByPk(request.currentUser.id);
    if (!user) throw fastify.httpErrors.notFound('User not found.');
    return user;
  });
};
EOT
# src/subsystems/auth/auth.service.js
cat <<EOT > src/subsystems/auth/auth.service.js
const bcrypt = require('bcryptjs');
const crypto = require('crypto');
const jwt = require('jsonwebtoken');
const appConfig = require('../../config/app');

module.exports = (fastify) => {
  const { User, AuditLog } = fastify.db;
  const { queues } = fastify; // For sending emails via queue

  const generateTokens = async (userPayload) => {
    const cleanPayload = { id: userPayload.id, role: userPayload.role, username: userPayload.username };
    const accessToken = await fastify.jwt.sign(cleanPayload, { expiresIn: appConfig.jwt.expiresIn });
    const refreshToken = jwt.sign(cleanPayload, appConfig.jwt.refreshTokenSecret, { expiresIn: appConfig.jwt.refreshTokenExpiresIn });
    return { accessToken, refreshToken };
  };
  
  const sendEmailViaQueue = async (mailJobData) => {
    if (queues && queues.email_sending) {
        await queues.email_sending.add(mailJobData);
        fastify.log.info({ to: mailJobData.mailOptions.to, subject: mailJobData.mailOptions.subject }, 'Email job added to queue.');
    } else if (fastify.mailService) { // Fallback to direct sending if queue is not up (e.g. during tests or simple setups)
        fastify.log.warn('Email queue not available, sending email directly (fallback).');
        await fastify.mailService.sendMail(mailJobData.mailOptions);
    } else {
        fastify.log.error('Neither email queue nor mailService is available. Email not sent.');
    }
  };


  const registerUser = async (userData) => {
    if (await User.scope(null).findOne({ where: { email: userData.email } })) {
      throw fastify.httpErrors.conflict('Email already exists.');
    }
    if (await User.scope(null).findOne({ where: { username: userData.username } })) {
      throw fastify.httpErrors.conflict('Username already taken.');
    }

    const user = new User({ ...userData, status: 'pending_verification' });
    user.generateEmailVerificationToken();
    await user.save(); // Password hashing hook runs here

    try {
      await sendEmailViaQueue({
        mailOptions: {
          to: user.email, subject: 'Verify Your Email - Enterprise App',
          text: \`Hello \${user.username}, verify your email: \${process.env.CLIENT_URL}/verify-email?token=\${user.emailVerificationToken}\`,
          html: \`<p>Hello \${user.username},</p><p>Verify your email: <a href="\${process.env.CLIENT_URL}/verify-email?token=\${user.emailVerificationToken}">Verify</a></p>\`,
        }
      });
    } catch (err) {
      fastify.log.error({ err, userId: user.id }, "Failed to queue/send verification email during registration.");
    }

    const tokens = await generateTokens(user);
    return { user: user.toJSON(), tokens };
  };

  const loginUser = async (emailOrUsername, password) => {
    const user = await User.scope('withSensitiveInfo').findOne({
      where: { [fastify.db.Op.or]: [{ email: emailOrUsername }, { username: emailOrUsername }] },
    });

    if (!user || !(await user.validPassword(password))) {
      throw fastify.httpErrors.unauthorized('Invalid credentials.');
    }
    if (user.status === 'pending_verification') {
      throw fastify.httpErrors.forbidden('Email not verified.');
    }
    if (user.status === 'suspended') {
      throw fastify.httpErrors.forbidden('Account suspended.');
    }

    user.lastLoginAt = new Date();
    await user.save();
    await AuditLog.create({ userId: user.id, action: 'USER_LOGIN', ipAddress: fastify.ip });
    const tokens = await generateTokens(user);
    return { user: user.toJSON(), tokens };
  };

  const refreshAccessToken = async (refreshToken) => {
    try {
      const decoded = jwt.verify(refreshToken, appConfig.jwt.refreshTokenSecret);
      const user = await User.findByPk(decoded.id);
      if (!user || user.status !== 'active') {
        throw fastify.httpErrors.unauthorized('Invalid refresh token or user inactive.');
      }
      return generateTokens(user);
    } catch (err) {
      fastify.log.warn({ err }, "Refresh token verification failed.");
      throw fastify.httpErrors.unauthorized('Invalid or expired refresh token.');
    }
  };
  
  const verifyEmail = async (token) => {
    const user = await User.scope('withSensitiveInfo').findOne({ where: { emailVerificationToken: token } });
    if (!user) throw fastify.httpErrors.badRequest('Invalid or expired verification token.');
    
    user.emailVerifiedAt = new Date();
    user.emailVerificationToken = null;
    user.status = 'active';
    await user.save();
    fastify.log.info(\`Email verified for user \${user.id}\`);
    await AuditLog.create({ userId: user.id, action: 'USER_EMAIL_VERIFIED', ipAddress: fastify.ip });
  };

  const forgotPassword = async (email) => {
    const user = await User.findOne({ where: { email } });
    if (user) {
      user.generatePasswordResetToken();
      // Need to save without triggering password update hook if password field is not changed
      await User.scope('withSensitiveInfo').update(
        { passwordResetToken: user.passwordResetToken, passwordResetExpiresAt: user.passwordResetExpiresAt },
        { where: { id: user.id }, individualHooks: false } // Avoids password hash if not changed
      );
      try {
        await sendEmailViaQueue({
           mailOptions: {
            to: user.email, subject: 'Password Reset - Enterprise App',
            text: \`Password reset link: \${process.env.CLIENT_URL}/reset-password?token=\${user.passwordResetToken}\`,
            html: \`<p>Reset password: <a href="\${process.env.CLIENT_URL}/reset-password?token=\${user.passwordResetToken}">Reset</a></p>\`,
           }
        });
      } catch(err){ fastify.log.error({err, userId: user.id}, "Failed to queue/send password reset email"); }
    }
  };

  const resetPassword = async (token, newPassword) => {
    const user = await User.scope('withSensitiveInfo').findOne({
      where: { passwordResetToken: token, passwordResetExpiresAt: { [fastify.db.Op.gt]: new Date() } },
    });
    if (!user) throw fastify.httpErrors.badRequest('Invalid or expired reset token.');

    user.password = newPassword; // Hook will hash
    user.passwordResetToken = null;
    user.passwordResetExpiresAt = null;
    user.status = 'active'; // Reactivate if needed
    await user.save();
    fastify.log.info(\`Password reset for user \${user.id}\`);
    await AuditLog.create({ userId: user.id, action: 'USER_PASSWORD_RESET', ipAddress: fastify.ip });
  };

  return { registerUser, loginUser, refreshAccessToken, verifyEmail, forgotPassword, resetPassword };
};
EOT
# src/subsystems/auth/auth.schemas.js
cat <<EOT > src/subsystems/auth/auth.schemas.js
const Joi = require('joi');
const registerSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(30).required(),
  email: Joi.string().email().required(),
  password: Joi.string().min(8).required(),
  firstName: Joi.string().max(50).optional().allow(''),
  lastName: Joi.string().max(50).optional().allow(''),
});
const loginSchema = Joi.object({ emailOrUsername: Joi.string().required(), password: Joi.string().required() });
const refreshTokenSchema = Joi.object({ refreshToken: Joi.string().required() });
const forgotPasswordSchema = Joi.object({ email: Joi.string().email().required() });
const resetPasswordSchema = Joi.object({ token: Joi.string().required(), newPassword: Joi.string().min(8).required() });
module.exports = { registerSchema, loginSchema, refreshTokenSchema, forgotPasswordSchema, resetPasswordSchema };
EOT

# src/subsystems/users/* (content from previous script)
echo -e "  ${BLUE}👤 Creating Users subsystem...${NC}"
mkdir -p src/subsystems/users
# src/subsystems/users/index.js
cat <<EOT > src/subsystems/users/index.js
const usersRoutes = require('./users.routes');
module.exports = async function usersSubsystem(fastify, options) {
  fastify.register(usersRoutes);
  fastify.log.info('👤 Users subsystem routes registered.');
};
EOT
# src/subsystems/users/users.routes.js
cat <<EOT > src/subsystems/users/users.routes.js
const usersServiceFactory = require('./users.service');
const { updateUserSchema, listUsersSchema, updateUserStatusSchema } = require('./users.schemas');

module.exports = async function usersRoutes(fastify, options) {
  const service = usersServiceFactory(fastify);

  fastify.get('/', { schema: { querystring: listUsersSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin', 'manager'])] }, 
    async r => service.listUsers(r.query)
  );
  fastify.put('/me', { schema: { body: updateUserSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.updateUserProfile(r.currentUser.id, r.body, r.currentUser)
  );
  fastify.get('/:userId', { preHandler: [fastify.authenticate, fastify.checkRoles(['admin', 'manager'])] }, 
    async r => service.getUserProfile(r.params.userId)
  );
  fastify.put('/:userId', { schema: { body: updateUserSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin'])] }, 
    async r => service.updateUserProfile(r.params.userId, r.body, r.currentUser, true)
  );
  fastify.patch('/:userId/status', { schema: { body: updateUserStatusSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin'])] }, 
    async r => service.updateUserStatus(r.params.userId, r.body.status, r.currentUser)
  );
};
EOT
# src/subsystems/users/users.service.js
cat <<EOT > src/subsystems/users/users.service.js
const { Op } = require('sequelize'); // Or fastify.db.Op

module.exports = (fastify) => {
  const { User, AuditLog } = fastify.db;

  const listUsers = async (queryParams) => {
    const { limit = 10, offset = 0, sortBy = 'createdAt', sortOrder = 'DESC', search, role, status } = queryParams;
    const where = {};
    if (search) {
      where[Op.or] = [
        { username: { [Op.iLike]: \`%\${search}%\` } }, { email: { [Op.iLike]: \`%\${search}%\` } },
        { firstName: { [Op.iLike]: \`%\${search}%\` } }, { lastName: { [Op.iLike]: \`%\${search}%\` } },
      ];
    }
    if (role) where.role = role;
    if (status) where.status = status;
    const { count, rows } = await User.findAndCountAll({
      where, limit: parseInt(limit,10), offset: parseInt(offset,10), order: [[sortBy, sortOrder.toUpperCase()]],
    });
    return { total: count, users: rows, limit, offset };
  };

  const getUserProfile = async (userId) => {
    const user = await User.findByPk(userId);
    if (!user) throw fastify.httpErrors.notFound('User not found.');
    return user;
  };

  const updateUserProfile = async (targetUserId, data, actorUser, isAdminUpdate = false) => {
    const userToUpdate = await User.scope(isAdminUpdate ? 'withSensitiveInfo' : null).findByPk(targetUserId);
    if (!userToUpdate) throw fastify.httpErrors.notFound('User not found.');

    if (!isAdminUpdate) { // Non-admins cannot change role or status of others, or their own role/status directly
      delete data.role; delete data.status;
    }
    // Email change requires re-verification logic
    if (data.email && data.email !== userToUpdate.email) {
      if (await User.findOne({ where: {email: data.email, id: {[Op.ne]: targetUserId}} })) {
        throw fastify.httpErrors.conflict('Email already in use.');
      }
      userToUpdate.emailVerificationToken = null; // Invalidate old token
      userToUpdate.generateEmailVerificationToken();
      userToUpdate.emailVerifiedAt = null;
      userToUpdate.status = 'pending_verification'; // Force re-verify
      // TODO: Send new verification email
      fastify.log.info(\`User \${targetUserId} email changed to \${data.email}, requires re-verification.\`);
    }
    
    // Password should be handled by specific endpoint or ensure actor has rights
    if (data.password && !isAdminUpdate && targetUserId !== actorUser.id) {
        throw fastify.httpErrors.forbidden('Cannot change password for another user.');
    }
    if (!data.password) delete data.password; // Don't nullify password if not provided

    await userToUpdate.update(data);
    await AuditLog.create({ userId: actorUser.id, action: 'USER_PROFILE_UPDATE', entityType: 'User', entityId: userToUpdate.id, details: { updatedFields: Object.keys(data) }, ipAddress: fastify.ip });
    return userToUpdate.reload();
  };
  
  const updateUserStatus = async (targetUserId, status, actorUser) => {
    const userToUpdate = await User.findByPk(targetUserId);
    if (!userToUpdate) throw fastify.httpErrors.notFound('User not found.');
    const oldStatus = userToUpdate.status;
    await userToUpdate.update({ status });
    await AuditLog.create({ userId: actorUser.id, action: 'USER_STATUS_CHANGE', entityType: 'User', entityId: userToUpdate.id, details: { oldStatus, newStatus: status }, ipAddress: fastify.ip });
    return userToUpdate.reload();
  };

  return { listUsers, getUserProfile, updateUserProfile, updateUserStatus };
};
EOT
# src/subsystems/users/users.schemas.js
cat <<EOT > src/subsystems/users/users.schemas.js
const Joi = require('joi');
const listUsersSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(10), offset: Joi.number().integer().min(0).default(0),
  sortBy: Joi.string().default('createdAt'), sortOrder: Joi.string().uppercase().valid('ASC', 'DESC').default('DESC'),
  search: Joi.string().optional().allow(''),
  role: Joi.string().valid('user', 'manager', 'admin', 'developer', 'guest').optional(),
  status: Joi.string().valid('active', 'inactive', 'suspended', 'pending_verification').optional(),
});
const updateUserSchema = Joi.object({
  username: Joi.string().alphanum().min(3).max(30).optional(),
  email: Joi.string().email().optional(), // Email change is complex, handle in service
  password: Joi.string().min(8).optional(), // Password change should be separate or require current password
  firstName: Joi.string().max(50).allow('').optional(), lastName: Joi.string().max(50).allow('').optional(),
  avatarUrl: Joi.string().uri().allow('').optional(), timezone: Joi.string().optional(), locale: Joi.string().optional(),
  // Admin only fields (service layer should enforce this):
  role: Joi.string().valid('user', 'manager', 'admin', 'developer', 'guest').optional(),
  // status: Joi.string().valid('active', 'inactive', 'suspended', 'pending_verification').optional(), // status via dedicated endpoint
}).min(1);
const updateUserStatusSchema = Joi.object({ status: Joi.string().valid('active', 'inactive', 'suspended').required() });
module.exports = { listUsersSchema, updateUserSchema, updateUserStatusSchema };
EOT

# src/subsystems/tasks/* (content from previous script)
echo -e "  ${BLUE}✔️  Creating Tasks subsystem...${NC}"
mkdir -p src/subsystems/tasks
# src/subsystems/tasks/index.js
cat <<EOT > src/subsystems/tasks/index.js
const tasksRoutes = require('./tasks.routes');
module.exports = async function tasksSubsystem(fastify, options) {
  fastify.register(tasksRoutes);
  fastify.log.info('✔️ Tasks subsystem routes registered.');
};
EOT
# src/subsystems/tasks/tasks.routes.js
cat <<EOT > src/subsystems/tasks/tasks.routes.js
const tasksServiceFactory = require('./tasks.service');
const { createTaskSchema, updateTaskSchema, listTasksSchema, assignTaskSchema } = require('./tasks.schemas');

module.exports = async function tasksRoutes(fastify, options) {
  const service = tasksServiceFactory(fastify);
  fastify.post('/', { schema: { body: createTaskSchema }, preHandler: [fastify.authenticate] }, 
    async (r, reply) => reply.code(201).send(await service.createTask(r.currentUser, r.body))
  );
  fastify.get('/', { schema: { querystring: listTasksSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.listTasks(r.query, r.currentUser)
  );
  fastify.get('/:taskId', { preHandler: [fastify.authenticate] }, 
    async r => service.getTaskById(r.params.taskId, r.currentUser)
  );
  fastify.put('/:taskId', { schema: { body: updateTaskSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.updateTask(r.params.taskId, r.body, r.currentUser)
  );
  fastify.delete('/:taskId', { preHandler: [fastify.authenticate] }, 
    async (r, reply) => { await service.deleteTask(r.params.taskId, r.currentUser); return reply.code(204).send(); }
  );
  fastify.patch('/:taskId/assign', { schema: { body: assignTaskSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin', 'manager'])] },
    async r => service.assignTask(r.params.taskId, r.body.assigneeId, r.currentUser)
  );
};
EOT
# src/subsystems/tasks/tasks.service.js
cat <<EOT > src/subsystems/tasks/tasks.service.js
const { Op } = require('sequelize'); // Or fastify.db.Op

module.exports = (fastify) => {
  const { Task, User, AuditLog } = fastify.db;
  const { queues } = fastify;

  const createTask = async (actorUser, taskData) => {
    const task = await Task.create({ ...taskData, creatorId: actorUser.id });
    await AuditLog.create({ userId: actorUser.id, action: 'TASK_CREATE', entityType: 'Task', entityId: task.id, details: { title: task.title }, ipAddress: fastify.ip });
    if (task.assigneeId && task.assigneeId !== actorUser.id && queues.notifications) {
      queues.notifications.add({
        type: 'task_assigned', userId: task.assigneeId, title: 'New Task Assigned',
        message: \`Task "\${task.title}" assigned by \${actorUser.username}.\`,
        data: { taskId: task.id }, deliveryMethods: ['database', 'websocket', 'email'],
      });
    }
    return task;
  };

  const listTasks = async (queryParams, actorUser) => {
    const { limit = 10, offset = 0, sortBy = 'createdAt', sortOrder = 'DESC', status, priority, assigneeId, creatorId, search } = queryParams;
    const where = {};
    if (!['admin', 'manager'].includes(actorUser.role)) {
      where[Op.or] = [{ assigneeId: actorUser.id }, { creatorId: actorUser.id }];
    } else { // Admins/Managers can filter freely
      if (assigneeId) where.assigneeId = assigneeId;
      if (creatorId) where.creatorId = creatorId;
    }
    if (status) where.status = status;
    if (priority) where.priority = priority;
    if (search) where.title = { [Op.iLike]: \`%\${search}%\` };

    const { count, rows } = await Task.findAndCountAll({
      where, include: [
        { model: User, as: 'assignee', attributes: ['id', 'username'] },
        { model: User, as: 'creator', attributes: ['id', 'username'] },
      ], limit: parseInt(limit,10), offset: parseInt(offset,10), order: [[sortBy, sortOrder.toUpperCase()]],
    });
    return { total: count, tasks: rows, limit, offset };
  };

  const getTaskById = async (taskId, actorUser) => {
    const task = await Task.findByPk(taskId, { include: [{ model: User, as: 'assignee' }, { model: User, as: 'creator' }] });
    if (!task) throw fastify.httpErrors.notFound('Task not found.');
    if (!['admin', 'manager'].includes(actorUser.role) && task.assigneeId !== actorUser.id && task.creatorId !== actorUser.id) {
      throw fastify.httpErrors.forbidden('Access to this task denied.');
    }
    return task;
  };

  const updateTask = async (taskId, updateData, actorUser) => {
    const task = await getTaskById(taskId, actorUser); // Auth check done in getTaskById
    const oldAssigneeId = task.assigneeId;
    const oldStatus = task.status;
    await task.update(updateData);
    await AuditLog.create({ userId: actorUser.id, action: 'TASK_UPDATE', entityType: 'Task', entityId: task.id, details: { updatedFields: Object.keys(updateData) }, ipAddress: fastify.ip });
    
    if (task.assigneeId && task.assigneeId !== oldAssigneeId && queues.notifications) {
      queues.notifications.add({
        type: 'task_assigned', userId: task.assigneeId, title: 'Task Re-assigned',
        message: \`Task "\${task.title}" assigned to you.\`, data: { taskId: task.id },
      });
    }
    if (task.status !== oldStatus && queues.notifications) {
      const notifyUserIds = new Set();
      if (task.creatorId && task.creatorId !== actorUser.id) notifyUserIds.add(task.creatorId);
      if (task.assigneeId && task.assigneeId !== actorUser.id) notifyUserIds.add(task.assigneeId);
      notifyUserIds.forEach(uid => queues.notifications.add({
        type: 'task_updated', userId: uid, title: \`Task "\${task.title}" Updated\`,
        message: \`Status changed to \${task.status} by \${actorUser.username}.\`, data: { taskId: task.id },
      }));
    }
    return task.reload({ include: [{ model: User, as: 'assignee' }, { model: User, as: 'creator' }] });
  };

  const deleteTask = async (taskId, actorUser) => {
    const task = await getTaskById(taskId, actorUser); // Auth check
    if (!['admin', 'manager'].includes(actorUser.role) && task.creatorId !== actorUser.id) {
        throw fastify.httpErrors.forbidden('Only creator or admin can delete this task.');
    }
    await task.destroy(); // Soft delete
    await AuditLog.create({ userId: actorUser.id, action: 'TASK_DELETE', entityType: 'Task', entityId: task.id, ipAddress: fastify.ip });
  };
  
  const assignTask = async (taskId, newAssigneeId, actorUser) => {
    const task = await getTaskById(taskId, actorUser); // Basic auth check
    if (!await User.findByPk(newAssigneeId)) throw fastify.httpErrors.notFound('Assignee user not found.');
    
    const oldAssigneeId = task.assigneeId;
    await task.update({ assigneeId: newAssigneeId });
    await AuditLog.create({ userId: actorUser.id, action: 'TASK_ASSIGN', entityType: 'Task', entityId: task.id, details: { oldAssigneeId, newAssigneeId }, ipAddress: fastify.ip });
    if (newAssigneeId !== oldAssigneeId && queues.notifications) {
      queues.notifications.add({
        type: 'task_assigned', userId: newAssigneeId, title: 'Task Assignment',
        message: \`Task "\${task.title}" assigned to you by \${actorUser.username}.\`, data: { taskId: task.id },
      });
      if (oldAssigneeId) queues.notifications.add({
        type: 'task_unassigned', userId: oldAssigneeId, title: 'Task Unassigned',
        message: \`Task "\${task.title}" unassigned from you.\`, data: { taskId: task.id },
      });
    }
    return task.reload({ include: [{ model: User, as: 'assignee' }, { model: User, as: 'creator' }] });
  };

  return { createTask, listTasks, getTaskById, updateTask, deleteTask, assignTask };
};
EOT
# src/subsystems/tasks/tasks.schemas.js
cat <<EOT > src/subsystems/tasks/tasks.schemas.js
const Joi = require('joi');
const taskStatusEnum = ['todo', 'in_progress', 'in_review', 'blocked', 'done', 'archived'];
const taskPriorityEnum = ['low', 'medium', 'high', 'critical'];
const createTaskSchema = Joi.object({
  title: Joi.string().min(3).max(255).required(), description: Joi.string().allow('').optional(),
  status: Joi.string().valid(...taskStatusEnum).default('todo'), priority: Joi.string().valid(...taskPriorityEnum).default('medium'),
  dueDate: Joi.date().iso().optional().allow(null), assigneeId: Joi.string().uuid().optional().allow(null),
  tags: Joi.array().items(Joi.string()).optional(),
});
const updateTaskSchema = Joi.object({
  title: Joi.string().min(3).max(255).optional(), description: Joi.string().allow('').optional(),
  status: Joi.string().valid(...taskStatusEnum).optional(), priority: Joi.string().valid(...taskPriorityEnum).optional(),
  dueDate: Joi.date().iso().optional().allow(null), assigneeId: Joi.string().uuid().optional().allow(null),
  tags: Joi.array().items(Joi.string()).optional(),
  completedAt: Joi.date().iso().when('status', { is: 'done', then: Joi.optional(), otherwise: Joi.forbidden() }).allow(null),
}).min(1);
const listTasksSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(10), offset: Joi.number().integer().min(0).default(0),
  sortBy: Joi.string().valid('createdAt', 'updatedAt', 'dueDate', 'title', 'status', 'priority').default('createdAt'),
  sortOrder: Joi.string().uppercase().valid('ASC', 'DESC').default('DESC'),
  status: Joi.string().valid(...taskStatusEnum).optional(), priority: Joi.string().valid(...taskPriorityEnum).optional(),
  assigneeId: Joi.string().uuid().optional(), creatorId: Joi.string().uuid().optional(),
  search: Joi.string().optional().allow(''),
});
const assignTaskSchema = Joi.object({ assigneeId: Joi.string().uuid().required() });
module.exports = { createTaskSchema, updateTaskSchema, listTasksSchema, assignTaskSchema };
EOT

# src/subsystems/notifications/* (content from previous script)
echo -e "  ${BLUE}🔔 Creating Notifications subsystem...${NC}"
mkdir -p src/subsystems/notifications
# src/subsystems/notifications/index.js
cat <<EOT > src/subsystems/notifications/index.js
const notificationsRoutes = require('./notifications.routes');
module.exports = async function notificationsSubsystem(fastify, options) {
  fastify.register(notificationsRoutes);
  fastify.log.info('🔔 Notifications subsystem routes registered.');
};
EOT
# src/subsystems/notifications/notifications.routes.js
cat <<EOT > src/subsystems/notifications/notifications.routes.js
const notificationsServiceFactory = require('./notifications.service');
const { listNotificationsSchema, markNotificationSchema, pushSubscriptionSchema, testPushSchema } = require('./notifications.schemas');

module.exports = async function notificationRoutes(fastify, options) {
  const service = notificationsServiceFactory(fastify);
  fastify.get('/', { schema: { querystring: listNotificationsSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.getUserNotifications(r.currentUser.id, r.query)
  );
  fastify.patch('/:notificationId/read', { schema: { params: markNotificationSchema }, preHandler: [fastify.authenticate] }, 
    async r => { await service.markNotificationAsRead(r.params.notificationId, r.currentUser.id); return { success: true }; }
  );
  fastify.patch('/read-all', { preHandler: [fastify.authenticate] }, 
    async r => ({ success: true, count: await service.markAllNotificationsAsRead(r.currentUser.id) })
  );
  fastify.post('/subscribe-webpush', { schema: { body: pushSubscriptionSchema }, preHandler: [fastify.authenticate] }, 
    async r => { await service.saveWebPushSubscription(r.currentUser.id, r.body.subscription); return { success: true }; }
  );
  fastify.post('/unsubscribe-webpush', { schema: { body: Joi.object({endpoint: Joi.string().uri().required()}) }, preHandler: [fastify.authenticate] }, // Joi inline for brevity
    async r => { await service.removeWebPushSubscription(r.currentUser.id, r.body.endpoint); return { success: true }; }
  );
  fastify.post('/test-push', { schema: { body: testPushSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin', 'developer'])] },
    async r => { await service.sendTestPushNotification(r.currentUser.id, r.body.title, r.body.message, r.body.deliveryMethods); return { success: true }; }
  );
};
EOT
# src/subsystems/notifications/notifications.service.js
cat <<EOT > src/subsystems/notifications/notifications.service.js
const webPush = require('web-push');
const appConfig = require('../../config/app');

// In-memory store for demo; use DB (UserPushSubscription model) in production
const userPushSubscriptionsStore = new Map(); 

module.exports = (fastify) => {
  const { Notification, User } = fastify.db;
  const { mailService, wsService } = fastify;
  const logger = fastify.log.child({ service: 'NotificationService' });

  if (appConfig.pushNotifications.vapidDetails.publicKey && appConfig.pushNotifications.vapidDetails.privateKey) {
    webPush.setVapidDetails(
      appConfig.pushNotifications.vapidDetails.subject,
      appConfig.pushNotifications.vapidDetails.publicKey,
      appConfig.pushNotifications.vapidDetails.privateKey
    );
    logger.info('Web Push VAPID details configured.');
  } else {
    logger.warn('Web Push VAPID details not configured. Web push notifications will not work.');
  }
  
  const processAndSendNotification = async (userId, title, message, type, data, deliveryMethods = ['database', 'websocket']) => {
    const user = await User.findByPk(userId);
    if (!user) { logger.warn(\`User \${userId} not found for notification.\`); return; }

    let dbNotification;
    if (deliveryMethods.includes('database')) {
      dbNotification = await Notification.create({ userId, type, title, message, data });
      logger.info({ userId, type, notificationId: dbNotification.id }, 'Notification stored in DB.');
    }

    if (deliveryMethods.includes('websocket') && wsService) {
      wsService.sendToUser(userId, { event: 'new_notification', payload: dbNotification || { type, title, message, data, createdAt: new Date() } });
      logger.info({ userId, type }, 'Notification sent via WebSocket.');
    }
    
    if (deliveryMethods.includes('email') && mailService) {
      try {
        await mailService.sendMail({ to: user.email, subject: \`[EntApp] \${title}\`, text: message, html: \`<p>\${message}</p>\` });
        logger.info({ userId, type }, 'Notification sent via Email.');
      } catch (err) { logger.error({ err, userId }, "Failed to send notification email"); }
    }

    if (deliveryMethods.includes('webpush')) {
      await sendWebPushNotification(userId, title, message, data);
    }
    return dbNotification;
  };

  const getUserNotifications = async (userId, { limit = 10, offset = 0, readStatus }) => {
    const where = { userId };
    if (readStatus === 'read') where.isRead = true;
    if (readStatus === 'unread') where.isRead = false;
    const { count, rows } = await Notification.findAndCountAll({
      where, limit: parseInt(limit,10), offset: parseInt(offset,10), order: [['createdAt', 'DESC']],
    });
    return { total: count, notifications: rows, limit, offset };
  };

  const markNotificationAsRead = async (notificationId, userId) => {
    const [affectedCount] = await Notification.update({ isRead: true, readAt: new Date() }, { where: { id: notificationId, userId, isRead: false } });
    if (affectedCount === 0) {
        const exists = await Notification.findOne({ where: {id: notificationId, userId}});
        if (!exists) throw fastify.httpErrors.notFound('Notification not found.');
        // else it was already read or doesn't belong to user
    }
  };

  const markAllNotificationsAsRead = async (userId) => {
    const [affectedCount] = await Notification.update({ isRead: true, readAt: new Date() }, { where: { userId, isRead: false } });
    return affectedCount;
  };
  
  const saveWebPushSubscription = async (userId, subscription) => {
    // PROD: Save to DB UserPushSubscription table, handling duplicates by endpoint
    if (!userPushSubscriptionsStore.has(userId.toString())) userPushSubscriptionsStore.set(userId.toString(), []);
    const userSubs = userPushSubscriptionsStore.get(userId.toString());
    if (!userSubs.find(s => s.endpoint === subscription.endpoint)) {
      userSubs.push(subscription);
      logger.info({ userId, endpoint: subscription.endpoint }, 'Web push subscription saved (in-memory).');
    }
  };

  const removeWebPushSubscription = async (userId, endpoint) => {
    // PROD: Remove from DB
    if (userPushSubscriptionsStore.has(userId.toString())) {
      let userSubs = userPushSubscriptionsStore.get(userId.toString());
      userSubs = userSubs.filter(s => s.endpoint !== endpoint);
      userPushSubscriptionsStore.set(userId.toString(), userSubs);
      logger.info({ userId, endpoint }, 'Web push subscription removed (in-memory).');
    }
  };
  
  const sendWebPushNotification = async (userId, title, body, data = {}) => {
    if (!appConfig.pushNotifications.vapidDetails.publicKey) { logger.warn('Web push VAPID keys not set.'); return; }
    const subscriptions = userPushSubscriptionsStore.get(userId.toString()) || []; // PROD: Fetch from DB
    if (subscriptions.length === 0) { logger.info({userId}, 'No web push subscriptions for user.'); return; }

    const payload = JSON.stringify({ title, body, data, icon: '/icons/icon-192x192.png' });
    const promises = subscriptions.map(sub =>
      webPush.sendNotification(sub, payload)
        .then(() => logger.info({ userId, endpoint: sub.endpoint.slice(0,30) }, 'Web push sent.'))
        .catch(err => {
          logger.error({ err, userId, endpoint: sub.endpoint }, 'Error sending web push.');
          if (err.statusCode === 404 || err.statusCode === 410) removeWebPushSubscription(userId, sub.endpoint);
        })
    );
    await Promise.allSettled(promises);
  };
  
  const sendTestPushNotification = async (userId, title, message, deliveryMethods = ['webpush']) => {
    logger.info({userId, title, deliveryMethods}, "Sending test push notification.");
    if(deliveryMethods.includes('webpush')) await sendWebPushNotification(userId, title, message, { test: true });
    // Add other test methods
  };

  return { processAndSendNotification, getUserNotifications, markNotificationAsRead, markAllNotificationsAsRead, saveWebPushSubscription, removeWebPushSubscription, sendTestPushNotification };
};
EOT
# src/subsystems/notifications/notifications.schemas.js
cat <<EOT > src/subsystems/notifications/notifications.schemas.js
const Joi = require('joi');
const listNotificationsSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(50).default(10),
  offset: Joi.number().integer().min(0).default(0),
  readStatus: Joi.string().valid('all', 'read', 'unread').default('all'),
});
const markNotificationSchema = Joi.object({ notificationId: Joi.string().uuid().required() });
const pushSubscriptionSchema = Joi.object({
  subscription: Joi.object({ // Basic structure of a PushSubscription
    endpoint: Joi.string().uri().required(),
    keys: Joi.object({ p256dh: Joi.string().required(), auth: Joi.string().required() }).required(),
  }).required(),
});
const testPushSchema = Joi.object({
  title: Joi.string().default('Test Push'),
  message: Joi.string().default('This is a test push notification from the server!'),
  deliveryMethods: Joi.array().items(Joi.string().valid('webpush', 'email', 'database', 'websocket')).default(['webpush'])
});
module.exports = { listNotificationsSchema, markNotificationSchema, pushSubscriptionSchema, testPushSchema };
EOT

# src/subsystems/search/* (content from previous script)
echo -e "  ${BLUE}🔍 Creating Search subsystem (Elasticsearch integrated)...${NC}"
mkdir -p src/subsystems/search
# src/subsystems/search/index.js
cat <<EOT > src/subsystems/search/index.js
const searchRoutes = require('./search.routes');
module.exports = async function searchSubsystem(fastify, options) {
  if (!fastify.elasticsearch && process.env.ENABLE_SEARCH === 'true') {
    fastify.log.warn('Elasticsearch client not available. Search subsystem may be limited or disabled.');
    // return; // Optionally disable routes if ES is critical
  }
  fastify.register(searchRoutes);
  fastify.log.info('🔍 Search subsystem routes registered.');
};
EOT
# src/subsystems/search/search.routes.js
cat <<EOT > src/subsystems/search/search.routes.js
const searchServiceFactory = require('./search.service');
const { simpleSearchSchema, advancedSearchSchema, reindexSchema } = require('./search.schemas');

module.exports = async function searchRoutes(fastify, options) {
  const service = searchServiceFactory(fastify);
  fastify.get('/', { schema: { querystring: simpleSearchSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.simpleSearch(r.query.q, r.query.types, r.query)
  );
  fastify.post('/advanced', { schema: { body: advancedSearchSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.advancedSearch(r.body)
  );
  fastify.post('/reindex', { schema: { body: reindexSchema }, preHandler: [fastify.authenticate, fastify.checkRoles(['admin'])] },
    async (r, reply) => {
      // Reindexing should be a background job for large datasets
      const result = await service.reindexData(r.body.modelName);
      return { message: 'Reindexing process completed (synchronously for now).', details: result };
    }
  );
};
EOT
# src/subsystems/search/search.service.js
cat <<EOT > src/subsystems/search/search.service.js
const { ensureIndexExists, defaultMappings } = require('../../services/searchService/elasticsearchClient'); // Correct path
const appConfig = require('../../config/app');

module.exports = (fastify) => {
  const { elasticsearch: esClient, db } = fastify;
  const logger = fastify.log.child({ service: 'SearchService' });

  const getSearchableModelsMap = () => {
    const map = new Map();
    // Ensure model names are consistent (e.g., 'User', 'Task')
    if (db.User) map.set('user', { model: db.User, fields: ['username', 'email', 'firstName', 'lastName'] });
    if (db.Task) map.set('task', { model: db.Task, fields: ['title', 'description', 'tags'] });
    if (db.File) map.set('file', { model: db.File, fields: ['originalName', 'mimeType'] });
    // Add other models
    return map;
  };

  const simpleSearch = async (query, typesArray, options = {}) => {
    if (!esClient) { logger.warn('ES not available for simpleSearch.'); return { error: 'Search unavailable', results: [] }; }
    if (!query) return { results: [], message: 'Query "q" is required.' };

    const limit = parseInt(options.limit, 10) || 10;
    const offset = parseInt(options.offset, 10) || 0;
    const searchableModelsMap = getSearchableModelsMap();
    let indicesToSearch = [];

    if (typesArray && typesArray.length > 0) {
      indicesToSearch = typesArray.map(type => {
        const modelInfo = searchableModelsMap.get(type.toLowerCase());
        return modelInfo ? modelInfo.model.getSearchIndexName() : null;
      }).filter(Boolean);
    } else {
      indicesToSearch = Array.from(searchableModelsMap.values()).map(m => m.model.getSearchIndexName());
    }

    if (indicesToSearch.length === 0) return { results: [], message: 'No valid types for search.' };

    try {
      // Construct fields to search across all specified indices/types
      const fieldsToQuery = [];
      searchableModelsMap.forEach((modelInfo, typeKey) => {
          if(indicesToSearch.includes(modelInfo.model.getSearchIndexName())) {
            modelInfo.fields.forEach(field => fieldsToQuery.push(field)); // Simple field names
            // For more specific targeting: fieldsToQuery.push(\`\${typeKey}.\${field}\`); // If fields are namespaced in ES doc
          }
      });
      const uniqueFields = [...new Set(fieldsToQuery)];


      const { body } = await esClient.search({
        index: indicesToSearch.join(','), from: offset, size: limit,
        body: {
          query: {
            multi_match: { query, fields: uniqueFields.length > 0 ? uniqueFields : ['*'], type: 'best_fields', fuzziness: "AUTO" },
          },
          // sort: options.sortBy ? [{ [options.sortBy]: options.sortOrder || 'asc' }] : ['_score'],
        },
      });
      return {
        total: body.hits.total.value,
        hits: body.hits.hits.map(h => ({ score: h._score, type: searchableModelsMap.get(h._index.replace(appConfig.elasticsearch.indexPrefix, ''))?.model.name || h._index, id: h._id, source: h._source })),
        limit, offset,
      };
    } catch (error) {
      logger.error({ err: error, query, typesArray }, 'ES simple search failed.');
      if (error.meta && error.meta.body && error.meta.body.error && error.meta.body.error.type === 'index_not_found_exception') {
          return { error: 'One or more search indices not found. Reindexing may be required.', results: [] };
      }
      throw fastify.httpErrors.internalServerError('Search failed.');
    }
  };

  const advancedSearch = async (searchBody) => {
    if (!esClient) { logger.warn('ES not available for advancedSearch.'); return { error: 'Search unavailable', results: [] }; }
    try {
      const { body } = await esClient.search(searchBody); // searchBody should be { index: 'idx1,idx2', body: { query: ... } }
      return {
        total: body.hits.total.value,
        hits: body.hits.hits.map(h => ({ score: h._score, type: h._index.replace(appConfig.elasticsearch.indexPrefix, ''), id: h._id, source: h._source })),
      };
    } catch (error) { logger.error({ err: error, searchBody }, 'ES advanced search failed.'); throw fastify.httpErrors.internalServerError('Adv search failed.'); }
  };
  
  const reindexData = async (specificModelKey = null) => {
    if (!esClient) return { error: 'ES not configured for reindexing.' };
    logger.info(\`Reindexing started for: \${specificModelKey || 'all models'}\`);
    const results = {};
    const searchableModelsMap = getSearchableModelsMap();

    for (const [modelKey, modelInfo] of searchableModelsMap) {
      if (specificModelKey && modelKey.toLowerCase() !== specificModelKey.toLowerCase()) continue;

      const indexName = modelInfo.model.getSearchIndexName();
      logger.info(\`Reindexing model: \${modelInfo.model.name} into index: \${indexName}\`);
      
      try {
        const modelMapping = modelInfo.mapping || defaultMappings;
        await ensureIndexExists(esClient, indexName, modelMapping);

        let offset = 0; const batchSize = 100; let itemsProcessed = 0; let hasMore = true;
        while(hasMore) {
          const items = await modelInfo.model.findAll({ limit: batchSize, offset, paranoid: false }); // Include soft-deleted if paranoid
          if (items.length === 0) { hasMore = false; break; }

          const bulkOps = [];
          for (const item of items) {
            const doc = await item.toSearchableDocument();
            if (item.deletedAt && modelInfo.model.options.paranoid) { // Handle soft deletes: either remove or mark as deleted
                 bulkOps.push({ delete: { _index: indexName, _id: item.id.toString() } });
            } else {
                bulkOps.push({ index: { _index: indexName, _id: item.id.toString() } });
                bulkOps.push(doc);
            }
          }
          if (bulkOps.length > 0) {
            const { body: bulkResponse } = await esClient.bulk({ refresh: false, body: bulkOps });
            if (bulkResponse.errors) { /* ... error handling ... */ logger.error({errors: bulkResponse.items.filter(i=>i.index && i.index.error)}, \`ES bulk errors for \${modelInfo.model.name}\`); }
            itemsProcessed += items.length; // More accurately, count successful operations from bulkResponse
          }
          offset += items.length;
          if (itemsProcessed % (batchSize * 5) === 0) logger.info(\`Indexed \${itemsProcessed} \${modelInfo.model.name} documents...\`);
        }
        results[modelInfo.model.name] = { status: 'success', indexed: itemsProcessed, index: indexName };
        logger.info(\`Finished reindexing for \${modelInfo.model.name}. Total: \${itemsProcessed}\`);
      } catch (error) {
        logger.error({ err: error, model: modelInfo.model.name }, \`Error reindexing \${modelInfo.model.name}\`);
        results[modelInfo.model.name] = { status: 'failed', error: error.message };
      }
    }
    logger.info('Reindexing process completed.');
    return results;
  };

  return { simpleSearch, advancedSearch, reindexData };
};
EOT
# src/subsystems/search/search.schemas.js
cat <<EOT > src/subsystems/search/search.schemas.js
const Joi = require('joi');
const simpleSearchSchema = Joi.object({
  q: Joi.string().min(1).required(),
  types: Joi.string().optional(), // Comma-separated list of types (e.g., user,task)
  limit: Joi.number().integer().min(1).max(100).default(10),
  offset: Joi.number().integer().min(0).default(0),
  sortBy: Joi.string().optional(), // e.g., _score, createdAt
  sortOrder: Joi.string().valid('asc', 'desc').optional(),
});
const advancedSearchSchema = Joi.object({ // This would mirror ES request body structure
  index: Joi.string().required(), // Comma-separated indices
  body: Joi.object().required(),  // ES query DSL
  // Other ES params like size, from, sort can be included here
});
const reindexSchema = Joi.object({
  modelName: Joi.string().optional(), // Specific model to reindex, or all if null
});
module.exports = { simpleSearchSchema, advancedSearchSchema, reindexSchema };
EOT

# src/subsystems/files/* (content from previous script)
echo -e "  ${BLUE}💾 Creating Files subsystem...${NC}"
mkdir -p src/subsystems/files
# src/subsystems/files/index.js
cat <<EOT > src/subsystems/files/index.js
const filesRoutes = require('./files.routes');
module.exports = async function filesSubsystem(fastify, options) {
  fastify.register(filesRoutes);
  fastify.log.info('💾 Files subsystem routes registered.');
};
EOT
# src/subsystems/files/files.routes.js
cat <<EOT > src/subsystems/files/files.routes.js
const filesServiceFactory = require('./files.service');
const { listFilesSchema, uploadFileSchema } = require('./files.schemas'); // Define these

module.exports = async function filesRoutes(fastify, options) {
  const service = filesServiceFactory(fastify);

  fastify.post('/upload', { 
    // schema: { consumes: ['multipart/form-data'], body: uploadFileSchema }, // Schema for metadata part
    preHandler: [fastify.authenticate] 
  }, async (request, reply) => {
    // @fastify/multipart automatically handles the stream if not using `request.file()`
    // If attachFieldsToBody is 'keyValues', fields are in request.body.file (or other field names)
    const filePart = request.body.file; // Assuming 'file' is the field name for the file
    if (!filePart || !filePart.filename) { // Check if filePart is a valid file object
        return reply.code(400).send({ error: 'No file uploaded or invalid multipart request. Expecting "file" field.' });
    }
    const metadata = request.body.metadata ? JSON.parse(request.body.metadata) : {};
    const fileRecord = await service.uploadFile(request.currentUser.id, filePart, metadata);
    return reply.code(201).send(fileRecord);
  });

  fastify.get('/', { schema: { querystring: listFilesSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.listFiles(r.query, r.currentUser)
  );
  fastify.get('/:fileId/meta', { preHandler: [fastify.authenticate] }, 
    async r => service.getFileMetadata(r.params.fileId, r.currentUser)
  );
  fastify.get('/:fileId/download', { preHandler: [fastify.authenticate] }, async (request, reply) => {
    const { stream, fileRecord } = await service.downloadFile(request.params.fileId, request.currentUser);
    reply.header('Content-Disposition', \`attachment; filename="\${encodeURIComponent(fileRecord.originalName)}"\`);
    reply.header('Content-Type', fileRecord.mimeType);
    reply.header('Content-Length', fileRecord.size);
    return reply.send(stream);
  });
  fastify.delete('/:fileId', { preHandler: [fastify.authenticate] }, 
    async (r, reply) => { await service.deleteFile(r.params.fileId, r.currentUser); return reply.code(204).send(); }
  );
};
EOT
# src/subsystems/files/files.service.js
cat <<EOT > src/subsystems/files/files.service.js
const fsPromises = require('node:fs/promises');
const fsSync = require('node:fs');
const path = require('path');
const crypto = require('crypto');
const sharp = require('sharp');
const appConfig = require('../../config/app');
const { Op } = require('sequelize');

module.exports = (fastify) => {
  const { File, User, AuditLog } = fastify.db;
  const logger = fastify.log.child({ service: 'FileService' });
  let s3; // Placeholder for S3 client

  if (appConfig.fileStorage.provider === 's3') {
    // TODO: Initialize AWS S3 client
    logger.info('S3 storage provider selected (SDK usage placeholder).');
  } else {
    fsPromises.mkdir(appConfig.fileStorage.uploadDir, { recursive: true })
      .catch(err => logger.error({err}, 'Failed to create local upload dir'));
  }

  const generateUniqueFileName = (originalName) => {
    const ext = path.extname(originalName);
    const base = path.basename(originalName, ext).replace(/[^a-zA-Z0-9_-]/g, '_');
    return \`\${base}_\${Date.now()}_\${crypto.randomBytes(4).toString('hex')}\${ext}\`;
  };

  const calculateFileHash = async (readStream) => {
    return new Promise((resolve, reject) => {
      const hash = crypto.createHash('sha256');
      readStream.on('data', chunk => hash.update(chunk));
      readStream.on('end', () => resolve(hash.digest('hex')));
      readStream.on('error', reject);
    });
  };

  const uploadFile = async (userId, fileData, metadata) => {
    // fileData from @fastify/multipart (if attachFieldsToBody: 'keyValues') is an object:
    // { file: ReadableStream, filename: string, mimetype: string, encoding: string, fields: object }
    // Or if using request.parts(), fileData would be the async iterator part for the file.
    // Here we assume fileData is the object for the specific file field.
    
    const { file: stream, filename: originalName, mimetype } = fileData;
    if (!stream || typeof stream.pipe !== 'function') {
        throw fastify.httpErrors.badRequest('Invalid file stream provided.');
    }

    const uniqueFileName = generateUniqueFileName(originalName);
    let storagePath, publicUrl = null, fileSize = 0;
    const tempPath = path.join(appConfig.fileStorage.uploadDir, \`temp_\${uniqueFileName}\`);

    // Stream to temp file to get size and allow processing/S3 upload
    await new Promise((resolve, reject) => {
      const writeStream = fsSync.createWriteStream(tempPath);
      stream.on('data', chunk => fileSize += chunk.length);
      stream.on('error', err => { fsPromises.unlink(tempPath).catch(NOP); reject(err); });
      writeStream.on('error', err => { fsPromises.unlink(tempPath).catch(NOP); reject(err); });
      writeStream.on('finish', resolve);
      stream.pipe(writeStream);
    });

    if (fileSize > appConfig.fileStorage.maxFileSize) {
      await fsPromises.unlink(tempPath);
      throw fastify.httpErrors.payloadTooLarge(\`File exceeds size limit of \${appConfig.fileStorage.maxFileSize} bytes.\`);
    }

    if (appConfig.fileStorage.provider === 's3') {
      // const s3UploadStream = fsSync.createReadStream(tempPath);
      // const s3Params = { Bucket: BUCKET, Key: `uploads/\${uniqueFileName}\`, Body: s3UploadStream, ContentType: mimetype };
      // const s3Result = await s3.upload(s3Params).promise();
      // storagePath = s3Result.Key; publicUrl = s3Result.Location;
      storagePath = \`s3_placeholder_path/\${uniqueFileName}\`; publicUrl = \`s3_placeholder_url/\${uniqueFileName}\`; // Placeholder
      await fsPromises.unlink(tempPath); // Clean up temp after S3 upload
      logger.info(\`File '\${originalName}' placeholder S3 upload to \${storagePath}\`);
    } else {
      storagePath = path.join(appConfig.fileStorage.uploadDir, uniqueFileName);
      await fsPromises.rename(tempPath, storagePath);
      logger.info(\`File '\${originalName}' saved locally to \${storagePath}\`);
    }

    // const fileHash = await calculateFileHash(fsSync.createReadStream(storagePath)); // Hash the final stored file

    const fileRecord = await File.create({
      originalName, fileName: uniqueFileName, mimeType: mimetype, size: fileSize,
      storagePath, storageProvider: appConfig.fileStorage.provider, uploadedById: userId, publicUrl,
      // hash: fileHash, metadata,
    });
    
    if (appConfig.fileStorage.provider === 'local' && !fileRecord.publicUrl) {
        await fileRecord.update({ publicUrl: \`\${appConfig.apiBasePath}/files/\${fileRecord.id}/download\` });
    }

    await AuditLog.create({ userId, action: 'FILE_UPLOAD', entityType: 'File', entityId: fileRecord.id, details: { originalName, size: fileSize }, ipAddress: fastify.ip });
    return fileRecord;
  };

  const listFiles = async (queryParams, actorUser) => {
    const { limit = 10, offset = 0, sortBy = 'createdAt', sortOrder = 'DESC', search, mimeTypePrefix } = queryParams;
    const where = {};
    if (!['admin', 'manager'].includes(actorUser.role)) where.uploadedById = actorUser.id;
    if (search) where.originalName = { [Op.iLike]: \`%\${search}%\` };
    if (mimeTypePrefix) where.mimeType = { [Op.startsWith]: mimeTypePrefix };
    const { count, rows } = await File.findAndCountAll({
      where, include: [{ model: User, as: 'uploader', attributes: ['id', 'username'] }],
      limit: parseInt(limit,10), offset: parseInt(offset,10), order: [[sortBy, sortOrder.toUpperCase()]],
    });
    return { total: count, files: rows, limit, offset };
  };

  const getFileMetadata = async (fileId, actorUser) => {
    const fileRecord = await File.findByPk(fileId, { include: [{ model: User, as: 'uploader' }] });
    if (!fileRecord) throw fastify.httpErrors.notFound('File not found.');
    if (!['admin', 'manager'].includes(actorUser.role) && fileRecord.uploadedById !== actorUser.id) {
      // TODO: Add sharing logic check
      throw fastify.httpErrors.forbidden('Access to file metadata denied.');
    }
    return fileRecord;
  };

  const downloadFile = async (fileId, actorUser) => {
    const fileRecord = await getFileMetadata(fileId, actorUser); // Auth check done here
    if (fileRecord.storageProvider === 's3') {
      // const s3Params = { Bucket: BUCKET, Key: fileRecord.storagePath };
      // const s3Stream = s3.getObject(s3Params).createReadStream();
      // return { stream: s3Stream, fileRecord };
      throw fastify.httpErrors.notImplemented('S3 download stream not implemented.');
    } else {
      try {
        await fsPromises.access(fileRecord.storagePath);
        return { stream: fsSync.createReadStream(fileRecord.storagePath), fileRecord };
      } catch (error) {
        logger.error({ err: error, fileId, path: fileRecord.storagePath }, 'Error accessing local file for download.');
        throw fastify.httpErrors.internalServerError('Could not retrieve file.');
      }
    }
  };

  const deleteFile = async (fileId, actorUser) => {
    const fileRecord = await getFileMetadata(fileId, actorUser); // Auth check
    if (!['admin'].includes(actorUser.role) && fileRecord.uploadedById !== actorUser.id) {
      throw fastify.httpErrors.forbidden('Permission to delete file denied.');
    }
    if (fileRecord.storageProvider === 's3') {
      // await s3.deleteObject({ Bucket: BUCKET, Key: fileRecord.storagePath }).promise();
      logger.info(\`S3 file deletion placeholder for: \${fileRecord.storagePath}\`);
    } else {
      try { await fsPromises.unlink(fileRecord.storagePath); }
      catch (err) { logger.error({ err, fileId }, 'Failed to delete local file from disk.'); }
    }
    await fileRecord.destroy(); // Soft delete
    await AuditLog.create({ userId: actorUser.id, action: 'FILE_DELETE', entityType: 'File', entityId: fileRecord.id, ipAddress: fastify.ip });
  };
  
  const NOP = () => {}; // No-op for catch blocks

  return { uploadFile, listFiles, getFileMetadata, downloadFile, deleteFile };
};
EOT
# src/subsystems/files/files.schemas.js
cat <<EOT > src/subsystems/files/files.schemas.js
const Joi = require('joi');
const listFilesSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(10),
  offset: Joi.number().integer().min(0).default(0),
  sortBy: Joi.string().default('createdAt'),
  sortOrder: Joi.string().uppercase().valid('ASC', 'DESC').default('DESC'),
  search: Joi.string().optional().allow(''),
  mimeTypePrefix: Joi.string().optional(), // e.g., 'image/', 'application/pdf'
  // uploaderId: Joi.string().uuid().optional(), // If admin wants to filter by uploader
});
// Schema for multipart form parts if using request.parts() or specific validation
const uploadFileSchema = Joi.object({
    // 'file' field is handled by multipart plugin, this schema is for other metadata fields
    metadata: Joi.object().optional(), // e.g. { description: 'Team photo', tags: ['team', '2023'] }
});
module.exports = { listFilesSchema, uploadFileSchema };
EOT

# src/subsystems/messaging/* (content from previous script)
echo -e "  ${BLUE}💬 Creating Messaging subsystem...${NC}"
mkdir -p src/subsystems/messaging
# src/subsystems/messaging/index.js
cat <<EOT > src/subsystems/messaging/index.js
const messagingRoutes = require('./messaging.routes');
const webSocketHandler = require('./messaging.websocket');

module.exports = async function messagingSubsystem(fastify, options) {
  const wsService = { // Simple in-memory WebSocket client manager
    clients: new Map(), // Map<userId_string, Set<WebSocketConnection>>
    sendToUser: (userId, message) => {
      const conns = wsService.clients.get(userId.toString());
      if (conns) conns.forEach(c => { if (c.readyState === 1) c.send(JSON.stringify(message)); });
    },
    broadcastToChannel: (channelId, message, excludeUserId = null) => {
      // TODO: Need a way to map channelId to users. For now, this is illustrative.
      // This would iterate over users in a channel and call sendToUser.
      fastify.log.info({channelId, message}, "Broadcasting to channel (needs user mapping)");
    },
    addClient: (userId, ws) => {
      const uidStr = userId.toString();
      if (!wsService.clients.has(uidStr)) wsService.clients.set(uidStr, new Set());
      wsService.clients.get(uidStr).add(ws);
      fastify.log.info(\`WS client added for user \${uidStr}. Total: \${wsService.clients.get(uidStr).size}\`);
    },
    removeClient: (userId, ws) => {
      const uidStr = userId.toString();
      const conns = wsService.clients.get(uidStr);
      if (conns) {
        conns.delete(ws);
        if (conns.size === 0) wsService.clients.delete(uidStr);
        fastify.log.info(\`WS client removed for user \${uidStr}. Remaining: \${conns ? conns.size : 0}\`);
      }
    }
  };
  if (!fastify.wsService) fastify.decorate('wsService', wsService);
  
  fastify.register(messagingRoutes);
  fastify.get('/ws', { websocket: true }, (conn, req) => webSocketHandler(conn, req, fastify));
  fastify.log.info('💬 Messaging subsystem (HTTP & WebSocket) routes registered.');
};
EOT
# src/subsystems/messaging/messaging.routes.js
cat <<EOT > src/subsystems/messaging/messaging.routes.js
const messagingServiceFactory = require('./messaging.service');
const { listMessagesSchema, sendMessageSchema, listChannelsSchema } = require('./messaging.schemas');

module.exports = async function messagingRoutes(fastify, options) {
  const service = messagingServiceFactory(fastify);
  fastify.get('/channels/:channelId/messages', { schema: { querystring: listMessagesSchema }, preHandler: [fastify.authenticate] }, 
    async r => {
      if (!(await service.canAccessChannel(r.currentUser.id, r.params.channelId))) throw fastify.httpErrors.forbidden('Access denied.');
      return service.getMessagesForChannel(r.params.channelId, r.query);
    }
  );
  fastify.post('/channels/:channelId/messages', { schema: { body: sendMessageSchema }, preHandler: [fastify.authenticate] }, 
    async (r, reply) => {
      if (!(await service.canAccessChannel(r.currentUser.id, r.params.channelId))) throw fastify.httpErrors.forbidden('Access denied.');
      const message = await service.sendMessage(r.currentUser.id, r.params.channelId, r.body.channelType || 'direct', r.body.content);
      return reply.code(201).send(message);
    }
  );
  fastify.get('/channels', { schema: { querystring: listChannelsSchema }, preHandler: [fastify.authenticate] }, 
    async r => service.getUserChannels(r.currentUser.id, r.query)
  );
};
EOT
# src/subsystems/messaging/messaging.service.js
cat <<EOT > src/subsystems/messaging/messaging.service.js
const { Op } = require('sequelize');

module.exports = (fastify) => {
  const { Message, User } = fastify.db;
  const { wsService } = fastify;
  const logger = fastify.log.child({ service: 'MessagingService' });

  // Basic check; real system needs robust group/channel membership management
  const canAccessChannel = async (userId, channelId) => {
    // For DMs, channelId might be other user's ID. A user can always access a DM they are part of.
    // For group, check UserChannelMembership table (not implemented here)
    // This is a placeholder.
    const isSenderOrReceiverInvolved = await Message.findOne({
        where: { channelId, [Op.or]: [{ senderId: userId }] }
    });
    // If channelId is a UUID, it might be another user's ID in a DM context
    const isDirectPeer = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/.test(channelId);
    if (isDirectPeer) return true; // Allow access if it looks like a UUID (potential peer)
    return !!isSenderOrReceiverInvolved;
  };
  
  const getMessagesForChannel = async (channelId, { limit = 20, before, after }) => {
    const where = { channelId }; const order = [['createdAt', 'DESC']];
    if (before) { /* cursor logic for older */ const msg = await Message.findByPk(before); if(msg) where.createdAt = { [Op.lt]: msg.createdAt }; }
    if (after) { /* cursor logic for newer */ const msg = await Message.findByPk(after); if(msg) where.createdAt = { [Op.gt]: msg.createdAt }; order[0][1] = 'ASC'; }
    const messages = await Message.findAll({ where, limit: parseInt(limit,10), order, include: [{ model: User, as: 'sender', attributes: ['id', 'username', 'avatarUrl'] }] });
    return (after ? messages.reverse() : messages);
  };

  const sendMessage = async (senderId, channelId, channelType, content) => {
    const message = await Message.create({ senderId, channelId, channelType, content });
    const fullMessage = await Message.findByPk(message.id, { include: [{ model: User, as: 'sender', attributes: ['id', 'username', 'avatarUrl'] }] });

    if (wsService) { // Broadcast to channel members
      if (channelType === 'direct') {
        // For DMs, channelId is assumed to be the other user's ID.
        // Both sender and receiver should get the message for sync.
        wsService.sendToUser(senderId, { event: 'new_message', payload: fullMessage });
        if (channelId !== senderId.toString()) { // Don't send twice if user is sending to self (notes)
             wsService.sendToUser(channelId, { event: 'new_message', payload: fullMessage });
        }
      } else { // Group channel
        // TODO: Fetch all members of group 'channelId' and send to each
        // wsService.broadcastToChannel(channelId, { event: 'new_message', payload: fullMessage });
        // For now, just send to sender for testing group messages
        wsService.sendToUser(senderId, { event: 'new_message', payload: fullMessage });
      }
    }
    return fullMessage;
  };
  
  const getUserChannels = async (userId, queryParams) => {
    const { limit = 20, offset = 0 } = queryParams;
    // Simplified: get distinct channelIds user has participated in, ordered by last message
    const [results] = await fastify.db.sequelize.query(\`
      SELECT "channel_id", "channel_type", MAX("created_at") as "lastMessageAt"
      FROM "messages"
      WHERE "sender_id" = :userId OR "channel_id" = :userIdStr -- Simplified: user sent or channel IS user (DM where channelId is peerId)
      GROUP BY "channel_id", "channel_type"
      ORDER BY "lastMessageAt" DESC
      LIMIT :limit OFFSET :offset
    \`, { replacements: { userId, userIdStr: userId.toString(), limit, offset }, type: QueryTypes.SELECT });

    if(!results || results.length === 0) return { channels: [], total: 0, limit, offset };

    const channels = await Promise.all(results.map(async ch => {
      const lastMsg = await Message.findOne({ where: { channelId: ch.channel_id }, order: [['createdAt', 'DESC']], include: [{ model: User, as: 'sender', attributes:['id','username']}] });
      let name = ch.channel_id; let avatarUrl = null;
      if (ch.channel_type === 'direct' && ch.channel_id !== userId.toString()) { // If channelId is peer's ID
        const peer = await User.findByPk(ch.channel_id, {attributes: ['id', 'username', 'avatarUrl']});
        if (peer) { name = peer.username; avatarUrl = peer.avatarUrl; }
      } else if (ch.channel_type === 'direct' && ch.channel_id === userId.toString() && lastMsg && lastMsg.senderId.toString() !== userId.toString()) {
        // This case handles DM where channelId is current user's ID, and last message was from peer.
        const peer = await User.findByPk(lastMsg.senderId, {attributes: ['id', 'username', 'avatarUrl']});
        if (peer) { name = peer.username; avatarUrl = peer.avatarUrl; }
      }
      // TODO: Group name resolution
      return { id: ch.channel_id, type: ch.channel_type, name, avatarUrl, lastMessage: lastMsg };
    }));
    // Total count for pagination would require a separate query
    return { channels, total: results.length, limit, offset }; // This 'total' is just for this page.
  };

  return { canAccessChannel, getMessagesForChannel, sendMessage, getUserChannels };
};
EOT
# src/subsystems/messaging/messaging.websocket.js
cat <<EOT > src/subsystems/messaging/messaging.websocket.js
module.exports = async (connection, request, fastify) => {
  const { wsService, log, jwt: jwtInstance, db: { User } } = fastify;
  let authedUserId = null;
  const NOP = () => {}; // Keep-alive no-op
  // log.info({ socketId: request.id }, 'WS connection established.'); // request.id might not be set for websockets by default

  const pingInterval = setInterval(() => {
    if (connection.socket.readyState === 1) connection.socket.ping(NOP);
    else clearInterval(pingInterval);
  }, 30000);

  connection.socket.on('message', async (messageBuffer) => {
    try {
      const msgData = JSON.parse(messageBuffer.toString());
      // log.debug({ msgData }, 'WS message received');
      if (msgData.type === 'auth' && msgData.token) {
        if (authedUserId) return; // Already authed
        try {
          const decoded = await jwtInstance.verify(msgData.token);
          const user = await User.findByPk(decoded.id);
          if (user && user.status === 'active') {
            authedUserId = user.id;
            wsService.addClient(authedUserId, connection.socket);
            connection.socket.send(JSON.stringify({ type: 'auth_success', userId: authedUserId }));
            log.info(\`WS authed for user \${authedUserId}\`);
          } else {
            connection.socket.send(JSON.stringify({ type: 'auth_fail', message: 'User not found or inactive.' }));
            connection.socket.terminate();
          }
        } catch (err) {
          log.warn({ err }, 'WS auth token verification failed.');
          connection.socket.send(JSON.stringify({ type: 'auth_fail', message: 'Invalid token.' }));
          connection.socket.terminate();
        }
        return;
      }
      if (!authedUserId) { connection.socket.send(JSON.stringify({ type: 'error', message: 'Not authenticated.' })); return; }
      // Handle other authenticated messages
      if (msgData.type === 'ping') connection.socket.send(JSON.stringify({ type: 'pong' }));

    } catch (err) { log.error({ err }, 'Error processing WS message.'); }
  });
  connection.socket.on('close', () => {
    clearInterval(pingInterval);
    if (authedUserId) wsService.removeClient(authedUserId, connection.socket);
    log.info(\`WS connection closed for user \${authedUserId || 'unauthenticated'}\`);
  });
  connection.socket.on('error', (err) => {
    clearInterval(pingInterval);
    log.error({ err }, 'WS connection error.');
    if (authedUserId) wsService.removeClient(authedUserId, connection.socket);
  });
};
EOT
# src/subsystems/messaging/messaging.schemas.js
cat <<EOT > src/subsystems/messaging/messaging.schemas.js
const Joi = require('joi');
const listMessagesSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(100).default(20),
  before: Joi.string().uuid().optional(), // Message ID for cursor (older)
  after: Joi.string().uuid().optional(),  // Message ID for cursor (newer)
});
const sendMessageSchema = Joi.object({
  content: Joi.string().min(1).max(5000).required(),
  channelType: Joi.string().valid('direct', 'group').default('direct'),
  // attachments: Joi.array().items(Joi.string().uuid()).optional(), // Array of File IDs
});
const listChannelsSchema = Joi.object({
  limit: Joi.number().integer().min(1).max(50).default(20),
  offset: Joi.number().integer().min(0).default(0),
});
module.exports = { listMessagesSchema, sendMessageSchema, listChannelsSchema };
EOT

# src/scripts/initElasticsearch.js (content from previous script)
echo -e "  ${BLUE}🔍 Creating ES Init script (src/scripts/initElasticsearch.js)...${NC}"
cat <<EOT > src/scripts/initElasticsearch.js
require('dotenv').config({ path: require('path').resolve(__dirname, '../../.env') });
const { esClient, ensureIndexExists, defaultMappings } = require('../services/searchService/elasticsearchClient');
const db = require('../models'); // This should load all your models
const appConfig = require('../config/app'); // For index prefix

async function initializeElasticsearch() {
  if (!esClient) {
    console.error('Elasticsearch client is not initialized. Check ES_NODE in .env and ES service.');
    process.exit(1);
  }
  console.log('Starting Elasticsearch initialization...');
  try {
    await esClient.ping();
    console.log('Successfully connected to Elasticsearch.');
  } catch (error) {
    console.error('Failed to connect to Elasticsearch:', error.message);
    process.exit(1);
  }

  const searchableModelsMap = new Map();
  if (db.User) searchableModelsMap.set('user', { model: db.User, name: 'User' });
  if (db.Task) searchableModelsMap.set('task', { model: db.Task, name: 'Task' });
  if (db.File) searchableModelsMap.set('file', { model: db.File, name: 'File' });

  for (const [modelKey, modelInfo] of searchableModelsMap) {
    if (!modelInfo.model || !modelInfo.model.getSearchIndexName) {
      console.warn(\`Model '\${modelInfo.name}' misconfigured for search.\`); continue;
    }
    const indexName = modelInfo.model.getSearchIndexName();
    const mapping = modelInfo.mapping || defaultMappings;
    console.log(\`Ensuring index '\${indexName}' for model '\${modelInfo.name}'...`);
    await ensureIndexExists(esClient, indexName, mapping);
  }
  console.log('Elasticsearch index initialization complete.');
  
  // Optional: Trigger reindex if needed, e.g., if a flag is passed or it's first setup
  // const shouldReindex = process.argv.includes('--reindex');
  // if (shouldReindex) {
  //   console.log('Reindexing data...');
  //   const mockFastify = { elasticsearch: esClient, db, log: console, httpErrors: { internalServerError: (m) => new Error(m) } };
  //   const searchService = require('../subsystems/search/search.service')(mockFastify);
  //   await searchService.reindexData();
  //   console.log('Reindexing complete.');
  // }

  await esClient.close();
  console.log('Elasticsearch client connection closed after init.');
}

initializeElasticsearch().catch(error => {
  console.error('Unhandled error during Elasticsearch initialization:', error);
  if (esClient && esClient.close) esClient.close().catch(e => console.error("Error closing ES client on failure:", e));
  process.exit(1);
});
EOT


# --- END OF PASTED SRC FILE GENERATION ---

# 5. Create Basic Migrations (Placeholders - to be manually edited)
echo -e "  ${BLUE}📜 Creating placeholder migration files...${NC}"
TIMESTAMP=$(date +%Y%m%d%H%M%S)
# Users Table
cat <<EOT > "migrations/${TIMESTAMP}01-create-user.js"
'use strict';
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.createTable('users', { // Note: table name is pluralized by default
      id: { allowNull: false, primaryKey: true, type: Sequelize.UUID, defaultValue: Sequelize.UUIDV4 },
      username: { type: Sequelize.STRING, allowNull: false, unique: true },
      email: { type: Sequelize.STRING, allowNull: false, unique: true },
      password: { type: Sequelize.STRING, allowNull: false },
      first_name: { type: Sequelize.STRING },
      last_name: { type: Sequelize.STRING },
      role: { type: Sequelize.ENUM('user', 'manager', 'admin', 'developer', 'guest'), defaultValue: 'user', allowNull: false },
      avatar_url: { type: Sequelize.STRING },
      status: { type: Sequelize.ENUM('active', 'inactive', 'suspended', 'pending_verification'), defaultValue: 'pending_verification', allowNull: false },
      last_login_at: { type: Sequelize.DATE },
      timezone: { type: Sequelize.STRING, defaultValue: 'UTC' },
      locale: { type: Sequelize.STRING, defaultValue: 'en-US' },
      email_verified_at: { type: Sequelize.DATE },
      email_verification_token: { type: Sequelize.STRING },
      password_reset_token: { type: Sequelize.STRING },
      password_reset_expires_at: { type: Sequelize.DATE },
      created_at: { allowNull: false, type: Sequelize.DATE },
      updated_at: { allowNull: false, type: Sequelize.DATE }
    });
  },
  async down(queryInterface, Sequelize) { await queryInterface.dropTable('users'); }
};
EOT
# Tasks Table
cat <<EOT > "migrations/${TIMESTAMP}02-create-task.js"
'use strict';
module.exports = {
  async up(queryInterface, Sequelize) {
    await queryInterface.createTable('tasks', {
      id: { allowNull: false, primaryKey: true, type: Sequelize.UUID, defaultValue: Sequelize.UUIDV4 },
      title: { type: Sequelize.STRING, allowNull: false },
      description: { type: Sequelize.TEXT },
      status: { type: Sequelize.ENUM('todo', 'in_progress', 'in_review', 'blocked', 'done', 'archived'), defaultValue: 'todo', allowNull: false },
      priority: { type: Sequelize.ENUM('low', 'medium', 'high', 'critical'), defaultValue: 'medium', allowNull: false },
      due_date: { type: Sequelize.DATE },
      completed_at: { type: Sequelize.DATE },
      creator_id: { type: Sequelize.UUID, allowNull: false, references: { model: 'users', key: 'id' }, onUpdate: 'CASCADE', onDelete: 'SET NULL' },
      assignee_id: { type: Sequelize.UUID, allowNull: true, references: { model: 'users', key: 'id' }, onUpdate: 'CASCADE', onDelete: 'SET NULL' },
      tags: { type: Sequelize.ARRAY(Sequelize.STRING) },
      created_at: { allowNull: false, type: Sequelize.DATE },
      updated_at: { allowNull: false, type: Sequelize.DATE },
      deleted_at: { type: Sequelize.DATE } // For paranoid: true
    });
  },
  async down(queryInterface, Sequelize) { await queryInterface.dropTable('tasks'); }
};
EOT
# Add more migration files for File, Notification, AuditLog, Message, Workflow etc. following this pattern.

# 6. Create Basic Seeder (Admin User)
echo -e "  ${BLUE}🌱 Creating admin user seeder...${NC}"
cat <<EOT > "seeders/${TIMESTAMP}01-admin-user.js"
'use strict';
const bcrypt = require('bcryptjs');
const { v4: uuidv4 } = require('uuid');

module.exports = {
  async up (queryInterface, Sequelize) {
    const adminPassword = await bcrypt.hash(process.env.ADMIN_INITIAL_PASSWORD || 'AdminSecurePassword123!', 10);
    await queryInterface.bulkInsert('users', [{
      id: uuidv4(),
      username: process.env.ADMIN_INITIAL_USERNAME || 'admin',
      email: process.env.ADMIN_INITIAL_EMAIL || 'admin@example.com',
      password: adminPassword,
      first_name: 'Admin',
      last_name: 'User',
      role: 'admin',
      status: 'active',
      email_verified_at: new Date(),
      created_at: new Date(),
      updated_at: new Date(),
    }], {});
  },
  async down (queryInterface, Sequelize) {
    await queryInterface.bulkDelete('users', { email: process.env.ADMIN_INITIAL_EMAIL || 'admin@example.com' }, {});
  }
};
EOT

# 7. Create Dockerfile
echo -e "  ${BLUE}🐳 Creating Dockerfile...${NC}"
cat <<EOT > Dockerfile
FROM node:18-alpine AS base
WORKDIR /app
ENV NODE_ENV=production

FROM base AS deps
COPY package.json package-lock.json* ./
RUN npm ci --omit=dev --ignore-scripts

FROM base AS runner
COPY --from=deps /app/node_modules ./node_modules
COPY . .

# Ensure log and upload directories exist and are writable by the node user
RUN mkdir -p /app/logs && chown -R node:node /app/logs
RUN mkdir -p /app/data/uploads && chown -R node:node /app/data/uploads

USER node
EXPOSE \${PORT:-3000}
CMD ["node", "src/server.js"]
EOT

# 8. Create docker-compose.yml
echo -e "  ${BLUE}🐳 Creating docker-compose.yml...${NC}"
cat <<EOT > docker-compose.yml
version: '3.8'

services:
  app:
    build:
      context: .
      dockerfile: Dockerfile
    container_name: enterprise_app_service
    env_file: .env
    ports:
      - "\${PORT:-3000}:\${PORT:-3000}"
    volumes:
      - ./logs:/app/logs
      - ./data/uploads:/app/data/uploads # If using local storage
      # For development, mount src to see changes without rebuilding:
      # - ./src:/app/src 
    depends_on:
      db: { condition: service_healthy }
      redis: { condition: service_started } # Redis alpine doesn't have a simple healthcheck
      elasticsearch: { condition: service_healthy }
    restart: unless-stopped
    networks:
      - enterprise_network
    # healthcheck: # App-level healthcheck
    #   test: ["CMD-SHELL", "wget --quiet --tries=1 --spider http://localhost:\${PORT:-3000}/health || exit 1"]
    #   interval: 30s
    #   timeout: 10s
    #   retries: 3
    #   start_period: 30s # Give app time to start

  db:
    image: postgres:15-alpine
    container_name: enterprise_db_service
    environment:
      POSTGRES_USER: \${POSTGRES_USER}
      POSTGRES_PASSWORD: \${POSTGRES_PASSWORD}
      POSTGRES_DB: \${POSTGRES_DB}
    ports:
      - "5433:5432" # Host 5433 -> Container 5432
    volumes:
      - postgres_data_vol:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U \${POSTGRES_USER} -d \${POSTGRES_DB}"]
      interval: 10s
      timeout: 5s
      retries: 5
    restart: unless-stopped
    networks:
      - enterprise_network

  redis:
    image: redis:7-alpine
    container_name: enterprise_redis_service
    ports:
      - "6379:6379"
    volumes:
      - redis_data_vol:/data
    command: redis-server --save 60 1 --loglevel warning
    restart: unless-stopped
    networks:
      - enterprise_network
    # healthcheck: # For redis-cli
    #   test: ["CMD", "redis-cli", "ping"]
    #   interval: 10s
    #   timeout: 5s
    #   retries: 3

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.1
    container_name: enterprise_es_service
    environment:
      - discovery.type=single-node
      - ES_JAVA_OPTS=-Xms512m -Xmx512m # Adjust for your system
      - xpack.security.enabled=false # DEV ONLY! Enable for PROD.
      - "TAKE_FILE_OWNERSHIP=true" # Fixes permissions issues on volume mounts
    ports:
      - "9200:9200"
      - "9300:9300"
    volumes:
      - es_data_vol:/usr/share/elasticsearch/data
    healthcheck:
      test: ["CMD-SHELL", "curl -s -f http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=10s || exit 1"]
      interval: 20s # Check less frequently once healthy
      timeout: 15s
      retries: 10
      start_period: 60s # ES can take time to start
    restart: unless-stopped
    networks:
      - enterprise_network
    ulimits: # Recommended for Elasticsearch
      memlock:
        soft: -1
        hard: -1
      nofile:
        soft: 65536
        hard: 65536


volumes:
  postgres_data_vol:
  redis_data_vol:
  es_data_vol:

networks:
  enterprise_network:
    driver: bridge
EOT

# 9. Create public/index.html and related static assets
echo -e "  ${BLUE}🌐 Creating public/index.html and static assets...${NC}"
# public/index.html (content from previous script, with VAPID key placeholder updated)
cat <<EOT > public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8"><title>Enterprise App</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="description" content="Enterprise Application"><meta name="theme-color" content="#3498db">
  <link rel="manifest" href="/manifest.json"><link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" href="/icons/icon-192x192.png" type="image/png" sizes="192x192">
  <link rel="apple-touch-icon" href="/icons/apple-touch-icon.png">
  <link rel="stylesheet" href="/css/main.css">
  <style>
    body { font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, Helvetica, Arial, sans-serif; margin: 0; padding: 20px; background-color: #f0f2f5; color: #1d2129; line-height: 1.6; }
    .container { max-width: 900px; margin: 20px auto; background: #fff; padding: 25px; border-radius: 8px; box-shadow: 0 4px 12px rgba(0,0,0,0.1); }
    h1, h2, h3 { color: #1877f2; margin-top:0; } h1 { text-align: center; margin-bottom: 25px; }
    input, button { padding: 12px 15px; margin: 8px 0; border-radius: 6px; border: 1px solid #ddd; font-size: 16px; }
    input { width: calc(100% - 32px); }
    button { background-color: #1877f2; color: white; cursor: pointer; border-color: #1877f2; font-weight: bold; }
    button:hover { background-color: #166fe5; } button.secondary { background-color: #e4e6eb; color: #050505; border-color: #ced0d4;} button.secondary:hover{ background-color: #ccd0d5;}
    #auth-section > div, #app-section > div { margin-bottom: 15px; }
    #notifications { border-left: 4px solid #1877f2; padding: 15px; margin-top: 20px; background: #e7f3ff; border-radius: 6px; }
    .hidden { display: none; }
    ul { list-style-type: none; padding: 0; }
    li { background: #f7f8fa; margin-bottom: 8px; padding: 10px 15px; border-radius: 6px; border: 1px solid #e0e0e0; display: flex; justify-content: space-between; align-items: center;}
    .auth-toggle { text-align: center; margin-top: 15px; } .auth-toggle button { background: none; border: none; color: #1877f2; cursor: pointer; text-decoration: underline; padding: 5px;}
    .error-message { color: red; font-size: 0.9em; margin-top: 5px; }
  </style>
</head>
<body>
  <div class="container">
    <h1>Enterprise Application</h1>
    <div id="error-display" class="error-message" style="text-align:center;"></div>

    <div id="auth-section">
      <div id="login-form">
        <h2>Login</h2>
        <input type="text" id="loginEmailOrUsername" placeholder="Email or Username">
        <input type="password" id="loginPassword" placeholder="Password">
        <button onclick="app.login()">Login</button>
        <div class="auth-toggle"><button onclick="app.toggleAuthForm('register')">Need an account? Register</button></div>
        <div class="auth-toggle"><button onclick="app.toggleAuthForm('forgot')">Forgot Password?</button></div>
      </div>
      <div id="register-form" class="hidden">
        <h2>Register</h2>
        <input type="text" id="registerUsername" placeholder="Username">
        <input type="email" id="registerEmail" placeholder="Email">
        <input type="password" id="registerPassword" placeholder="Password">
        <button onclick="app.register()">Register</button>
        <div class="auth-toggle"><button onclick="app.toggleAuthForm('login')">Already have an account? Login</button></div>
      </div>
      <div id="forgot-password-form" class="hidden">
        <h2>Forgot Password</h2>
        <input type="email" id="forgotEmail" placeholder="Enter your email">
        <button onclick="app.forgotPassword()">Send Reset Link</button>
        <div class="auth-toggle"><button onclick="app.toggleAuthForm('login')">Back to Login</button></div>
      </div>
    </div>

    <div id="app-section" class="hidden">
      <h2>Welcome, <span id="currentUserDisplay">User</span>!</h2>
      <button onclick="app.logout()" class="secondary">Logout</button>
      <button onclick="app.fetchTasks()">Fetch Tasks</button>
      <button onclick="app.requestNotificationPermission()" class="secondary">Enable Notifications</button>

      <div>
        <h3>Create Task</h3>
        <input type="text" id="taskTitle" placeholder="Task Title">
        <textarea id="taskDescription" placeholder="Task Description" style="width: calc(100% - 32px); min-height: 60px; margin: 8px 0; padding: 10px; border-radius: 6px; border: 1px solid #ddd; font-size: 16px;"></textarea>
        <button onclick="app.createTask()">Create Task</button>
      </div>
      
      <div>
        <h3>Your Tasks</h3>
        <ul id="tasks-list"><li>Loading tasks...</li></ul>
      </div>

      <div id="notifications">
        <h4>Real-time Updates:</h4>
        <ul id="notifications-list"></ul>
      </div>
    </div>
  </div>

  <script>
    const API_BASE_PATH = '/api/v1'; // From .env API_BASE_PATH
    const VAPID_PUBLIC_KEY_PLACEHOLDER = '${VAPID_PUBLIC_KEY}'; // This will be replaced by the script or manually
    
    const state = { accessToken: localStorage.getItem('accessToken'), refreshToken: localStorage.getItem('refreshToken'), currentUser: null, ws: null };
    const ui = { /* DOM element references */ };

    function getUIElements() {
        ui.errorDisplay = document.getElementById('error-display');
        ui.authSection = document.getElementById('auth-section');
        ui.loginForm = document.getElementById('login-form');
        ui.registerForm = document.getElementById('register-form');
        ui.forgotPasswordForm = document.getElementById('forgot-password-form');
        ui.appSection = document.getElementById('app-section');
        ui.currentUserDisplay = document.getElementById('currentUserDisplay');
        ui.tasksList = document.getElementById('tasks-list');
        ui.notificationsList = document.getElementById('notifications-list');
        // Login
        ui.loginEmailOrUsernameInput = document.getElementById('loginEmailOrUsername');
        ui.loginPasswordInput = document.getElementById('loginPassword');
        // Register
        ui.registerUsernameInput = document.getElementById('registerUsername');
        ui.registerEmailInput = document.getElementById('registerEmail');
        ui.registerPasswordInput = document.getElementById('registerPassword');
        // Forgot Password
        ui.forgotEmailInput = document.getElementById('forgotEmail');
        // Task
        ui.taskTitleInput = document.getElementById('taskTitle');
        ui.taskDescriptionInput = document.getElementById('taskDescription');
    }
    
    function displayError(message) { if(ui.errorDisplay) ui.errorDisplay.textContent = message; }
    function clearError() { if(ui.errorDisplay) ui.errorDisplay.textContent = ''; }

    async function apiCall(endpoint, method = 'GET', body = null, requiresAuth = true) {
      clearError();
      const headers = { 'Content-Type': 'application/json' };
      if (requiresAuth && state.accessToken) headers['Authorization'] = \`Bearer \${state.accessToken}\`;
      const config = { method, headers };
      if (body) config.body = JSON.stringify(body);

      try {
        let response = await fetch(\`\${API_BASE_PATH}\${endpoint}\`, config);
        if (response.status === 204) return null;
        let data = await response.json();

        if (!response.ok) {
          if (response.status === 401 && data.error === 'Unauthorized' && data.message.includes('expired') && state.refreshToken && endpoint !== '/auth/refresh-token') {
            console.warn('Access token expired. Attempting refresh...');
            const refreshData = await app.refreshToken(); // Use app.refreshToken
            if (refreshData && refreshData.accessToken) {
                headers['Authorization'] = \`Bearer \${state.accessToken}\`; // state.accessToken updated by app.refreshToken
                response = await fetch(\`\${API_BASE_PATH}\${endpoint}\`, { ...config, headers }); // Retry with new token
                if(response.status === 204) return null;
                data = await response.json();
                if (!response.ok) throw new Error(data.message || \`API Error (after refresh): \${response.status}\`);
            } else {
                 throw new Error(data.message || 'Token refresh failed, please log in again.');
            }
          } else {
            throw new Error(data.message || data.error || \`API Error: \${response.status}\`);
          }
        }
        return data;
      } catch (error) {
        console.error('API Call Error:', endpoint, error);
        displayError(error.message);
        if (error.message.toLowerCase().includes('token refresh failed') || error.message.toLowerCase().includes('invalid refresh token')) {
            app.logout(); // Force logout if refresh chain fails
        }
        throw error;
      }
    }
    
    function initWebSocket() { /* ... (content from previous script, ensure VAPID key is used from VAPID_PUBLIC_KEY_PLACEHOLDER) ... */
      if (state.ws && state.ws.readyState === WebSocket.OPEN) return;
      if (!state.accessToken) { console.log('No access token, WebSocket not connecting.'); return; }
      const wsProtocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
      const wsUrl = \`\${wsProtocol}//\${window.location.host}\${API_BASE_PATH}/messaging/ws\`; // Ensure this path is correct
      state.ws = new WebSocket(wsUrl);
      state.ws.onopen = () => { console.log('WebSocket connected.'); state.ws.send(JSON.stringify({ type: 'auth', token: state.accessToken })); };
      state.ws.onmessage = (event) => {
        try {
          const message = JSON.parse(event.data); console.log('WS Rx:', message);
          if (message.event === 'new_notification' || message.event === 'new_message' || message.event === 'task_update') app.handleRealtimeEvent(message);
        } catch (e) { console.error('Error parsing WS message:', e); }
      };
      state.ws.onclose = () => { console.log('WebSocket disconnected.'); state.ws = null; /* setTimeout(initWebSocket, 5000); */ };
      state.ws.onerror = (error) => { console.error('WebSocket error:', error); state.ws = null; };
    }

    const app = {
      async init() {
        getUIElements(); // Cache DOM elements
        if (state.accessToken) {
          try {
            state.currentUser = await apiCall('/auth/me');
            this.showAppView(); initWebSocket(); this.fetchTasks();
          } catch (error) { this.logout(); /* Error displayed by apiCall */ }
        } else this.showAuthView();
      },
      showAuthView() { ui.authSection.classList.remove('hidden'); ui.appSection.classList.add('hidden'); this.toggleAuthForm('login'); },
      showAppView() { ui.authSection.classList.add('hidden'); ui.appSection.classList.remove('hidden'); ui.currentUserDisplay.textContent = state.currentUser?.username || 'User'; },
      toggleAuthForm(formName) {
        ['login', 'register', 'forgot'].forEach(name => {
            const form = document.getElementById(\`\${name}-form\`);
            if (form) form.classList.toggle('hidden', name !== formName);
        });
        clearError();
      },
      async register() {
        try {
          const { user } = await apiCall('/auth/register', 'POST', {
            username: ui.registerUsernameInput.value, email: ui.registerEmailInput.value, password: ui.registerPasswordInput.value,
          }, false);
          alert(\`User \${user.username} registered! Check email for verification.\`); this.toggleAuthForm('login');
        } catch (error) { /* Handled by apiCall */ }
      },
      async login() {
        try {
          const { user, accessToken, refreshToken } = await apiCall('/auth/login', 'POST', {
            emailOrUsername: ui.loginEmailOrUsernameInput.value, password: ui.loginPasswordInput.value,
          }, false);
          this.setSession(user, accessToken, refreshToken); this.showAppView(); initWebSocket(); this.fetchTasks();
        } catch (error) { /* Handled by apiCall */ }
      },
      async forgotPassword() {
        try {
            await apiCall('/auth/forgot-password', 'POST', { email: ui.forgotEmailInput.value }, false);
            alert('If an account with that email exists, a password reset link has been sent.');
            this.toggleAuthForm('login');
        } catch (error) { /* Handled */ }
      },
      setSession(user, accessToken, refreshToken) {
        state.currentUser = user; state.accessToken = accessToken; state.refreshToken = refreshToken;
        localStorage.setItem('accessToken', accessToken); localStorage.setItem('refreshToken', refreshToken);
      },
      async refreshToken() { // Called by apiCall on 401
        try {
            const { accessToken, refreshToken: newRefreshToken } = await apiCall('/auth/refresh-token', 'POST', { refreshToken: state.refreshToken }, false);
            this.setSession(state.currentUser, accessToken, newRefreshToken || state.refreshToken); // Update with new tokens
            return { accessToken }; // Return new access token for retry
        } catch (err) {
            console.error("Refresh token failed:", err);
            this.logout(); // Force logout if refresh fails
            throw err; // Propagate error
        }
      },
      logout() {
        // apiCall('/auth/logout', 'POST').catch(e => console.warn("Logout API call failed", e)); // Optional server-side logout
        localStorage.removeItem('accessToken'); localStorage.removeItem('refreshToken');
        state.accessToken = null; state.refreshToken = null; state.currentUser = null;
        if (state.ws) state.ws.close();
        this.showAuthView(); displayError('You have been logged out.');
      },
      async createTask() {
        const title = ui.taskTitleInput.value; const description = ui.taskDescriptionInput.value;
        if(!title) { alert('Task title is required.'); return; }
        try {
            const task = await apiCall('/tasks', 'POST', { title, description });
            alert(\`Task '\${task.title}' created.\`); ui.taskTitleInput.value = ''; ui.taskDescriptionInput.value = ''; this.fetchTasks();
        } catch (error) {}
      },
      async fetchTasks() {
        try {
          const { tasks } = await apiCall('/tasks?limit=10&sortOrder=DESC');
          ui.tasksList.innerHTML = tasks.length > 0 ? tasks.map(t => \`<li>\${t.title} (\${t.status})</li>\`).join('') : '<li>No tasks found.</li>';
        } catch (error) { ui.tasksList.innerHTML = '<li>Failed to load tasks.</li>'; }
      },
      handleRealtimeEvent(eventData) {
        const item = document.createElement('li');
        let content = \`[\${new Date(eventData.createdAt || Date.now()).toLocaleTimeString()}] \`;
        if(eventData.type === 'task_assigned' || eventData.type === 'task_updated') {
            content += \`Task Update: \${eventData.title || eventData.taskTitle} - \${eventData.message}\`;
        } else if (eventData.sender) { // For messages
            content += \`Message from \${eventData.sender.username}: \${eventData.content}\`;
        } else { // Generic notification
            content += \`\${eventData.title}: \${eventData.message}\`;
        }
        item.textContent = content;
        ui.notificationsList.prepend(item);
        if (Notification.permission === 'granted' && document.visibilityState === 'hidden') {
          navigator.serviceWorker.ready.then(reg => reg.showNotification(eventData.title || 'New Update', { body: eventData.message || eventData.content, icon: '/icons/icon-192x192.png', data: eventData.data }));
        }
      },
      async requestNotificationPermission() { /* ... (content from previous script) ... */
        if (!('Notification' in window)) { alert('Browser does not support notifications'); return; }
        if (Notification.permission === 'granted') { alert('Notification permission already granted.'); this.subscribeToPush(); return; }
        if (Notification.permission !== 'denied') {
          const permission = await Notification.requestPermission();
          if (permission === 'granted') { alert('Notification permission granted!'); this.subscribeToPush(); }
          else { alert('Notification permission denied.'); }
        }
      },
      async subscribeToPush() { /* ... (content from previous script, use VAPID_PUBLIC_KEY_PLACEHOLDER) ... */
        if (!('serviceWorker' in navigator) || !('PushManager' in window)) { alert('Push messaging not supported.'); return; }
        try {
          const registration = await navigator.serviceWorker.ready;
          let subscription = await registration.pushManager.getSubscription();
          if (!subscription) {
            const vapidKey = VAPID_PUBLIC_KEY_PLACEHOLDER;
            if (!vapidKey || vapidKey.includes("YOUR_GENERATED")) { alert('VAPID public key not configured.'); return; }
            subscription = await registration.pushManager.subscribe({ userVisibleOnly: true, applicationServerKey: this.urlBase64ToUint8Array(vapidKey) });
            await apiCall('/notifications/subscribe-webpush', 'POST', { subscription });
            alert('Subscribed to push notifications!');
          } else alert('Already subscribed.');
        } catch (err) { console.error('Push subscription error:', err); alert(\`Push subscribe failed: \${err.message}\`); }
      },
      urlBase64ToUint8Array(base64String) { /* ... (content from previous script) ... */
        const padding = '='.repeat((4 - base64String.length % 4) % 4);
        const base64 = (base64String + padding).replace(/-/g, '+').replace(/_/g, '/');
        const rawData = window.atob(base64); const outputArray = new Uint8Array(rawData.length);
        for (let i = 0; i < rawData.length; ++i) outputArray[i] = rawData.charCodeAt(i);
        return outputArray;
      }
    };
    document.addEventListener('DOMContentLoaded', () => app.init());
  </script>
  <script> if ('serviceWorker' in navigator) window.addEventListener('load', () => navigator.serviceWorker.register('/sw.js').then(r => console.log('SW registered.')).catch(e => console.error('SW reg failed:', e))); </script>
</body>
</html>
EOT

# public/manifest.json (content from previous script)
echo -e "  ${BLUE}📝 Creating public/manifest.json...${NC}"
cat <<EOT > public/manifest.json
{
  "name": "Enterprise Application", "short_name": "EntApp",
  "description": "A comprehensive enterprise application.", "start_url": "/",
  "display": "standalone", "background_color": "#ffffff", "theme_color": "#3498db",
  "orientation": "portrait-primary",
  "icons": [
    { "src": "/icons/icon-72x72.png", "type": "image/png", "sizes": "72x72" },
    { "src": "/icons/icon-96x96.png", "type": "image/png", "sizes": "96x96" },
    { "src": "/icons/icon-128x128.png", "type": "image/png", "sizes": "128x128" },
    { "src": "/icons/icon-144x144.png", "type": "image/png", "sizes": "144x144" },
    { "src": "/icons/icon-152x152.png", "type": "image/png", "sizes": "152x152" },
    { "src": "/icons/icon-192x192.png", "type": "image/png", "sizes": "192x192", "purpose": "any maskable" },
    { "src": "/icons/icon-384x384.png", "type": "image/png", "sizes": "384x384" },
    { "src": "/icons/icon-512x512.png", "type": "image/png", "sizes": "512x512" }
  ]
}
EOT
# Create dummy icons & basic CSS
touch public/icons/icon-72x72.png public/icons/icon-96x96.png public/icons/icon-128x128.png public/icons/icon-144x144.png \
      public/icons/icon-152x152.png public/icons/icon-192x192.png public/icons/icon-384x384.png public/icons/icon-512x512.png \
      public/icons/apple-touch-icon.png public/favicon.ico
echo "/* Basic CSS - public/css/main.css */ body { padding: 1em; }" > public/css/main.css

# public/sw.js (Service Worker - content from previous script)
echo -e "  ${BLUE}⚙️  Creating public/sw.js (Service Worker)...${NC}"
cat <<EOT > public/sw.js
const CACHE_NAME = 'entapp-v1'; const API_CACHE_NAME = 'entapp-api-v1';
const STATIC_ASSETS = ['/', '/index.html', '/css/main.css', '/manifest.json', '/favicon.ico', '/icons/icon-192x192.png', '/icons/icon-512x512.png'];
self.addEventListener('install', e => e.waitUntil(caches.open(CACHE_NAME).then(c => c.addAll(STATIC_ASSETS)).then(() => self.skipWaiting())));
self.addEventListener('activate', e => e.waitUntil(caches.keys().then(names => Promise.all(names.map(n => (n!==CACHE_NAME && n!==API_CACHE_NAME) ? caches.delete(n) : null))).then(() => self.clients.claim())));
self.addEventListener('fetch', e => {
  const {request} = e; const url = new URL(request.url);
  if (url.pathname.startsWith('/api/v1/')) { // Network first for API
    e.respondWith(caches.open(API_CACHE_NAME).then(c => fetch(request).then(res => { if(request.method === 'GET' && res.ok) c.put(request, res.clone()); return res; }).catch(() => c.match(request)))); return;
  } // Cache first for static assets
  e.respondWith(caches.match(request).then(res => res || fetch(request).then(netRes => { if (netRes.ok && STATIC_ASSETS.includes(url.pathname)) caches.open(CACHE_NAME).then(c => c.put(request, netRes.clone())); return netRes; })).catch(() => { /* Offline fallback? */ }));
});
self.addEventListener('push', e => {
  if (!e.data) return; const data = e.data.json();
  e.waitUntil(self.registration.showNotification(data.title || 'Notification', { body: data.body || 'New update.', icon: data.icon || '/icons/icon-192x192.png', data: data.data }));
});
self.addEventListener('notificationclick', e => {
  e.notification.close(); const url = e.notification.data && e.notification.data.url ? e.notification.data.url : '/';
  e.waitUntil(clients.matchAll({type:'window', includeUncontrolled:true}).then(wc => { for(let i=0;i<wc.length;i++){ if(wc[i].url===url && 'focus' in wc[i]) return wc[i].focus(); } if(clients.openWindow) return clients.openWindow(url); }));
});
EOT

# 10. Jest test setup (jest.config.js, tests/setup.js, basic auth test)
echo -e "  ${BLUE}🧪 Creating test suite files...${NC}"
cat <<EOT > jest.config.js
module.exports = {
  testEnvironment: 'node', verbose: true, coveragePathIgnorePatterns: ['/node_modules/', '/src/config/', '/src/scripts/', '/src/models/index.js', '/src/plugins.js', '/src/decorators.js', '/src/hooks.js', '/src/subsystems/index.js'],
  setupFilesAfterEnv: ['./tests/setup.js'], testTimeout: 20000, // Increased timeout
};
EOT
cat <<EOT > tests/setup.js
process.env.NODE_ENV = 'test';
process.env.LOG_LEVEL = 'silent';
// IMPORTANT: Use a DEDICATED test database. This config assumes it's running against Dockerized DB.
process.env.DATABASE_URL = 'postgres://ep_user:ep_password@localhost:5433/enterprise_app_test'; // Points to host machine port mapped to DB container
process.env.ELASTICSEARCH_NODE = ''; // Disable ES for most tests or use a test ES instance
process.env.SENTRY_DSN = '';
process.env.REDIS_HOST = 'localhost'; // Assuming Redis is also port-mapped for tests if needed outside app container
process.env.REDIS_PORT = '6379';
EOT
mkdir -p tests/integration
# Basic Auth Test (Adjusted for promise-based server export and test DB)
cat <<EOT > tests/integration/auth.test.js
const supertest = require('supertest');
let fastifyPromise = require('../../src/server'); // This is now a promise
let fastify; // Will hold the resolved Fastify instance
let User;
const RND_STR = Math.random().toString(36).substring(2, 8);

beforeAll(async () => {
  fastify = await fastifyPromise; // Resolve the promise
  await fastify.ready(); // Ensure all plugins, etc., are loaded
  User = fastify.db.User;
  // Sync test database (force:true is okay for a dedicated test DB)
  try {
    await fastify.db.sequelize.authenticate(); // Check connection first
    console.log('Test DB connection successful. Syncing...');
    await fastify.db.sequelize.sync({ force: true });
    console.log('Test database synchronized.');
  } catch (err) {
    console.error("FATAL: Test DB setup failed. Ensure test DB is accessible and TEST_DATABASE_URL in tests/setup.js is correct.", err);
    process.exit(1);
  }
}, 30000); // Increased timeout for beforeAll

afterAll(async () => {
  if (fastify) {
    await fastify.close(); // Close the Fastify server
    if (fastify.db && fastify.db.sequelize) {
      await fastify.db.sequelize.close(); // Close DB connection
    }
    if (fastify.redis) { // Close Redis if decorated and used by tests directly
        await fastify.redis.quit();
    }
  }
});

describe('Auth Subsystem - /api/v1/auth', () => {
  const testUser = { username: \`test_\${RND_STR}\`, email: \`test_\${RND_STR}@example.com\`, password: 'Password123!' };
  let accessToken, refreshToken;

  it('POST /register - should register a new user', async () => {
    const res = await supertest(fastify.server).post('/api/v1/auth/register').send(testUser).expect(201);
    expect(res.body.user.email).toBe(testUser.email);
    // Manually activate user for subsequent tests if email verification is on
    await User.update({ status: 'active', emailVerifiedAt: new Date() }, { where: { email: testUser.email } });
  });
  it('POST /login - should login user', async () => {
    const res = await supertest(fastify.server).post('/api/v1/auth/login').send({ emailOrUsername: testUser.email, password: testUser.password }).expect(200);
    expect(res.body.user.email).toBe(testUser.email);
    accessToken = res.body.accessToken; refreshToken = res.body.refreshToken;
  });
  it('GET /me - should get current user profile', async () => {
    const res = await supertest(fastify.server).get('/api/v1/auth/me').set('Authorization', \`Bearer \${accessToken}\`).expect(200);
    expect(res.body.email).toBe(testUser.email);
  });
  it('POST /refresh-token - should refresh token', async () => {
    const res = await supertest(fastify.server).post('/api/v1/auth/refresh-token').send({ refreshToken }).expect(200);
    expect(res.body.accessToken).not.toBe(accessToken);
  });
});
EOT

echo -e "${GREEN}✅ Application file generation complete.${NC}"
echo ""

# --- Section 2: Docker Deployment ---
echo -e "${BLUE}🐳 Starting Docker deployment process...${NC}"

# 1. Install Node.js dependencies locally (for CLI tools like sequelize-cli, web-push if not already global)
echo -e "  ${BLUE}📦 Ensuring local npm packages for CLI tools are available...${NC}"
npm install --loglevel error --no-fund --no-audit # Suppress extensive output

# 2. Build Docker images
echo -e "  ${BLUE}🛠️  Building Docker images (this might take a while)...${NC}"
if docker-compose build; then
  echo -e "  ${GREEN}✅ Docker images built successfully.${NC}"
else
  echo -e "  ${RED}❌ Docker image build failed. Please check Dockerfile and logs.${NC}"
  exit 1
fi

# 3. Start services in detached mode
echo -e "  ${BLUE}🚀 Starting services with docker-compose up -d...${NC}"
if docker-compose up -d; then
  echo -e "  ${GREEN}✅ Services started successfully in detached mode.${NC}"
else
  echo -e "  ${RED}❌ Failed to start services with docker-compose. Check logs.${NC}"
  exit 1
fi

# 4. Wait for services to be fully ready (especially DB and ES)
echo -e "  ${BLUE}⏳ Waiting for services to initialize (DB, Elasticsearch)...${NC}"
echo -e "    (This could take up to a minute or two, especially for Elasticsearch on first run)"

# Improved wait logic: Loop with health checks
MAX_RETRIES=30 # Approx 5 minutes if sleep is 10s
RETRY_COUNT=0
DB_READY=false
ES_READY=false

while [[ ("\$DB_READY" = false || "\$ES_READY" = false) && \$RETRY_COUNT -lt \$MAX_RETRIES ]]; do
  RETRY_COUNT=\$((RETRY_COUNT + 1))
  echo -ne "    Attempt \$RETRY_COUNT/\$MAX_RETRIES: "
  
  # Check DB
  if ! \$DB_READY; then
    if docker-compose exec -T db pg_isready -U "\${POSTGRES_USER:-ep_user}" -d "\${POSTGRES_DB:-enterprise_app}" -q; then
      DB_READY=true
      echo -ne "${GREEN}DB Ready. ${NC}"
    else
      echo -ne "${YELLOW}DB not ready... ${NC}"
    fi
  else
    echo -ne "${GREEN}DB Ready. ${NC}"
  fi

  # Check ES
  if ! \$ES_READY; then
    # Use curl inside the app container if wget is not in es container, or use host curl
    if docker-compose exec -T elasticsearch curl -s -f http://localhost:9200/_cluster/health?wait_for_status=yellow&timeout=5s > /dev/null; then
      ES_READY=true
      echo -e "${GREEN}ES Ready.${NC}"
    else
      echo -e "${YELLOW}ES not ready...${NC}"
    fi
  else
     echo -e "${GREEN}ES Ready.${NC}"
  fi

  if [[ "\$DB_READY" = true && "\$ES_READY" = true ]]; then
    break
  fi
  sleep 10
done

if [[ "\$DB_READY" = false || "\$ES_READY" = false ]]; then
  echo -e "  ${RED}❌ Services did not become healthy after \$MAX_RETRIES attempts. Check docker-compose logs.${NC}"
  echo -e "    - DB Status: \$DB_READY"
  echo -e "    - ES Status: \$ES_READY"
  echo -e "    To see logs: docker-compose logs"
  exit 1
fi
echo -e "  ${GREEN}✅ Database and Elasticsearch appear to be ready.${NC}"


# 5. Run Database Migrations inside the app container
echo -e "  ${BLUE}📜 Running database migrations...${NC}"
echo -e "${YELLOW}⚠️  IMPORTANT: If this is the first run or models changed, you MUST ensure migration files in ./migrations are correct BEFORE this step completes fully.${NC}"
echo -e "${YELLOW}   This script created placeholder migrations. You need to tailor them to your Sequelize models.${NC}"
ask_proceed "Have you reviewed and updated the migration files in the './migrations' directory to match your models?"

if docker-compose exec -T app npm run migrate; then
  echo -e "  ${GREEN}✅ Database migrations completed successfully.${NC}"
else
  echo -e "  ${RED}❌ Database migrations failed. Check logs: \`docker-compose logs app\`${NC}"
  echo -e "  ${YELLOW}Common issues: Migration files incorrect, DB connection issues, or syntax errors in migrations.${NC}"
  exit 1
fi

# 6. Run Database Seeders
echo -e "  ${BLUE}🌱 Running database seeders...${NC}"
if docker-compose exec -T app npm run seed; then
  echo -e "  ${GREEN}✅ Database seeders completed successfully.${NC}"
else
  echo -e "  ${RED}❌ Database seeders failed. Check logs: \`docker-compose logs app\`${NC}"
  exit 1
fi

# 7. Initialize Elasticsearch Indices
echo -e "  ${BLUE}🔍 Initializing Elasticsearch indices...${NC}"
if docker-compose exec -T app npm run es:init; then
  echo -e "  ${GREEN}✅ Elasticsearch indices initialized successfully.${NC}"
else
  echo -e "  ${RED}❌ Elasticsearch index initialization failed. Check logs: \`docker-compose logs app\` and ensure Elasticsearch is running and accessible.${NC}"
  # exit 1 # This might not be critical for app to start, but search will fail.
fi

# --- Final Instructions ---
echo ""
echo -e "${GREEN}🎉🎉🎉 Enterprise Application Deployment Complete! 🎉🎉🎉${NC}"
echo ""
echo -e "${BLUE}Access your application:${NC}"
echo -e "  🌐 Frontend/API:   ${GREEN}http://localhost:\$(grep '^PORT=' .env | cut -d'=' -f2 || echo 3000)${NC}"
echo -e "  📚 API Docs:     ${GREEN}http://localhost:\$(grep '^PORT=' .env | cut -d'=' -f2 || echo 3000)/documentation${NC}"
echo -e "  🐘 PostgreSQL DB (from host): Port ${YELLOW}5433${NC} (maps to container 5432)"
echo -e "  🔍 Elasticsearch:  ${GREEN}http://localhost:9200${NC}"
echo ""
echo -e "${BLUE}Default Admin Credentials (from seeder, if not changed in .env):${NC}"
echo -e "  👤 Username:       ${YELLOW}$(grep '^ADMIN_INITIAL_USERNAME=' .env | cut -d'=' -f2 || echo "admin")${NC}"
echo -e "  🔑 Password:       ${YELLOW}$(grep '^ADMIN_INITIAL_PASSWORD=' .env | cut -d'=' -f2 || echo "AdminSecurePassword123!")${NC}"
echo ""
echo -e "${BLUE}Manage Services:${NC}"
echo -e "  👀 View Logs:      ${YELLOW}docker-compose logs -f${NC} (or \`docker-compose logs app\`, \`docker-compose logs db\` etc.)"
echo -e "  🛑 Stop Services:  ${YELLOW}docker-compose down${NC}"
echo -e "  ⬆️ Start Services: ${YELLOW}docker-compose up -d${NC} (if already built and configured)"
echo ""
echo -e "${YELLOW}IMPORTANT VAPID KEYS for Web Push (from .env file):${NC}"
echo -e "  Public Key (used in frontend JS): ${GREEN}$(grep '^VAPID_PUBLIC_KEY=' .env | cut -d'=' -f2)${NC}"
echo -e "  ${YELLOW}Ensure this public key is correctly used in your frontend JavaScript for push subscriptions.${NC}"
echo -e "  The \`public/index.html\` generated by this script uses this value via a placeholder."
echo ""
echo -e "${YELLOW}Remember to review and secure all configurations in '.env' for a production environment!${NC}"
echo -e "${YELLOW}Especially Elasticsearch security and database credentials.${NC}"

exit 0
