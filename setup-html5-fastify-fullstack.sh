#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Enterprise App Deployment with Modular Architecture...${NC}"

# 1. Create enhanced project structure
mkdir -p public/css public/js public/images public/fonts src/config src/routes src/services src/models src/middleware src/utils src/subsystems/{notifications,analytics,reporting,search} tests migrations

# 2. Create .env with enhanced configuration
cat <<EOT > .env
PORT=3000
NODE_ENV=development
JWT_SECRET=enterprise_secret_key
DATABASE_URL=postgres://postgres:postgres@db:5432/enterprise?schema=public
PUSHY_API_KEY=your_pushy_api_key
FCM_SERVER_KEY=your_fcm_server_key
VAPID_PUBLIC_KEY=BKdCQZGzXkFh49DqHMsuVzVWlJL0fPfR9rU0T8NlA1oBqUw=
VAPID_PRIVATE_KEY=3K1oVXj3Oe9jZzS0mFzU0Q7tK2tL0fPfR9rU0T8NlA1oBqU=
REDIS_HOST=redis
REDIS_PORT=6379
LOG_LEVEL=debug
LOG_FILE_PATH=/var/log/enterprise-app/application.log
ENABLE_ANALYTICS=true
ENABLE_NOTIFICATIONS=true
ENABLE_REPORTING=true
ENABLE_SEARCH=true
EOT

# 3. Create package.json with enhanced dependencies
cat <<EOT > package.json
{
  "name": "enterprise-app",
  "version": "1.0.0",
  "description": "Enterprise-grade full-stack app with Fastify, HTML5 Boilerplate, JWT, and workflow engine",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "node --watch src/server.js",
    "test": "jest tests",
    "lint": "eslint .",
    "docs": "swagger-ui-express",
    "migrate": "sequelize-cli db:migrate",
    "seed": "sequelize-cli db:seed:all"
  },
  "dependencies": {
    "fastify": "^4.26.0",
    "fastify-jwt": "^3.0.0",
    "fastify-helmet": "^1.0.0",
    "fastify-rate-limit": "^6.0.0",
    "fastify-csrf": "^3.0.0",
    "fastify-swagger": "^5.0.0",
    "fastify-multipart": "^8.0.0",
    "fastify-autoload": "^5.10.0",
    "fastify-cors": "^2.3.0",
    "winston": "^3.9.0",
    "winston-daily-rotate-file": "^4.0.6",
    "joi": "^17.9.1",
    "pg": "^8.11.0",
    "sequelize": "^6.35.2",
    "bull": "^4.23.0",
    "web-push": "^3.5.4",
    "pushy-sdk": "^2.0.4",
    "elasticsearch": "^7.17.1",
    "moment": "^2.29.4",
    "xlsx": "^0.18.5",
    "pdfmake": "^0.2.7",
    "ioredis": "^5.3.1"
  },
  "devDependencies": {
    "dotenv": "^16.3.1",
    "jest": "^29.7.0",
    "supertest": "^4.0.2",
    "eslint": "^8.56.0",
    "eslint-config-airbnb-base": "^15.0.0",
    "eslint-plugin-import": "^2.28.1",
    "sequelize-cli": "^6.6.2"
  }
}
EOT

# 4. Install dependencies
echo -e "${BLUE}📦 Installing dependencies...${NC}"
npm install

# 5. Create server.js with modular architecture
cat <<EOT > src/server.js
require("dotenv").config();
const fastify = require("fastify")({ 
  logger: {
    level: process.env.LOG_LEVEL || 'info',
    file: process.env.LOG_FILE_PATH || null,
    prettyPrint: true
  }
});
const path = require("path");
const fs = require("fs");
const { format, transports } = require("winston");
const DailyRotateFile = require("winston-daily-rotate-file");
const { combine, timestamp, printf } = format;

// Configure logging
const logFormat = printf(({ level, message, timestamp }) => {
  return \`\${timestamp} [\${level.toUpperCase()}]: \${message}\`;
});

const logger = require("winston").createLogger({
  level: process.env.LOG_LEVEL || "debug",
  format: combine(
    timestamp(),
    logFormat
  ),
  transports: [
    new DailyRotateFile({
      filename: process.env.LOG_FILE_PATH || "logs/application-%DATE%.log",
      datePattern: "YYYY-MM-DD",
      zippedArchive: true,
      maxSize: "20m",
      maxFiles: "14d"
    }),
    new transports.Console()
  ]
});

// Register core plugins
fastify.register(require("./middleware/core"));

// Load subsystems dynamically based on environment variables
const enabledSubsystems = [];
const availableSubsystems = fs.readdirSync(path.join(__dirname, "subsystems")).filter(file => 
  fs.statSync(path.join(__dirname, "subsystems", file)).isDirectory()
);

availableSubsystems.forEach(subsystem => {
  const enableVar = process.env[\`ENABLE_\${subsystem.toUpperCase()}\`];
  if (enableVar === "true" || enableVar === undefined) {
    try {
      const routes = require(\`./subsystems/\${subsystem}\`);
      fastify.register(routes, { prefix: \`/api/\${subsystem}\` });
      enabledSubsystems.push(subsystem);
    } catch (error) {
      logger.error(\`Failed to load subsystem \${subsystem}: \${error.message}\`);
    }
  }
});

// Serve static files
fastify.register(require("fastify-static"), {
  root: path.join(__dirname, "../public"),
  prefix: "/",
});

// Start server
const start = async () => {
  try {
    const PORT = process.env.PORT || 3000;
    
    // Wait for database connection
    const { sequelize } = require("./models");
    await sequelize.authenticate();
    logger.info("✅ Database connection established");
    
    // Sync models
    await sequelize.sync({ alter: true });
    logger.info("✅ Models synchronized");
    
    await fastify.listen({ port: PORT });
    logger.info(\`Server running at http://localhost:\${PORT}\`);
    logger.info(\`Enabled subsystems: \${enabledSubsystems.join(", ") || "none"}\`);
  } catch (err) {
    logger.error(err);
    process.exit(1);
  }
};

start();
EOT

# 6. Create database models with associations
cat <<EOT > src/models/index.js
const { Sequelize } = require("sequelize");
const sequelize = new Sequelize(process.env.DATABASE_URL);
const User = require("./User")(sequelize);
const Task = require("./Task")(sequelize);
const Workflow = require("./Workflow")(sequelize);
const Notification = require("./Notification")(sequelize);
const AuditLog = require("./AuditLog")(sequelize);

// Define associations
User.hasMany(Task, { foreignKey: "assigneeId" });
Task.belongsTo(User, { foreignKey: "assigneeId" });

User.hasMany(Notification, { foreignKey: "userId" });
Notification.belongsTo(User, { foreignKey: "userId" });

User.hasMany(AuditLog, { foreignKey: "userId" });
AuditLog.belongsTo(User, { foreignKey: "userId" });

module.exports = { sequelize, User, Task, Workflow, Notification, AuditLog };
EOT

# 7. Enhanced User model with timestamps
cat <<EOT > src/models/User.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const User = sequelize.define("User", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    username: { 
      type: DataTypes.STRING, 
      unique: true,
      validate: { len: [3, 50] }
    },
    password: { 
      type: DataTypes.STRING,
      validate: { len: [6, 100] }
    },
    role: { 
      type: DataTypes.ENUM("admin", "manager", "user"), 
      defaultValue: "user" 
    },
    email: {
      type: DataTypes.STRING,
      unique: true,
      validate: { isEmail: true }
    },
    firstName: { type: DataTypes.STRING },
    lastName: { type: DataTypes.STRING },
    lastLogin: { type: DataTypes.DATE }
  }, {
    hooks: {
      beforeCreate: (user) => {
        user.createdAt = new Date();
        user.updatedAt = new Date();
      },
      beforeUpdate: (user) => {
        user.updatedAt = new Date();
      }
    }
  });
  
  return User;
};
EOT

# 8. Enhanced Task model with better relationships
cat <<EOT > src/models/Task.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const Task = sequelize.define("Task", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    title: { 
      type: DataTypes.STRING,
      validate: { len: [3, 255] }
    },
    description: { type: DataTypes.TEXT },
    status: { 
      type: DataTypes.ENUM("pending", "in_progress", "completed"), 
      defaultValue: "pending" 
    },
    priority: { 
      type: DataTypes.ENUM("low", "medium", "high"), 
      defaultValue: "medium" 
    },
    dueDate: { type: DataTypes.DATE },
    completedAt: { type: DataTypes.DATE },
    assigneeId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" },
      allowNull: true
    },
    creatorId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    }
  }, {
    paranoid: true,
    defaultScope: {
      where: { deletedAt: null }
    },
    scopes: {
      withDeleted: {
        where: {}
      }
    }
  });
  
  return Task;
};
EOT

# 9. Enhanced Workflow model
cat <<EOT > src/models/Workflow.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const Workflow = sequelize.define("Workflow", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    name: { 
      type: DataTypes.STRING,
      validate: { len: [3, 100] }
    },
    description: { type: DataTypes.TEXT },
    steps: { 
      type: DataTypes.JSON,
      validate: {
        isArray: (value) => {
          if (!Array.isArray(value)) {
            throw new Error("Steps must be an array");
          }
        }
      }
    },
    currentStep: { 
      type: DataTypes.INTEGER, 
      defaultValue: 0,
      validate: { min: 0 }
    },
    status: { 
      type: DataTypes.ENUM("active", "paused", "completed", "archived"), 
      defaultValue: "active" 
    },
    startedAt: { type: DataTypes.DATE },
    completedAt: { type: DataTypes.DATE }
  }, {
    indexes: [
      { fields: ['status'] }
    ]
  });
  
  return Workflow;
};
EOT

# 10. Notification model
cat <<EOT > src/models/Notification.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const Notification = sequelize.define("Notification", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    title: { type: DataTypes.STRING, allowNull: false },
    message: { type: DataTypes.TEXT, allowNull: false },
    read: { type: DataTypes.BOOLEAN, defaultValue: false },
    type: { 
      type: DataTypes.ENUM("task", "workflow", "system", "reminder"), 
      defaultValue: "system"
    },
    data: { type: DataTypes.JSON },
    userId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    }
  });
  
  return Notification;
};
EOT

# 11. Audit Log model
cat <<EOT > src/models/AuditLog.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const AuditLog = sequelize.define("AuditLog", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    action: { type: DataTypes.STRING, allowNull: false },
    description: { type: DataTypes.TEXT },
    entityType: { type: DataTypes.STRING },
    entityId: { type: DataTypes.INTEGER },
    details: { type: DataTypes.JSON },
    userId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    }
  });
  
  return AuditLog;
};
EOT

# 12. Create notifications subsystem
cat <<EOT > src/subsystems/notifications/index.js
const fastifyPlugin = require("fastify-plugin");
const notificationRoutes = require("./routes");

async function notificationSubsystem(fastify, options) {
  // Register notification routes
  fastify.register(notificationRoutes);
}

module.exports = fastifyPlugin(notificationSubsystem);
EOT

# 13. Create notifications routes
cat <<EOT > src/subsystems/notifications/routes.js
async function notificationRoutes(fastify, options) {
  const { notificationService } = require("../services");
  
  // Get user notifications
  fastify.get("/", async (request, reply) => {
    const notifications = await notificationService.getUserNotifications(request.user.id);
    return notifications;
  });
  
  // Mark notification as read
  fastify.put("/:id/read", async (request, reply) => {
    const result = await notificationService.markAsRead(request.params.id, request.user.id);
    return result ? { success: true } : reply.code(404).send({ error: "Notification not found" });
  });
  
  // Subscribe to push notifications
  fastify.post("/subscribe", async (request, reply) => {
    const { subscription } = request.body;
    await notificationService.savePushSubscription(request.user.id, subscription);
    return { success: true };
  });
}
module.exports = notificationRoutes;
EOT

# 14. Create notifications service
cat <<EOT > src/subsystems/notifications/services.js
const { Notification, User } = require("../../models");
const webPush = require("web-push");
const Pushy = require('pushy');

// Initialize Pushy SDK
const pushyClient = new Pushy(process.env.PUSHY_API_KEY);

// VAPID keys for Web Push
const vapidKeys = {
  publicKey: process.env.VAPID_PUBLIC_KEY || 'BKdCQZGzXkFh49DqHMsuVzVWlJL0fPfR9rU0T8NlA1oBqUw=',
  privateKey: process.env.VAPID_PRIVATE_KEY || '3K1oVXj3Oe9jZzS0mFzU0Q7tK2tL0fPfR9rU0T8NlA1oBqU='
};

webPush.setVapidDetails(
  'mailto:example@example.com',
  vapidKeys.publicKey,
  vapidKeys.privateKey
);

async function getUserNotifications(userId) {
  return Notification.findAll({
    where: { userId },
    order: [['createdAt', 'DESC']]
  });
}

async function markAsRead(notificationId, userId) {
  const notification = await Notification.findOne({
    where: { id: notificationId, userId }
  });
  
  if (notification) {
    await notification.update({ read: true });
    return true;
  }
  return false;
}

async function createNotification(userId, title, message, type = "system", data = null) {
  const notification = await Notification.create({
    userId,
    title,
    message,
    type,
    data
  });
  
  // Send push notification
  await sendPushNotification(userId, title, message, data);
  return notification;
}

async function sendPushNotification(userId, title, message, data) {
  // This is a placeholder for your actual implementation
  // You would retrieve the user's push subscription from the database
  
  // 1. Web Push
  const subscription = await getWebPushSubscription(userId);
  if (subscription) {
    try {
      await webPush.sendNotification(
        subscription,
        JSON.stringify({
          title,
          message,
          data,
          icon: '/favicon.ico'
        })
      );
    } catch (error) {
      console.error("Web Push Error:", error);
    }
  }
  
  // 2. FCM (Android)
  const fcmToken = await getFCMToken(userId);
  if (fcmToken) {
    try {
      const response = await fetch('https://fcm.googleapis.com/fcm/send',  {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'key=' + process.env.FCM_SERVER_KEY
        },
        body: JSON.stringify({
          to: fcmToken,
          notification: {
            title,
            body: message,
            click_action: 'OPEN_APP'
          },
          data: data || {}
        })
      });
      
      const result = await response.json();
      console.log("FCM Response:", result);
    } catch (error) {
      console.error("FCM Error:", error);
    }
  }
  
  // 3. Pushy (Alternative)
  try {
    await pushyClient.sendPushNotification({
      to: userId.toString(),
      data: {
        title,
        message,
        ...data
      }
    });
  } catch (error) {
    console.error("Pushy Error:", error);
  }
}

async function savePushSubscription(userId, subscription) {
  // Save subscription to database
  // This is a placeholder for your actual implementation
  console.log("Saving push subscription:", subscription);
  return true;
}

async function getWebPushSubscription(userId) {
  // Retrieve subscription from database
  // This is a placeholder for your actual implementation
  return null;
}

async function getFCMToken(userId) {
  // Retrieve token from database
  // This is a placeholder for your actual implementation
  return null;
}

module.exports = { 
  getUserNotifications, 
  markAsRead, 
  createNotification, 
  savePushSubscription 
};
EOT

# 15. Create analytics subsystem
cat <<EOT > src/subsystems/analytics/index.js
const fastifyPlugin = require("fastify-plugin");
const analyticsRoutes = require("./routes");

async function analyticsSubsystem(fastify, options) {
  // Register analytics routes
  fastify.register(analyticsRoutes);
}

module.exports = fastifyPlugin(analyticsSubsystem);
EOT

# 16. Create analytics routes
cat <<EOT > src/subsystems/analytics/routes.js
async function analyticsRoutes(fastify, options) {
  const { analyticsService } = require("../services");
  
  // Get dashboard metrics
  fastify.get("/dashboard", async (request, reply) => {
    const metrics = await analyticsService.getDashboardMetrics();
    return metrics;
  });
  
  // Get task statistics
  fastify.get("/tasks", async (request, reply) => {
    const stats = await analyticsService.getTaskStatistics();
    return stats;
  });
  
  // Get user activity
  fastify.get("/activity", async (request, reply) => {
    const activity = await analyticsService.getUserActivity(request.query);
    return activity;
  });
}
module.exports = analyticsRoutes;
EOT

# 17. Create analytics service
cat <<EOT > src/subsystems/analytics/services.js
const { Task, Workflow, AuditLog } = require("../../models");

async function getDashboardMetrics() {
  const [tasks, workflows, logs] = await Promise.all([
    Task.count(),
    Workflow.count(),
    AuditLog.count({
      where: {
        createdAt: {
          [Op.gt]: new Date(new Date() - 24 * 60 * 60 * 1000)
        }
      }
    })
  ]);
  
  return {
    tasks: { total: tasks },
    workflows: { total: workflows },
    recentActivity: { count: logs },
    uptime: process.uptime()
  };
}

async function getTaskStatistics() {
  const [total, pending, inProgress, completed] = await Promise.all([
    Task.count(),
    Task.count({ where: { status: "pending" } }),
    Task.count({ where: { status: "in_progress" } }),
    Task.count({ where: { status: "completed" } })
  ]);
  
  return {
    total,
    byStatus: {
      pending,
      inProgress,
      completed
    }
  };
}

async function getUserActivity(query) {
  const options = {
    limit: query.limit || 100,
    offset: query.offset || 0,
    order: [["createdAt", "DESC"]]
  };
  
  if (query.userId) {
    options.where = { userId: query.userId };
  }
  
  return AuditLog.findAll(options);
}

module.exports = { getDashboardMetrics, getTaskStatistics, getUserActivity };
EOT

# 18. Create middleware directory
mkdir -p src/middleware

# 19. Create core middleware
cat <<EOT > src/middleware/core.js
const fastifyPlugin = require("fastify-plugin");
const jwt = require("fastify-jwt");
const helmet = require("fastify-helmet");
const rateLimit = require("fastify-rate-limit");
const csrf = require("fastify-csrf");
const swagger = require("fastify-swagger");

async function coreMiddleware(fastify, options) {
  // Register core plugins
  await fastify.register(jwt, { secret: process.env.JWT_SECRET });
  await fastify.register(helmet);
  await fastify.register(rateLimit, { 
    max: 100, 
    timeWindow: "1 minute",
    redis: process.env.REDIS_HOST
  });
  await fastify.register(csrf);
  
  // Add authentication hook
  fastify.addHook("onRequest", async (request, reply) => {
    // Skip authentication for login and register routes
    if (["/api/auth/login", "/api/auth/register"].includes(request.url)) {
      return;
    }
    
    try {
      await request.jwtVerify();
    } catch (err) {
      reply.send(err);
    }
  });
  
  // Swagger documentation
  await fastify.register(swagger, {
    routePrefix: "/documentation",
    swagger: {
      info: {
        title: "Enterprise App API",
        description: "API documentation",
        version: "1.0.0"
      },
      host: "localhost:3000",
      schemes: ["http"],
      consumes: ["application/json"],
      produces: ["application/json"]
    }
  });
}

module.exports = fastifyPlugin(coreMiddleware);
EOT

# 20. Create public/index.html with PWA capabilities
cat <<EOT > public/index.html
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <title>Enterprise Task Manager</title>
  <meta name="viewport" content="width=device-width, initial-scale=1">
  <meta name="mobile-web-app-capable" content="yes">
  <meta name="apple-mobile-web-app-capable" content="yes">
  <link rel="manifest" href="/manifest.json">
  <link rel="icon" href="/favicon.ico" sizes="any">
  <link rel="icon" href="/icon.svg" type="image/svg+xml">
  <link rel="apple-touch-icon" href="/apple-touch-icon.png">
  <link rel="stylesheet" href="/css/main.css">
  <style>
    /* Minimal CSS Reset */
    *, *::before, *::after {
      box-sizing: border-box;
      margin: 0;
      padding: 0;
    }
    
    :root {
      --color-primary: #3498db;
      --color-secondary: #2ecc71;
      --color-accent: #f39c12;
      --color-bg: #f4f4f4;
      --color-text: #333;
      --color-bg-dark: #1a1a1a;
      --color-text-dark: #f5f5f5;
    }
    
    body {
      font-family: system-ui, sans-serif;
      background-color: var(--color-bg);
      color: var(--color-text);
      line-height: 1.6;
      padding: 1rem;
    }
    
    .container {
      max-width: 1200px;
      margin: 0 auto;
      padding: 1rem;
    }
    
    header {
      display: flex;
      justify-content: space-between;
      align-items: center;
      padding: 1rem 0;
    }
    
    .notification-badge {
      position: relative;
    }
    
    .badge {
      position: absolute;
      top: -5px;
      right: -5px;
      background: red;
      color: white;
      border-radius: 50%;
      width: 20px;
      height: 20px;
      text-align: center;
      font-size: 0.75rem;
      display: none;
    }
    
    main {
      margin-top: 2rem;
    }
    
    .dashboard-grid {
      display: grid;
      gap: 1rem;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
    }
    
    .card {
      background: white;
      border-radius: 8px;
      box-shadow: 0 2px 5px rgba(0,0,0,0.1);
      padding: 1rem;
    }
    
    .btn {
      display: inline-block;
      background: var(--color-primary);
      color: white;
      border: none;
      padding: 0.5rem 1rem;
      border-radius: 4px;
      cursor: pointer;
      margin-top: 1rem;
    }
    
    .btn:hover {
      background: #2980b9;
    }
    
    ul {
      list-style: none;
      margin-top: 1rem;
    }
    
    li {
      padding: 0.5rem 0;
      border-bottom: 1px solid #eee;
    }
    
    @media (prefers-color-scheme: dark) {
      :root {
        --color-bg: var(--color-bg-dark);
        --color-text: var(--color-text-dark);
      }
    }
  </style>
</head>
<body>
  <header>
    <h1>Enterprise Task Manager</h1>
    <div class="notification-badge">
      <button id="notifications-btn">🔔</button>
      <span class="badge" id="notification-count">0</span>
    </div>
  </header>

  <main class="container">
    <div id="auth">
      <h2>Login</h2>
      <input type="text" id="username" placeholder="Username" />
      <input type="password" id="password" placeholder="Password" />
      <button onclick="login()">Login</button>
      <button onclick="register()">Register</button>
    </div>
    
    <div id="dashboard" style="display: none;">
      <h2>Dashboard</h2>
      <div class="dashboard-grid">
        <div class="card">
          <h3>Tasks</h3>
          <ul id="task-list"></ul>
          <button class="btn" onclick="createTask()">Create New Task</button>
        </div>
        
        <div class="card">
          <h3>Workflows</h3>
          <ul id="workflow-list"></ul>
          <button class="btn" onclick="createWorkflow()">Create New Workflow</button>
        </div>
      </div>
    </div>
  </main>

  <script>
    let token = "";
    let serviceWorkerRegistration;

    // Request notification permission
    async function requestNotificationPermission() {
      if (!("Notification" in window)) {
        console.error("This browser does not support notifications");
        return;
      }

      const permission = await Notification.requestPermission();
      if (permission === "granted") {
        console.log("Notification permission granted.");
        registerServiceWorker();
      }
    }

    async function registerServiceWorker() {
      if ("serviceWorker" in navigator) {
        try {
          serviceWorkerRegistration = await navigator.serviceWorker.register("/sw.js");
          console.log("Service Worker registered");
          
          // Get push subscription
          let subscription = await serviceWorkerRegistration.pushManager.getSubscription();
          
          if (!subscription) {
            subscription = await serviceWorkerRegistration.pushManager.subscribe({
              userVisibleOnly: true,
              applicationServerKey: urlBase64ToUint8Array("${vapidKeys.publicKey}")
            });
          }
          
          // Send subscription to server
          await fetch("/api/notifications/subscribe", {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "Authorization": "Bearer " + token
            },
            body: JSON.stringify(subscription)
          });
        } catch (error) {
          console.error("Service Worker registration failed:", error);
        }
      }
    }

    function urlBase64ToUint8Array(base64String) {
      const padding = "=".repeat((4 - base64String.length % 4) % 4);
      const base64 = (base64String + padding)
        .replace(/-/g, "+")
        .replace(/_/g, "/");
      
      const rawData = window.atob(base64);
      const outputArray = new Uint8Array(rawData.length);
      
      for (let i = 0; i < rawData.length; ++i) {
        outputArray[i] = rawData.charCodeAt(i);
      }
      return outputArray;
    }

    function login() {
      const username = document.getElementById("username").value;
      const password = document.getElementById("password").value;
      
      fetch("/api/auth/login", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password })
      })
      .then(res => res.json())
      .then(data => {
        if (data.token) {
          token = data.token;
          document.getElementById("auth").style.display = "none";
          document.getElementById("dashboard").style.display = "block";
          requestNotificationPermission();
          showDashboard();
        } else {
          alert("Login failed: " + data.error);
        }
      });
    }

    function register() {
      const username = document.getElementById("username").value;
      const password = document.getElementById("password").value;
      
      fetch("/api/auth/register", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ username, password, role: "user" })
      })
      .then(res => res.json())
      .then(data => {
        alert("Registration successful!");
      });
    }

    function showDashboard() {
      Promise.all([
        fetchTasks(),
        fetchWorkflows()
      ]).then(([tasks, workflows]) => {
        renderDashboard(tasks, workflows);
      });
    }

    function fetchTasks() {
      return fetch("/api/tasks", {
        headers: { "Authorization": "Bearer " + token }
      })
      .then(res => res.json());
    }

    function fetchWorkflows() {
      return fetch("/api/workflows", {
        headers: { "Authorization": "Bearer " + token }
      })
      .then(res => res.json());
    }

    function fetchNotifications() {
      return fetch("/api/notifications", {
        headers: { "Authorization": "Bearer " + token }
      })
      .then(res => res.json());
    }

    async function renderDashboard(tasks, workflows) {
      const taskList = document.getElementById("task-list");
      const workflowList = document.getElementById("workflow-list");
      
      taskList.innerHTML = tasks.map(t => 
        `<li>${t.title} (${t.status})</li>`
      ).join("");
      
      workflowList.innerHTML = workflows.map(w => 
        `<li>${w.name} (Step ${w.currentStep + 1})</li>`
      ).join("");
      
      // Update notification count
      const notifications = await fetchNotifications();
      const unreadCount = notifications.filter(n => !n.read).length;
      const badge = document.getElementById("notification-count");
      badge.textContent = unreadCount;
      badge.style.display = unreadCount > 0 ? "inline-block" : "none";
    }

    function createTask() {
      const title = prompt("Enter task title:");
      const description = prompt("Enter task description:");
      fetch("/api/tasks", {
        method: "POST",
        headers: { 
          "Authorization": "Bearer " + token, 
          "Content-Type": "application/json" 
        },
        body: JSON.stringify({ 
          title, 
          description, 
          status: "pending", 
          priority: "medium" 
        })
      })
      .then(res => res.json())
      .then(data => {
        alert("Task created!");
        showDashboard();
      });
    }

    function createWorkflow() {
      const name = prompt("Enter workflow name:");
      const description = prompt("Enter workflow description:");
      fetch("/api/workflows", {
        method: "POST",
        headers: { 
          "Authorization": "Bearer " + token, 
          "Content-Type": "application/json" 
        },
        body: JSON.stringify({ 
          name, 
          description, 
          steps: []
        })
      })
      .then(res => res.json())
      .then(data => {
        alert("Workflow created!");
        showDashboard();
      });
    }

    // Handle incoming messages from Service Worker
    navigator.serviceWorker.addEventListener("message", (event) => {
      console.log("Received message from Service Worker:", event.data);
      
      if (event.data.type === "NOTIFICATION") {
        // Show toast notification
        const notificationToast = document.createElement("div");
        notificationToast.style.position = "fixed";
        notificationToast.style.bottom = "20px";
        notificationToast.style.right = "20px";
        notificationToast.style.backgroundColor = "#333";
        notificationToast.style.color = "#fff";
        notificationToast.style.padding = "1rem 2rem";
        notificationToast.style.borderRadius = "4px";
        notificationToast.style.zIndex = "1000";
        notificationToast.style.animation = "fadeIn 0.5s, fadeOut 3s forwards";
        notificationToast.style.opacity = "0";
        notificationToast.style.transition = "opacity 0.5s";
        
        notificationToast.innerHTML = \`
          <strong>\${event.data.title}</strong><br>
          <small>\${event.data.message}</small>
        \`;
        
        document.body.appendChild(notificationToast);
        
        setTimeout(() => {
          notificationToast.style.opacity = "1";
        }, 100);
        
        setTimeout(() => {
          notificationToast.style.opacity = "0";
          setTimeout(() => {
            notificationToast.remove();
          }, 500);
        }, 4000);
        
        // Update notification count
        showDashboard();
      }
    });

    // Animation keyframes
    const styleSheet = document.createElement("style");
    styleSheet.type = "text/css";
    styleSheet.innerText = \`
      @keyframes fadeIn {
        from { opacity: 0; transform: translateY(20px); }
        to { opacity: 1; transform: translateY(0); }
      }
      @keyframes fadeOut {
        from { opacity: 1; }
        to { opacity: 0; }
      }
    \`;
    document.head.appendChild(styleSheet);
  </script>

  <!-- Service Worker Registration -->
  <script>
    if ("serviceWorker" in navigator) {
      window.addEventListener("load", () => {
        navigator.serviceWorker.register("/sw.js").then(
          (registration) => {
            console.log("Service Worker registered:", registration);
          },
          (error) => {
            console.error("Service Worker registration failed:", error);
          }
        );
      });
    }
  </script>
</body>
</html>
EOT

# 21. Create manifest.json
cat <<EOT > public/manifest.json
{
  "name": "Enterprise Task Manager",
  "short_name": "ETM",
  "start_url": ".",
  "display": "standalone",
  "background_color": "#ffffff",
  "description": "Enterprise Task Management System",
  "theme_color": "#3498db",
  "icons": [
    {
      "src": "/icon-192x192.png",
      "sizes": "192x192",
      "type": "image/png"
    },
    {
      "src": "/icon-512x512.png",
      "sizes": "512x512",
      "type": "image/png"
    }
  ]
}
EOT

# 22. Create service worker
cat <<EOT > public/sw.js
importScripts('https://storage.googleapis.com/workbox-cdn/releases/6.4.1/workbox-sw.js'); 

if (workbox) {
  workbox.precaching.precacheAndRoute(self.__WB_MANIFEST);

  // Cache strategies
  workbox.routing.registerRoute(
    new RegExp('/api/.*'),
    new workbox.strategies.NetworkFirst()
  );

  workbox.routing.registerRoute(
    /\.(?:js|css|png|jpg|jpeg|svg)$/,
    new workbox.strategies.CacheFirst()
  );

  // Push notification handler
  self.addEventListener('push', (event) => {
    const data = event.data.json();
    console.log('Push notification received:', data);
    
    const options = {
      body: data.message,
      icon: '/icon-192x192.png',
      badge: '/icon-badge.png',
      data: data.data,
      actions: [
        { action: 'open', title: 'Open' },
        { action: 'close', title: 'Close' }
      ]
    };
    
    event.waitUntil(
      self.registration.showNotification(data.title, options)
    );
  });

  // Notification click handler
  self.addEventListener('notificationclick', (event) => {
    event.notification.close();
    
    if (event.action === 'open') {
      event.waitUntil(
        clients.openWindow('/')
      );
    }
  });
} else {
  console.log('Workbox did not load');
}
EOT

# 23. Create Dockerfile
cat <<EOT > Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "src/server.js"]
EOT

# 24. Create docker-compose.yml with Redis and Elasticsearch
cat <<EOT > docker-compose.yml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=postgres://postgres:postgres@db:5432/enterprise?schema=public
      - JWT_SECRET=enterprise_secret_key
      - LOG_LEVEL=debug
      - LOG_FILE_PATH=/var/log/enterprise-app/application.log
      - ENABLE_ANALYTICS=true
      - ENABLE_NOTIFICATIONS=true
      - VAPID_PUBLIC_KEY=BKdCQZGzXkFh49DqHMsuVzVWlJL0fPfR9rU0T8NlA1oBqUw=
      - VAPID_PRIVATE_KEY=3K1oVXj3Oe9jZzS0mFzU0Q7tK2tL0fPfR9rU0T8NlA1oBqU=
      - PUSHY_API_KEY=your_pushy_api_key
      - FCM_SERVER_KEY=your_fcm_server_key
      - REDIS_HOST=redis
      - ELASTICSEARCH_HOST=http://elasticsearch:9200
    depends_on:
      - db
      - redis
      - elasticsearch

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: postgres
      POSTGRES_PASSWORD: postgres
      POSTGRES_DB: enterprise
    ports:
      - "5432:5432"
    volumes:
      - postgres_data:/var/lib/postgresql/data

  redis:
    image: redis:alpine
    ports:
      - "6379:6379"
    volumes:
      - redis_data:/data

  elasticsearch:
    image: docker.elastic.co/elasticsearch/elasticsearch:7.17.1
    environment:
      discovery.type: single-node
      ES_JAVA_OPTS: "-Xms1g -Xmx1g"
    ports:
      - "9200:9200"
    volumes:
      - esdata:/usr/share/elasticsearch/data

volumes:
  postgres_data:
  redis_data:
  esdata:
EOT

# 25. Create test
cat <<EOT > tests/notification.test.js
const request = require("supertest");
const app = require("../src/server");

describe("Notification API", () => {
  let token;
  let userId;

  beforeAll(async () => {
    // Register test user
    const registerRes = await request(app)
      .post("/api/auth/register")
      .send({
        username: "testuser",
        password: "testpass123",
        email: "test@example.com"
      });
    
    // Login test user
    const loginRes = await request(app)
      .post("/api/auth/login")
      .send({ username: "testuser", password: "testpass123" });
    
    token = loginRes.body.accessToken;
    userId = registerRes.body.user.id;
  });

  test("GET /api/notifications - should return empty array initially", async () => {
    const res = await request(app)
      .get("/api/notifications")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(0);
  });

  test("POST /api/notifications/subscribe - should subscribe to push notifications", async () => {
    const subscription = {
      endpoint: "https://mock-endpoint.com", 
      expirationTime: null,
      keys: {
        p256dh: "mock-p256dh-key",
        auth: "mock-auth-key"
      }
    };
    
    const res = await request(app)
      .post("/api/notifications/subscribe")
      .set("Authorization", "Bearer " + token)
      .send({ subscription });
    
    expect(res.statusCode).toBe(200);
    expect(res.body.success).toBe(true);
  });

  test("Should receive notification when assigned task", async () => {
    // Create task for this user
    const taskRes = await request(app)
      .post("/api/tasks")
      .set("Authorization", "Bearer " + token)
      .send({
        title: "Test Task",
        description: "Test Description",
        assigneeId: userId
      });
    
    expect(taskRes.statusCode).toBe(201);
    
    // Check notifications
    const notifRes = await request(app)
      .get("/api/notifications")
      .set("Authorization", "Bearer " + token);
    
    expect(notifRes.statusCode).toBe(200);
    expect(Array.isArray(notifRes.body)).toBe(true);
    expect(notifRes.body.some(n => n.type === "task")).toBe(true);
  });
});
EOT

# 26. Start server
echo -e "${BLUE}🚀 Starting Fastify server...${NC}"
npm run dev &

# 27. Run tests
echo -e "${GREEN}🧪 Running tests...${NC}"
npm run test

# 28. Final instructions
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo "🌐 Open: http://localhost:3000"
echo "🔐 API Docs: http://localhost:3000/documentation"
echo "📱 To install on Android: Visit the site in Chrome > Add to Home Screen"
echo "📦 Build for production: npm install pm2 -g && pm2 start src/server.js --env production"
