#!/bin/bash
set -e

GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m'

echo -e "${BLUE}🚀 Starting Enterprise App Deployment with Full Subsystems...${NC}"

# 1. Create enhanced project structure
mkdir -p public/css public/js public/images public/fonts src/config src/routes src/services src/middleware src/utils src/models src/subsystems/{notifications,analytics,reporting,search,audit,workflow-engine,users,messaging,files} tests migrations logs

# 2. Create .env with enhanced configuration
cat <<EOT > .env
PORT=3000
NODE_ENV=production
JWT_SECRET=enterprise_secret_key_2023
DATABASE_URL=postgres://postgres:postgres@db:5432/enterprise?schema=public
PUSHY_API_KEY=your_pushy_api_key
FCM_SERVER_KEY=your_fcm_server_key
VAPID_PUBLIC_KEY=BKdCQZGzXkFh49DqHMsuVzVWlJL0fPfR9rU0T8NlA1oBqUw=
VAPID_PRIVATE_KEY=3K1oVXj3Oe9jZzS0mFzU0Q7tK2tL0fPfR9rU0T8NlA1oBqU=
REDIS_HOST=redis
REDIS_PORT=6379
ELASTICSEARCH_HOST=http://elasticsearch:9200
SENTRY_DSN=https://examplePublicKey@o0.ingest.sentry.io/0 
LOG_LEVEL=debug
LOG_FILE_PATH=/var/log/enterprise-app/application.log
ENABLE_ANALYTICS=true
ENABLE_NOTIFICATIONS=true
ENABLE_REPORTING=true
ENABLE_SEARCH=true
ENABLE_AUDIT=true
ENABLE_WORKFLOW_ENGINE=true
ENABLE_MESSAGING=true
ENABLE_FILES=true
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
    "migrate": "npx sequelize-cli db:migrate",
    "seed": "npx sequelize-cli db:seed:all",
    "build": "webpack --mode production"
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
    "fastify-websocket": "^5.1.0",
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
    "ioredis": "^5.3.1",
    "socket.io": "^4.6.0",
    "stripe": "^14.3.0",
    "twilio": "^4.16.1",
    "multer": "^1.4.5-lts.1",
    "sharp": "^0.32.3",
    "passport": "^0.6.0",
    "passport-jwt": "^4.0.0",
    "passport-local": "^1.0.3",
    "dotenv": "^16.3.1",
    "helmet": "^6.1.2",
    "express-rate-limit": "^6.8.1",
    "xss-clean": "^0.15.1",
    "validator": "^13.9.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "supertest": "^4.0.2",
    "eslint": "^8.56.0",
    "eslint-config-airbnb-base": "^15.0.0",
    "eslint-plugin-import": "^2.28.1",
    "sequelize-cli": "^6.6.2",
    "webpack": "^5.89.0",
    "webpack-cli": "^5.1.4",
    "webpack-dev-server": "^4.13.3",
    "html-webpack-plugin": "^5.5.3"
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
const subsystemsDir = path.join(__dirname, "subsystems");

if (fs.existsSync(subsystemsDir)) {
  const availableSubsystems = fs.readdirSync(subsystemsDir).filter(file => 
    fs.statSync(path.join(subsystemsDir, file)).isDirectory()
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
}

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
const Message = require("./Message")(sequelize);
const File = require("./File")(sequelize);

// Define associations
User.hasMany(Task, { foreignKey: "assigneeId", as: "assignedTasks" });
Task.belongsTo(User, { foreignKey: "assigneeId", as: "assignee" });

User.hasMany(Notification, { foreignKey: "userId" });
Notification.belongsTo(User, { foreignKey: "userId" });

User.hasMany(AuditLog, { foreignKey: "userId" });
AuditLog.belongsTo(User, { foreignKey: "userId" });

User.hasMany(Message, { foreignKey: "senderId", as: "sentMessages" });
User.hasMany(Message, { foreignKey: "receiverId", as: "receivedMessages" });
Message.belongsTo(User, { foreignKey: "senderId", as: "sender" });
Message.belongsTo(User, { foreignKey: "receiverId", as: "receiver" });

User.hasMany(File, { foreignKey: "userId" });
File.belongsTo(User, { foreignKey: "userId" });

module.exports = { sequelize, User, Task, Workflow, Notification, AuditLog, Message, File };
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
      type: DataTypes.ENUM("admin", "manager", "user", "developer", "guest"), 
      defaultValue: "user" 
    },
    email: {
      type: DataTypes.STRING,
      unique: true,
      validate: { isEmail: true }
    },
    firstName: { type: DataTypes.STRING },
    lastName: { type: DataTypes.STRING },
    lastLogin: { type: DataTypes.DATE },
    avatarUrl: { type: DataTypes.STRING },
    status: { 
      type: DataTypes.ENUM("active", "inactive", "suspended"), 
      defaultValue: "active" 
    },
    timezone: { type: DataTypes.STRING, defaultValue: "UTC" },
    locale: { type: DataTypes.STRING, defaultValue: "en-US" }
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
      type: DataTypes.ENUM("pending", "in_progress", "completed", "blocked", "review"), 
      defaultValue: "pending" 
    },
    priority: { 
      type: DataTypes.ENUM("low", "medium", "high", "critical"), 
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
    },
    projectId: { type: DataTypes.INTEGER },
    tags: { type: DataTypes.JSON }
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
    completedAt: { type: DataTypes.DATE },
    metadata: { type: DataTypes.JSON }
  }, {
    indexes: [
      { fields: ['status'] ]
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
      type: DataTypes.ENUM("task", "workflow", "system", "reminder", "message", "file"), 
      defaultValue: "system"
    },
    data: { type: DataTypes.JSON },
    userId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    },
    relatedId: { type: DataTypes.INTEGER },
    relatedType: { type: DataTypes.STRING }
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
    },
    ip: { type: DataTypes.STRING },
    userAgent: { type: DataTypes.STRING },
    location: { type: DataTypes.GEOMETRY('POINT') }
  });
  
  return AuditLog;
};
EOT

# 12. Message model
cat <<EOT > src/models/Message.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const Message = sequelize.define("Message", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    content: { type: DataTypes.TEXT, allowNull: false },
    read: { type: DataTypes.BOOLEAN, defaultValue: false },
    senderId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    },
    receiverId: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    },
    conversationId: { type: DataTypes.STRING },
    parentId: { type: DataTypes.INTEGER },
    attachments: { type: DataTypes.JSON }
  });
  
  return Message;
};
EOT

# 13. File model
cat <<EOT > src/models/File.js
module.exports = (sequelize) => {
  const { DataTypes } = require("sequelize");
  const File = sequelize.define("File", {
    id: { type: DataTypes.INTEGER, primaryKey: true, autoIncrement: true },
    name: { type: DataTypes.STRING, allowNull: false },
    size: { type: DataTypes.INTEGER, allowNull: false },
    mimeType: { type: DataTypes.STRING, allowNull: false },
    path: { type: DataTypes.STRING, allowNull: false },
    url: { type: DataTypes.STRING, allowNull: false },
    uploadedById: { 
      type: DataTypes.INTEGER, 
      references: { model: "Users", key: "id" }
    },
    sharedWith: { type: DataTypes.JSON },
    expiresAt: { type: DataTypes.DATE },
    hash: { type: DataTypes.STRING }
  });
  
  return File;
};
EOT

# 14. Create notifications subsystem
cat <<EOT > src/subsystems/notifications/index.js
const fastifyPlugin = require("fastify-plugin");
const notificationRoutes = require("./routes");

async function notificationSubsystem(fastify, options) {
  // Register notification routes
  fastify.register(notificationRoutes);
}

module.exports = fastifyPlugin(notificationSubsystem);
EOT

# 15. Create notifications routes
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

# 16. Create notifications service
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

# 17. Create analytics subsystem
cat <<EOT > src/subsystems/analytics/index.js
const fastifyPlugin = require("fastify-plugin");
const analyticsRoutes = require("./routes");

async function analyticsSubsystem(fastify, options) {
  // Register analytics routes
  fastify.register(analyticsRoutes);
}

module.exports = fastifyPlugin(analyticsSubsystem);
EOT

# 18. Create analytics routes
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
  
  // Get usage trends
  fastify.get("/trends", async (request, reply) => {
    const trends = await analyticsService.getUsageTrends(request.query);
    return trends;
  });
}
module.exports = analyticsRoutes;
EOT

# 19. Create analytics service
cat <<EOT > src/subsystems/analytics/services.js
const { Task, Workflow, AuditLog, User } = require("../../models");

async function getDashboardMetrics() {
  const [users, tasks, workflows, logs] = await Promise.all([
    User.count(),
    Task.count(),
    Workflow.count(),
    AuditLog.count({
      where: {
        createdAt: {
          $gt: new Date(new Date() - 24 * 60 * 60 * 1000)
        }
      }
    })
  ]);
  
  return {
    users: { total: users },
    tasks: { total: tasks },
    workflows: { total: workflows },
    recentActivity: { count: logs },
    uptime: process.uptime()
  };
}

async function getTaskStatistics() {
  const [total, pending, inProgress, completed, blocked] = await Promise.all([
    Task.count(),
    Task.count({ where: { status: "pending" } }),
    Task.count({ where: { status: "in_progress" } }),
    Task.count({ where: { status: "completed" } }),
    Task.count({ where: { status: "blocked" } })
  ]);
  
  return {
    total,
    byStatus: {
      pending,
      in_progress: inProgress,
      completed,
      blocked
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

async function getUsageTrends(query) {
  const interval = query.interval || "week";
  let groupByClause;
  
  switch(interval) {
    case "day":
      groupByClause = "DATE_TRUNC('day', \"createdAt\")";
      break;
    case "week":
      groupByClause = "DATE_TRUNC('week', \"createdAt\")";
      break;
    case "month":
      groupByClause = "DATE_TRUNC('month', \"createdAt\")";
      break;
    default:
      groupByClause = "DATE_TRUNC('day', \"createdAt\")";
  }
  
  const [results] = await AuditLog.sequelize.query(\`
    SELECT ${groupByClause} AS period, COUNT(*) AS count
    FROM AuditLogs
    WHERE "createdAt" >= NOW() - INTERVAL '30 days'
    GROUP BY period
    ORDER BY period
  \`);
  
  return results;
}

module.exports = { getDashboardMetrics, getTaskStatistics, getUserActivity, getUsageTrends };
EOT

# 20. Create reporting subsystem
cat <<EOT > src/subsystems/reporting/index.js
const fastifyPlugin = require("fastify-plugin");
const reportingRoutes = require("./routes");

async function reportingSubsystem(fastify, options) {
  // Register reporting routes
  fastify.register(reportingRoutes);
}

module.exports = fastifyPlugin(reportingSubsystem);
EOT

# 21. Create reporting routes
cat <<EOT > src/subsystems/reporting/routes.js
async function reportingRoutes(fastify, options) {
  const { reportingService } = require("../services");
  
  // Generate task report
  fastify.get("/tasks", async (request, reply) => {
    const report = await reportingService.generateTaskReport(request.query);
    return report;
  });
  
  // Generate user activity report
  fastify.get("/activity", async (request, reply) => {
    const report = await reportingService.generateActivityReport(request.query);
    return report;
  });
  
  // Export data
  fastify.get("/export/:type", async (request, reply) => {
    const data = await reportingService.exportData(request.params.type, request.query);
    reply.header("Content-Type", "text/csv");
    reply.header("Content-Disposition", "attachment");
    return data;
  });
}
module.exports = reportingRoutes;
EOT

# 22. Create reporting service
cat <<EOT > src/subsystems/reporting/services.js
const { Task, AuditLog } = require("../../models");
const xlsx = require("xlsx");
const pdfMake = require("pdfmake/build/pdfmake");
const pdfFonts = require("pdfmake/build/vfs_fonts");
pdfMake.vfs = pdfFonts.pdfMake.vfs;

async function generateTaskReport(query) {
  const options = {};
  
  if (query.status) {
    options.where = { status: query.status };
  }
  
  const tasks = await Task.findAll(options);
  return formatReport(tasks, query.format || "json");
}

async function generateActivityReport(query) {
  const options = {};
  
  if (query.userId) {
    options.where = { userId: query.userId };
  }
  
  const activities = await AuditLog.findAll(options);
  return formatReport(activities, query.format || "json");
}

function formatReport(data, format) {
  switch(format) {
    case "csv":
      return convertToCSV(data);
    case "xlsx":
      return convertToXLSX(data);
    case "pdf":
      return convertToPDF(data);
    default:
      return data;
  }
}

function convertToCSV(data) {
  if (!data.length) return "";
  
  const headers = Object.keys(data[0].get());
  const csvRows = [headers.join(",")];
  
  data.forEach(item => {
    const values = headers.map(header => {
      const value = item[header];
      return typeof value === "string" ? \`${value.replace(/"/g, '""')}\` : value;
    });
    
    csvRows.push(values.join(","));
  });
  
  return csvRows.join("\n");
}

function convertToXLSX(data) {
  const worksheet = xlsx.utils.json_to_sheet(data);
  const workbook = xlsx.utils.book_new();
  xlsx.utils.book_append_sheet(workbook, worksheet, "Sheet1");
  return xlsx.write(workbook, { bookType: "xlsx", type: "buffer" });
}

function convertToPDF(data) {
  const docDefinition = {
    content: [
      { text: "Enterprise Report", style: "header" },
      "\n",
      {
        table: {
          headerRows: 1,
          widths: Array(Object.keys(data[0]).length).fill("*"),
          body: [
            Object.keys(data[0]),
            ...data.map(item => Object.values(item))
          ]
        }
      }
    ],
    styles: {
      header: {
        fontSize: 18,
        bold: true,
        margin: [0, 0, 0, 10]
      }
    }
  };
  
  const pdfDoc = pdfMake.createPdf(docDefinition);
  return new Promise((resolve, reject) => {
    const buffers = [];
    pdfDoc.stream.on("finish", () => {
      resolve(Buffer.concat(buffers));
    });
    pdfDoc.stream.on("data", (chunk) => {
      buffers.push(chunk);
    });
    pdfDoc.stream.on("error", (err) => {
      reject(err);
    });
    pdfDoc.end();
  });
}

module.exports = { generateTaskReport, generateActivityReport, exportData: convertToXLSX };
EOT

# 23. Create search subsystem
cat <<EOT > src/subsystems/search/index.js
const fastifyPlugin = require("fastify-plugin");
const searchRoutes = require("./routes");

async function searchSubsystem(fastify, options) {
  // Register search routes
  fastify.register(searchRoutes);
}

module.exports = fastifyPlugin(searchSubsystem);
EOT

# 24. Create search routes
cat <<EOT > src/subsystems/search/routes.js
async function searchRoutes(fastify, options) {
  const { searchService } = require("../services");
  
  // Search across entities
  fastify.get("/", async (request, reply) => {
    const results = await searchService.search(request.query.q, request.query.types);
    return results;
  });
  
  // Advanced search
  fastify.get("/advanced", async (request, reply) => {
    const results = await searchService.advancedSearch(request.query);
    return results;
  });
}
module.exports = searchRoutes;
EOT

# 25. Create search service
cat <<EOT > src/subsystems/search/services.js
const { Task, Workflow, User, Message, File } = require("../../models");

async function search(query, types = ["task", "workflow", "user", "message", "file"]) {
  const results = {};
  const searchOptions = {
    where: {
      [Op.or]: [
        { title: { [Op.iLike]: `%\${query}%` } },
        { description: { [Op.iLike]: `%\${query}%` } }
      ]
    }
  };
  
  if (types.includes("task")) {
    results.tasks = await Task.findAll(searchOptions);
  }
  
  if (types.includes("workflow")) {
    results.workflows = await Workflow.findAll(searchOptions);
  }
  
  if (types.includes("user")) {
    results.users = await User.findAll({
      where: {
        [Op.or]: [
          { username: { [Op.iLike]: `%\${query}%` } },
          { firstName: { [Op.iLike]: `%\${query}%` } },
          { lastName: { [Op.iLike]: `%\${query}%` } }
        ]
      }
    });
  }
  
  if (types.includes("message")) {
    results.messages = await Message.findAll({
      where: {
        content: { [Op.iLike]: `%\${query}%` }
      }
    });
  }
  
  if (types.includes("file")) {
    results.files = await File.findAll({
      where: {
        name: { [Op.iLike]: `%\${query}%` }
      }
    });
  }
  
  return results;
}

async function advancedSearch(options) {
  const results = {};
  
  if (options.task) {
    results.tasks = await Task.findAll({
      where: buildQueryOptions(options.task),
      limit: options.limit || 100,
      offset: options.offset || 0
    });
  }
  
  if (options.workflow) {
    results.workflows = await Workflow.findAll(buildQueryOptions(options.workflow));
  }
  
  return results;
}

function buildQueryOptions(params) {
  const where = {};
  
  if (params.filters) {
    Object.entries(params.filters).forEach(([key, value]) => {
      where[key] = { [Op.like]: `%\${value}%` };
    });
  }
  
  if (params.range) {
    const [start, end] = params.range.split(":");
    where.createdAt = {
      [Op.between]: [new Date(start), new Date(end)]
    };
  }
  
  if (params.sort) {
    sort = params.sort.split(",").map(s => s.split(":"));
  }
  
  return { where, sort };
}

module.exports = { search, advancedSearch };
EOT

# 26. Create audit subsystem
cat <<EOT > src/subsystems/audit/index.js
const fastifyPlugin = require("fastify-plugin");
const auditRoutes = require("./routes");

async function auditSubsystem(fastify, options) {
  // Register audit routes
  fastify.register(auditRoutes);
}

module.exports = fastifyPlugin(auditSubsystem);
EOT

# 27. Create audit routes
cat <<EOT > src/subsystems/audit/routes.js
async function auditRoutes(fastify, options) {
  const { auditService } = require("../services");
  
  // Get audit logs
  fastify.get("/", async (request, reply) => {
    const logs = await auditService.getAuditLogs(request.query);
    return logs;
  });
  
  // Create manual audit entry
  fastify.post("/", async (request, reply) => {
    const log = await auditService.createAuditEntry(request.body);
    return reply.code(201).send(log);
  });
}
module.exports = auditRoutes;
EOT

# 28. Create audit service
cat <<EOT > src/subsystems/audit/services.js
const { AuditLog } = require("../../models");

async function getAuditLogs(query) {
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

async function createAuditEntry(entry) {
  return AuditLog.create(entry);
}

module.exports = { getAuditLogs, createAuditEntry };
EOT

# 29. Create workflow-engine subsystem
cat <<EOT > src/subsystems/workflow-engine/index.js
const fastifyPlugin = require("fastify-plugin");
const workflowEngineRoutes = require("./routes");

async function workflowEngineSubsystem(fastify, options) {
  // Register workflow engine routes
  fastify.register(workflowEngineRoutes);
}

module.exports = fastifyPlugin(workflowEngineSubsystem);
EOT

# 30. Create workflow-engine routes
cat <<EOT > src/subsystems/workflow-engine/routes.js
async function workflowEngineRoutes(fastify, options) {
  const { workflowEngineService } = require("../services");
  
  // Create workflow template
  fastify.post("/templates", async (request, reply) => {
    const template = await workflowEngineService.createTemplate(request.body);
    return reply.code(201).send(template);
  });
  
  // Get workflow templates
  fastify.get("/templates", async (request, reply) => {
    const templates = await workflowEngineService.getTemplates(request.query);
    return templates;
  });
  
  // Execute workflow
  fastify.post("/:id/execute", async (request, reply) => {
    const result = await workflowEngineService.executeWorkflow(request.params.id, request.body);
    return result;
  });
}
module.exports = workflowEngineRoutes;
EOT

# 31. Create workflow-engine service
cat <<EOT > src/subsystems/workflow-engine/services.js
const { Workflow } = require("../../models");

async function createTemplate(template) {
  return Workflow.create(template);
}

async function getTemplates(query) {
  return Workflow.findAll(query);
}

async function executeWorkflow(id, context) {
  const workflow = await Workflow.findByPk(id);
  if (!workflow) return { error: "Workflow not found" };
  
  // Validate workflow
  if (workflow.status !== "active") {
    return { error: "Workflow is not active" };
  }
  
  // Process workflow
  let currentContext = { ...context };
  let stepResults = [];
  
  for (let i = workflow.currentStep; i < workflow.steps.length; i++) {
    const step = workflow.steps[i];
    const stepResult = await executeStep(step, currentContext);
    stepResults.push(stepResult);
    
    // Check if step can proceed
    if (!stepResult.success && step.required) {
      return {
        success: false,
        completedSteps: stepResults.slice(0, i),
        failedStep: stepResult
      };
    }
    
    // Update context
    currentContext = {
      ...currentContext,
      ...stepResult.output
    };
    
    // Update workflow state
    await workflow.update({ 
      currentStep: i + 1,
      status: i + 1 === workflow.steps.length ? "completed" : "in_progress"
    });
  }
  
  return {
    success: true,
    results: stepResults,
    finalContext: currentContext
  };
}

async function executeStep(step, context) {
  try {
    // Simulate step execution
    // In a real system, this would call specific services based on step type
    const result = {
      stepId: step.id,
      name: step.name,
      startTime: new Date(),
      output: {},
      success: true
    };
    
    // Add custom logic based on step type
    switch(step.type) {
      case "approval":
        result.output.approved = context.autoApprove || Math.random() > 0.5;
        result.success = result.output.approved;
        break;
        
      case "notification":
        // In a real system, this would send a notification
        result.output.sent = true;
        break;
        
      case "integration":
        // In a real system, this would call external APIs
        result.output.result = "Integration executed";
        break;
        
      default:
        result.output.result = "Step executed";
    }
    
    result.endTime = new Date();
    return result;
  } catch (error) {
    return {
      stepId: step.id,
      name: step.name,
      startTime: new Date(),
      endTime: new Date(),
      success: false,
      error: error.message
    };
  }
}

module.exports = { createTemplate, getTemplates, executeWorkflow };
EOT

# 32. Create messaging subsystem
cat <<EOT > src/subsystems/messaging/index.js
const fastifyPlugin = require("fastify-plugin");
const messagingRoutes = require("./routes");

async function messagingSubsystem(fastify, options) {
  // Register messaging routes
  fastify.register(messagingRoutes);
}

module.exports = fastifyPlugin(messagingSubsystem);
EOT

# 33. Create messaging routes
cat <<EOT > src/subsystems/messaging/routes.js
async function messagingRoutes(fastify, options) {
  const { messagingService } = require("../services");
  
  // Get conversations
  fastify.get("/conversations", async (request, reply) => {
    const conversations = await messagingService.getConversations(request.user.id);
    return conversations;
  });
  
  // Get messages
  fastify.get("/:conversationId/messages", async (request, reply) => {
    const messages = await messagingService.getMessages(request.params.conversationId, request.query);
    return messages;
  });
  
  // Send message
  fastify.post("/messages", async (request, reply) => {
    const message = await messagingService.sendMessage(request.user.id, request.body);
    return reply.code(201).send(message);
  });
}
module.exports = messagingRoutes;
EOT

# 34. Create messaging service
cat <<EOT > src/subsystems/messaging/services.js
const { Message } = require("../../models");

async function getConversations(userId) {
  const [sent, received] = await Promise.all([
    Message.findAll({
      where: { senderId: userId },
      group: ["conversationId"],
      attributes: ["conversationId"]
    }),
    Message.findAll({
      where: { receiverId: userId },
      group: ["conversationId"],
      attributes: ["conversationId"]
    })
  ]);
  
  const conversationIds = [...new Set([...sent.map(s => s.conversationId), ...received.map(r => r.conversationId)])];
  return conversationIds;
}

async function getMessages(conversationId, query) {
  return Message.findAll({
    where: { conversationId },
    limit: query.limit || 100,
    offset: query.offset || 0,
    order: [["createdAt", "DESC"]]
  });
}

async function sendMessage(senderId, message) {
  return Message.create({
    ...message,
    senderId,
    read: false,
    createdAt: new Date(),
    updatedAt: new Date()
  });
}

module.exports = { getConversations, getMessages, sendMessage };
EOT

# 35. Create files subsystem
cat <<EOT > src/subsystems/files/index.js
const fastifyPlugin = require("fastify-plugin");
const filesRoutes = require("./routes");

async function filesSubsystem(fastify, options) {
  // Register files routes
  fastify.register(filesRoutes);
}

module.exports = fastifyPlugin(filesSubsystem);
EOT

# 36. Create files routes
cat <<EOT > src/subsystems/files/routes.js
async function filesRoutes(fastify, options) {
  const { filesService } = require("../services");
  
  // Upload file
  fastify.post("/upload", async (request, reply) => {
    const file = await filesService.uploadFile(request.user.id, request.file, request.body);
    return reply.code(201).send(file);
  });
  
  // Download file
  fastify.get("/:id/download", async (request, reply) => {
    const file = await filesService.getFile(request.params.id, request.user.id);
    if (!file) return reply.code(404).send({ error: "File not found" });
    
    reply.header("Content-Type", file.mimeType);
    reply.header("Content-Disposition", `attachment; filename=\${file.name}`);
    return reply.send(file.buffer);
  });
  
  // Manage file sharing
  fastify.put("/:id/share", async (request, reply) => {
    const updated = await filesService.updateSharing(request.params.id, request.body.sharedWith);
    return updated ? { success: true } : reply.code(404).send({ error: "File not found" });
  });
}
module.exports = filesRoutes;
EOT

# 37. Create files service
cat <<EOT > src/subsystems/files/services.js
const { File } = require("../../models");
const sharp = require("sharp");
const crypto = require("crypto");
const fs = require("fs");
const path = require("path");

async function uploadFile(userId, file, metadata) {
  // Generate unique filename
  const extension = path.extname(file.filename);
  const baseName = path.basename(file.filename, extension);
  const fileName = \`\${baseName}_\${Date.now()}_\${crypto.randomBytes(4).hex()}\${extension}\`;
  
  // Process file
  const filePath = path.join(__dirname, "../../storage", fileName);
  const writeStream = fs.createWriteStream(filePath);
  
  // Save original file
  file.file.pipe(writeStream);
  
  // Create thumbnail for images
  let thumbPath = null;
  if (file.mimetype.startsWith("image/")) {
    thumbPath = path.join(__dirname, "../../storage", "thumbs", fileName);
    await sharp(filePath)
      .resize(200, 200)
      .toFile(thumbPath);
  }
  
  // Save to database
  return File.create({
    name: fileName,
    size: file.byteCount,
    mimeType: file.mimetype,
    path: filePath,
    url: \`/api/files/\${fileName}/download\`,
    uploadedById: userId,
    sharedWith: metadata.sharedWith || [],
    hash: crypto.createHash("sha256").update(fs.readFileSync(filePath)).digest("hex")
  });
}

async function getFile(id, userId) {
  return File.findOne({
    where: {
      id,
      [Op.or]: [
        { uploadedById: userId },
        { sharedWith: { [Op.contains]: [userId] } }
      ]
    }
  });
}

async function updateSharing(id, sharedWith) {
  const file = await File.findByPk(id);
  if (!file) return false;
  
  await file.update({ sharedWith });
  return true;
}

module.exports = { uploadFile, getFile, updateSharing };
EOT

# 38. Create users subsystem
cat <<EOT > src/subsystems/users/index.js
const fastifyPlugin = require("fastify-plugin");
const usersRoutes = require("./routes");

async function usersSubsystem(fastify, options) {
  // Register users routes
  fastify.register(usersRoutes);
}

module.exports = fastifyPlugin(usersSubsystem);
EOT

# 39. Create users routes
cat <<EOT > src/subsystems/users/routes.js
async function usersRoutes(fastify, options) {
  const { usersService } = require("../services");
  
  // Get users
  fastify.get("/", async (request, reply) => {
    const users = await usersService.getUsers(request.query);
    return users;
  });
  
  // Get user profile
  fastify.get("/:id/profile", async (request, reply) => {
    const user = await usersService.getUserProfile(request.params.id);
    return user || reply.code(404).send({ error: "User not found" });
  });
  
  // Update user profile
  fastify.put("/:id/profile", async (request, reply) => {
    const updated = await usersService.updateProfile(request.params.id, request.body);
    return updated ? { success: true } : reply.code(404).send({ error: "User not found" });
  });
}
module.exports = usersRoutes;
EOT

# 40. Create users service
cat <<EOT > src/subsystems/users/services.js
const { User } = require("../../models");
const bcrypt = require("bcryptjs");

async function getUsers(query) {
  const options = {
    limit: query.limit || 100,
    offset: query.offset || 0,
    order: [["createdAt", "DESC"]]
  };
  
  if (query.role) {
    options.where = { role: query.role };
  }
  
  return User.findAll(options);
}

async function getUserProfile(id) {
  return User.findByPk(id, {
    attributes: { exclude: ["password"] }
  });
}

async function updateProfile(id, data) {
  const user = await User.findByPk(id);
  if (!user) return false;
  
  // Handle password change
  if (data.password) {
    data.password = await bcrypt.hash(data.password, 10);
  }
  
  return user.update(data);
}

module.exports = { getUsers, getUserProfile, updateProfile };
EOT

# 41. Create core middleware
cat <<EOT > src/middleware/core.js
const fastifyPlugin = require("fastify-plugin");
const jwt = require("fastify-jwt");
const helmet = require("fastify-helmet");
const rateLimit = require("fastify-rate-limit");
const csrf = require("fastify-csrf");
const swagger = require("fastify-swagger");
const cors = require("fastify-cors");
const multer = require("fastify-multipart");
const pino = require("pino");
const pinoLogger = require("fastify-pino-logger");

async function coreMiddleware(fastify, options) {
  // Register core plugins
  await fastify.register(cors, { origin: "*" });
  await fastify.register(jwt, { secret: process.env.JWT_SECRET });
  await fastify.register(helmet);
  await fastify.register(rateLimit, { 
    max: 100, 
    timeWindow: "1 minute",
    redis: process.env.REDIS_HOST
  });
  await fastify.register(csrf);
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
  await fastify.register(multer);
  await fastify.register(pinoLogger, {
    logger: pino({
      level: process.env.LOG_LEVEL || "info",
      transport: {
        target: "pino-pretty"
      }
    })
  });
  
  // Add authentication hook
  fastify.addHook("onRequest", async (request, reply) => {
    // Skip authentication for login and register
    if (["/api/auth/login", "/api/auth/register"].includes(request.url)) {
      return;
    }
    
    try {
      await request.jwtVerify();
    } catch (err) {
      reply.send(err);
    }
  });
}

module.exports = fastifyPlugin(coreMiddleware);
EOT

# 42. Create public/index.html with PWA capabilities
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
      --color-bg-light: #fff;
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
      border-bottom: 1px solid #eee;
    }
    
    nav {
      display: flex;
      gap: 1rem;
    }
    
    nav button {
      background: none;
      border: none;
      cursor: pointer;
      font-size: 1rem;
      padding: 0.5rem;
      border-radius: 4px;
    }
    
    nav button:hover {
      background: #f0f0f0;
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
      background: var(--color-bg-light);
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
    
    @media (prefers-color-scheme: dark) {
      :root {
        --color-bg: var(--color-bg-dark);
        --color-text: var(--color-text-dark);
        --color-bg-light: #2c2c2c;
      }
    }
  </style>
</head>
<body>
  <header>
    <h1>Enterprise Task Manager</h1>
    <nav>
      <button onclick="showDashboard()">Dashboard</button>
      <button onclick="showTasks()">Tasks</button>
      <button onclick="showWorkflows()">Workflows</button>
      <button onclick="showMessages()">Messages</button>
      <button onclick="showReports()">Reports</button>
    </nav>
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
        
        <div class="card">
          <h3>Recent Activity</h3>
          <ul id="activity-list"></ul>
        </div>
      </div>
    </div>
  </main>

  <script>
    let token = "";
    let ws;
    
    // Initialize WebSocket for real-time updates
    function initWebSocket() {
      ws = new WebSocket(\`ws://localhost:3000/api/messaging/ws\`);
      
      ws.onopen = () => {
        console.log("WebSocket connected");
        ws.send(JSON.stringify({ auth: token }));
      };
      
      ws.onmessage = (event) => {
        const message = JSON.parse(event.data);
        handleRealTimeMessage(message);
      };
      
      ws.onclose = () => {
        setTimeout(initWebSocket, 5000); // Reconnect every 5 seconds
      };
    }

    function handleRealTimeMessage(message) {
      switch(message.type) {
        case "NOTIFICATION":
          showNotification(message.title, message.body);
          updateNotificationBadge();
          break;
          
        case "MESSAGE":
          playNotificationSound();
          updateMessagesIndicator();
          break;
          
        case "TASK_UPDATE":
          refreshTasks();
          break;
          
        case "WORKFLOW_UPDATE":
          refreshWorkflows();
          break;
      }
    }

    function showNotification(title, body) {
      // Show browser notification if supported
      if ("Notification" in window && Notification.permission === "granted") {
        navigator.serviceWorker.ready.then(registration => {
          registration.showNotification(title, {
            body,
            icon: "/icon-192x192.png"
          });
        });
      } else if ("Notification" in window && Notification.permission !== "denied") {
        Notification.requestPermission().then(permission => {
          if (permission === "granted") {
            navigator.serviceWorker.ready.then(registration => {
              registration.showNotification(title, {
                body,
                icon: "/icon-192x192.png"
              });
            });
          }
        });
      }
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
          initWebSocket();
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
        fetch("/api/tasks", { headers: { "Authorization": "Bearer " + token } }),
        fetch("/api/workflows", { headers: { "Authorization": "Bearer " + token } }),
        fetch("/api/audit/activity", { headers: { "Authorization": "Bearer " + token } })
      ])
      .then(async ([tasksRes, workflowsRes, activityRes]) => {
        const tasks = await tasksRes.json();
        const workflows = await workflowsRes.json();
        const activity = await activityRes.json();
        renderDashboard(tasks, workflows, activity);
      });
    }

    function renderDashboard(tasks, workflows, activity) {
      const taskList = document.getElementById("task-list");
      const workflowList = document.getElementById("workflow-list");
      const activityList = document.getElementById("activity-list");
      
      taskList.innerHTML = tasks.map(t => 
        `<li>${t.title} (${t.status})</li>`
      ).join("");
      
      workflowList.innerHTML = workflows.map(w => 
        `<li>${w.name} (Step ${w.currentStep + 1})</li>`
      ).join("");
      
      activityList.innerHTML = activity.slice(0, 5).map(a => 
        `<li>${a.action} - ${new Date(a.createdAt).toLocaleString()}</li>`
      ).join("");
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

# 43. Create manifest.json
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

# 44. Create service worker
cat <<EOT > public/sw.js
importScripts('https://storage.googleapis.com/workbox-cdn/releases/6.4.1/workbox-sw.js'); 

if (workbox) {
  workbox.precaching.precacheAndRoute(self.__WB_MANIFEST);

  // Cache strategies
  workbox.routing.registerRoute(
    ({url}) => url.pathname.startsWith('/api'),
    new workbox.strategies.NetworkFirst()
  );

  workbox.routing.registerRoute(
    ({request}) => request.destination === 'image' || request.destination === 'font',
    new workbox.strategies.CacheFirst({
      cacheName: 'assets-cache',
      plugins: [
        new workbox.expiration.ExpirationPlugin({
          maxEntries: 60,
          maxAgeSeconds: 30 * 24 * 60 * 60, // 30 days
      })
    ]
  })
}

// Push notification handler
self.addEventListener('push', (event) => {
  const data = event.data.json();
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
EOT

# 45. Create Dockerfile
cat <<EOT > Dockerfile
FROM node:18-alpine
WORKDIR /app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 3000
CMD ["node", "src/server.js"]
EOT

# 46. Create docker-compose.yml with Redis and Elasticsearch
cat <<EOT > docker-compose.yml
version: '3.8'
services:
  app:
    build: .
    ports:
      - "3000:3000"
    environment:
      DATABASE_URL: "postgres://postgres:postgres@db:5432/enterprise?schema=public"
      JWT_SECRET: "enterprise_secret_key_2023"
      LOG_LEVEL: "debug"
      LOG_FILE_PATH: "/var/log/enterprise-app/application.log"
      ENABLE_ANALYTICS: "true"
      ENABLE_NOTIFICATIONS: "true"
      ENABLE_REPORTING: "true"
      ENABLE_SEARCH: "true"
      ENABLE_AUDIT: "true"
      ENABLE_WORKFLOW_ENGINE: "true"
      ENABLE_MESSAGING: "true"
      ENABLE_FILES: "true"
    depends_on:
      - db
      - redis
      - elasticsearch

  db:
    image: postgres:15
    environment:
      POSTGRES_USER: "postgres"
      POSTGRES_PASSWORD: "postgres"
      POSTGRES_DB: "enterprise"
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

# 47. Create test suite
cat <<EOT > tests/integration.test.js
const request = require("supertest");
const app = require("../src/server");

describe("Enterprise App Integration Tests", () => {
  let token;
  let userId;
  let taskId;
  let workflowId;

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
      .send({ 
        username: "testuser", 
        password: "testpass123" 
      });
    
    token = loginRes.body.accessToken;
    userId = registerRes.body.user.id;
  });

  test("GET /api/tasks - should return empty array initially", async () => {
    const res = await request(app)
      .get("/api/tasks")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(0);
  });

  test("POST /api/tasks - should create a new task", async () => {
    const res = await request(app)
      .post("/api/tasks")
      .set("Authorization", "Bearer " + token)
      .send({
        title: "Test Task",
        description: "Test Description",
        status: "pending",
        priority: "medium"
      });
    
    expect(res.statusCode).toBe(201);
    expect(res.body.task).toBeDefined();
    taskId = res.body.task.id;
  });

  test("GET /api/workflows - should return empty array", async () => {
    const res = await request(app)
      .get("/api/workflows")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(0);
  });

  test("POST /api/workflows - should create a new workflow", async () => {
    const res = await request(app)
      .post("/api/workflows")
      .set("Authorization", "Bearer " + token)
      .send({
        name: "Test Workflow",
        description: "Test Description",
        steps: []
      });
    
    expect(res.statusCode).toBe(201);
    expect(res.body.workflow).toBeDefined();
    workflowId = res.body.workflow.id;
  });

  test("PUT /api/workflows/:id/next - should move to next step", async () => {
    const res = await request(app)
      .put(\`/api/workflows/\${workflowId}/next`)
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(res.body.currentStep).toBe(1);
  });

  test("GET /api/notifications - should return empty array", async () => {
    const res = await request(app)
      .get("/api/notifications")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(0);
  });

  test("GET /api/analytics/dashboard - should return dashboard metrics", async () => {
    const res = await request(app)
      .get("/api/analytics/dashboard")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty("tasks");
    expect(res.body).toHaveProperty("workflows");
    expect(res.body).toHaveProperty("recentActivity");
  });

  test("GET /api/reports/tasks - should return CSV format", async () => {
    const res = await request(app)
      .get("/api/reports/tasks?format=csv")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-type']).toContain("text/csv");
    expect(res.headers['content-disposition']).toContain("attachment");
  });

  test("GET /api/search?types=user&q=admin - should find admin user", async () => {
    const res = await request(app)
      .get("/api/search?types=user&q=admin")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(res.body).toHaveProperty("users");
    expect(Array.isArray(res.body.users)).toBe(true);
    expect(res.body.users.length).toBe(1);
  });

  test("GET /api/audit/activity - should return activity logs", async () => {
    const res = await request(app)
      .get("/api/audit/activity")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
  });

  test("WebSocket connection", done => {
    const ws = new WebSocket(\`ws://localhost:3000/api/messaging/ws\`);
    ws.onopen = () => {
      expect(ws.readyState).toBe(WebSocket.OPEN);
      done();
    };
    
    ws.onerror = (err) => {
      done.fail(err);
    };
  });

  test("GET /api/messaging/conversations - should return empty array", async () => {
    const res = await request(app)
      .get("/api/messaging/conversations")
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(Array.isArray(res.body)).toBe(true);
    expect(res.body.length).toBe(0);
  });

  test("POST /api/files/upload - should upload file", async () => {
    const fs = require("fs");
    const path = require("path");
    const filePath = path.join(__dirname, "test.txt");
    
    fs.writeFileSync(filePath, "This is a test file");
    
    const res = await request(app)
      .post("/api/files/upload")
      .set("Authorization", "Bearer " + token)
      .attach("file", filePath)
      .field("sharedWith", "all");
    
    expect(res.statusCode).toBe(201);
    expect(res.body).toHaveProperty("id");
    
    // Clean up
    fs.unlinkSync(filePath);
  });

  test("GET /api/files/:id/download - should download file", async () => {
    const res = await request(app)
      .get(\`/api/files/\${res.body.id}/download\`)
      .set("Authorization", "Bearer " + token);
    
    expect(res.statusCode).toBe(200);
    expect(res.headers['content-disposition']).toContain("attachment");
  });
EOT

# 48. Start server
echo -e "${BLUE}🚀 Starting Fastify server...${NC}"
npm run dev &

# 49. Run tests
echo -e "${GREEN}🧪 Running tests...${NC}"
npm run test

# 50. Final instructions
echo -e "${GREEN}✅ Deployment complete!${NC}"
echo "🌐 Open: http://localhost:3000"
echo "🔐 API Docs: http://localhost:3000/documentation"
echo "📱 To install on Android: Visit the site in Chrome > Add to Home screen"
echo "📦 Build for production: npm install pm2 -g && pm2 start dist/server.js --env production"
