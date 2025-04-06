import http from 'http';
import { Client, GatewayIntentBits, Partials, ChannelType } from 'discord.js';
import { URL } from 'url';
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';
import { WebSocketServer } from 'ws'; // Import WebSocketServer

// --- Environment Setup ---
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
dotenv.config({ path: path.resolve(__dirname, '.env') });

// --- Configuration ---
const PORT = process.env.PORT || 3000; // Port for the HTTP/WebSocket server
const ADMIN_DISCORD_ID = process.env.ADMIN_DISCORD_ID;
const MAX_MESSAGES_FETCH = 10; // Max messages to fetch when checking DMs via GET

if (!ADMIN_DISCORD_ID) {
    console.error("Error: ADMIN_DISCORD_ID environment variable is not set.");
    process.exit(1);
}

// --- Global State ---
// Stores persistent Discord clients, keyed by vm_user
const discordClients = new Map();
// Stores active WebSocket connections, keyed by vm_user
const wsClients = new Map();
// Stores last fetched message timestamp (still useful for GET endpoint)
const lastMessageTimestamps = {};

// --- Helper Functions ---

function getBotToken(vmUser) {
    return process.env[`BOT_TOKEN_${vmUser}`];
}

// Logs in a single bot and stores it
async function loginAndStoreBot(vmUser, token) {
    if (!token) {
        console.warn(`No token found for ${vmUser}, skipping bot login.`);
        return null;
    }
    if (discordClients.has(vmUser)) {
        console.log(`Bot for ${vmUser} already logged in.`);
        return discordClients.get(vmUser);
    }

    console.log(`Attempting persistent login for bot ${vmUser}...`);
    const client = new Client({
        intents: [
            GatewayIntentBits.Guilds,
            GatewayIntentBits.DirectMessages,
            GatewayIntentBits.MessageContent
        ],
        partials: [Partials.Channel],
    });

    client.on('error', (error) => {
        console.error(`Discord Client Error for ${vmUser}:`, error);
        // Optional: Attempt to reconnect or handle specific errors
    });

    client.on('warn', (warning) => {
        console.warn(`Discord Client Warning for ${vmUser}:`, warning);
    });

    client.on('messageCreate', async (message) => {
        // Ignore messages from bots (including self) and non-DMs
        if (message.author.bot || message.channel.type !== ChannelType.DM) return;

        // Check if the message is from the ADMIN_DISCORD_ID
        if (message.author.id === ADMIN_DISCORD_ID) {
            console.log(`Received DM from ADMIN (${ADMIN_DISCORD_ID}) for bot ${vmUser}`);

            // Find the WebSocket client for this vmUser
            const wsClient = wsClients.get(vmUser);
            if (wsClient && wsClient.readyState === wsClient.OPEN) {
                console.log(`Sending reply notification to WebSocket client for ${vmUser}`);
                try {
                    wsClient.send(JSON.stringify({ type: 'reply_notification', recipient: vmUser }));
                } catch (wsError) {
                    console.error(`Failed to send WebSocket notification to ${vmUser}:`, wsError);
                }
            } else {
                console.log(`No active WebSocket client found for ${vmUser} to send notification.`);
            }
        }
    });

    try {
        await client.login(token);
        console.log(`Bot for ${vmUser} logged in successfully as ${client.user.tag}`);
        discordClients.set(vmUser, client); // Store the persistent client
        return client;
    } catch (error) {
        console.error(`Failed to login bot for ${vmUser}: ${error.message}`);
        client.destroy(); // Clean up failed client
        return null;
    }
}

// Initialize all bots based on environment variables
async function initializeBots() {
    console.log("Initializing Discord bots...");
    for (const key in process.env) {
        if (key.startsWith('BOT_TOKEN_')) {
            const vmUser = key.substring('BOT_TOKEN_'.length);
            const token = process.env[key];
            await loginAndStoreBot(vmUser, token);
        }
    }
    console.log("Bot initialization complete.");
}

// --- HTTP Server Logic ---
const server = http.createServer(async (req, res) => {
    // Log ALL incoming requests immediately
    // console.log(`[HTTP Server] Incoming request: ${req.method} ${req.url}`); // Keep this commented out unless needed

    const requestUrl = new URL(req.url, `http://${req.headers.host}`);
    const { method } = req;
    const pathParts = requestUrl.pathname.split('/').filter(part => part);

    // console.log(`Received ${method} request for ${requestUrl.pathname}`);

    // --- Send Message Endpoint ---
    if (method === 'POST' && pathParts[0] === 'message') {
        // console.log('[HTTP POST /message] Matched route.'); // Remove internal log
        let body = ''; // Declare body here, once
        req.on('data', chunk => {
             // console.log('[HTTP POST /message] Receiving body chunk...'); // Remove internal log
             body += chunk.toString(); // Append to the single body variable
        });
        req.on('end', async () => {
            // console.log('[HTTP POST /message] Request body received completely.'); // Remove internal log
            // Wrap the entire handler logic in a try-catch
            try {
                // console.log('[HTTP POST /message] Parsing body:', body); // Remove internal log
                const { vm_user, target, message } = JSON.parse(body); // Keep this try-catch for JSON parsing specifically
                // console.log(`[HTTP POST /message] Parsed data: vm_user=${vm_user}, target=${target}`); // Remove internal log
                if (!vm_user || !target || !message) {
                    console.error('[HTTP POST /message] Missing required fields.');
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Missing vm_user, target, or message' }));
                    return;
                }

                // Get the persistent client for this user
                // console.log(`[HTTP POST /message] Getting Discord client for user: ${vm_user}`); // Remove internal log
                const discordClient = discordClients.get(vm_user);
                if (!discordClient || !discordClient.isReady()) {
                     console.error(`Bot for ${vm_user} is not ready or not logged in.`); // Keep important errors
                     // Attempt re-login?
                     const token = getBotToken(vm_user); // Get token first
                     if (token) { // Only try if token exists
                         // console.log(`[HTTP POST /message] Attempting to re-login bot for ${vm_user}...`); // Remove internal log
                         const loggedInClient = await loginAndStoreBot(vm_user, token); // Try logging in again
                         if (!loggedInClient || !loggedInClient.isReady()) {
                              console.error(`Re-login failed or bot not ready for ${vm_user}.`); // Keep important errors
                              res.writeHead(503, { 'Content-Type': 'application/json' });
                              res.end(JSON.stringify({ error: `Bot for ${vm_user} is not available. Please try again later.` }));
                              return;
                         }
                         // console.log(`[HTTP POST /message] Re-login successful for ${vm_user}. Proceeding.`); // Remove internal log
                         // Use the newly logged-in client for the rest of the request
                     } else { // No token found
                         console.error(`Bot token not configured for user ${vm_user}.`); // Keep important errors
                         res.writeHead(500, { 'Content-Type': 'application/json' });
                         res.end(JSON.stringify({ error: `Bot token not configured for user ${vm_user}` }));
                         return;
                     }
                } // End of check for discordClient ready

                // Determine target user ID
                // console.log(`[HTTP POST /message] Determining target Discord ID for target: ${target}`); // Remove internal log
                let targetUserId = ADMIN_DISCORD_ID; // Default to admin
                if (target.startsWith('@') && target.toLowerCase() === '@admin') {
                    // console.log(`[HTTP POST /message] Target is @admin, using ADMIN_DISCORD_ID: ${ADMIN_DISCORD_ID}`); // Remove internal log
                } else if (/^\d+$/.test(target)) { // Check if target is a numeric ID
                    targetUserId = target;
                    // console.log(`[HTTP POST /message] Target is numeric ID: ${targetUserId}`); // Remove internal log
                } else if (target !== ADMIN_DISCORD_ID) {
                     console.warn(`Target '${target}' not recognized. Defaulting to ADMIN_DISCORD_ID: ${ADMIN_DISCORD_ID}.`); // Keep important warnings
                     // targetUserId remains ADMIN_DISCORD_ID
                } else {
                     // console.log(`[HTTP POST /message] Target matches ADMIN_DISCORD_ID: ${ADMIN_DISCORD_ID}`); // Remove internal log
                }

                try {
                    // console.log(`[HTTP POST /message] Fetching target user: ${targetUserId}`); // Remove internal log
                    const targetUser = await discordClients.get(vm_user).users.fetch(targetUserId); // Use the persistent client
                    if (!targetUser) throw new Error(`Could not find target user ID ${targetUserId}`);

                    // console.log(`[HTTP POST /message] Sending message via bot ${vm_user} to ${targetUser.tag}`); // Remove internal log
                    await targetUser.send(`[${vm_user}]: ${message}`);
                    console.log(`Message sent successfully via bot ${vm_user} to ${targetUser.tag}`); // Keep success log
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, message: 'Message sent' }));
                } catch (error) {
                    console.error(`Error sending message for ${vm_user}:`, error); // Keep important errors
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: `Failed to send message: ${error.message}` }));
                }
                // NOTE: We DO NOT destroy the client here anymore

            } catch (handlerError) { // Catch errors within the main handler logic
                console.error("Uncaught error in POST /message handler:", handlerError); // Keep important errors
                // Avoid sending response if headers already sent
                if (!res.headersSent) {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Internal server error processing message request.' }));
                }
            }
        });
        // Add error handler for the request stream itself
        req.on('error', (err) => {
             console.error('Request stream error on POST /message:', err); // Keep important errors
             if (!res.headersSent) {
                 res.writeHead(400, { 'Content-Type': 'application/json' });
                 res.end(JSON.stringify({ error: 'Bad request.' }));
             }
        });
    }
    // --- Receive Messages Endpoint (for CLI fetch after notification) ---
    else if (method === 'GET' && pathParts[0] === 'messages' && pathParts[1]) {
        const vm_user = decodeURIComponent(pathParts[1]);
        const discordClient = discordClients.get(vm_user); // Get persistent client

        if (!discordClient || !discordClient.isReady()) {
            console.error(`GET /messages: Bot for ${vm_user} is not available.`); // Keep error
            res.writeHead(503, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: `Bot for ${vm_user} is not available.` }));
            return;
        }

        try {
            const adminUser = await discordClient.users.fetch(ADMIN_DISCORD_ID);
            if (!adminUser) throw new Error(`Could not fetch admin user profile`);

            const dmChannel = await adminUser.createDM();
            if (!dmChannel || dmChannel.type !== ChannelType.DM) throw new Error(`Could not establish DM channel`);

            const fetchOptions = { limit: MAX_MESSAGES_FETCH };
            const lastTimestamp = lastMessageTimestamps[vm_user];

            const messages = await dmChannel.messages.fetch(fetchOptions);

            const newMessages = messages
                .filter(msg => msg.author.id === ADMIN_DISCORD_ID && (!lastTimestamp || msg.createdTimestamp > lastTimestamp))
                .map(msg => ({
                    timestamp: msg.createdTimestamp,
                    author: msg.author.tag,
                    content: msg.content
                }))
                .sort((a, b) => a.timestamp - b.timestamp);

            // Update timestamp based on fetched messages
            if (newMessages.length > 0) {
                lastMessageTimestamps[vm_user] = newMessages[newMessages.length - 1].timestamp;
            } else if (!lastTimestamp && messages.size > 0) {
                 const latestAdminMsg = messages
                     .filter(msg => msg.author.id === ADMIN_DISCORD_ID)
                     .sort((a, b) => b.createdTimestamp - a.createdTimestamp)
                     .first();
                 if (latestAdminMsg) lastMessageTimestamps[vm_user] = latestAdminMsg.createdTimestamp;
            }

            // console.log(`GET /messages/${vm_user}: Found ${newMessages.length} new messages since last check.`); // Remove internal log
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(newMessages));

        } catch (error) {
            console.error(`Error fetching messages for ${vm_user}:`, error); // Keep important errors
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: `Failed to fetch messages: ${error.message}` }));
        }
         // NOTE: We DO NOT destroy the client here anymore
    }
    // --- Not Found ---
    else {
        // console.log(`[HTTP Server] Route not found: ${method} ${requestUrl.pathname}`); // Remove internal log
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not Found' }));
    }
});

// --- WebSocket Server Logic ---
const wss = new WebSocketServer({ server }); // Attach WebSocket server to HTTP server

wss.on('connection', (ws, req) => {
    // Log IP address if available (useful for debugging connections)
    const clientIp = req.socket.remoteAddress || req.headers['x-forwarded-for']?.split(',')[0].trim();
    // console.log(`[WS Server] Client connected from IP: ${clientIp || 'unknown'}`); // Remove internal log
    let clientVmUser = null; // Keep track of the user for this connection

    ws.on('message', (message) => {
        // console.log(`[WS Server] Received raw message: ${message.toString()}`); // Remove internal log
        try {
            const parsedMessage = JSON.parse(message.toString());
            // console.log('[WS Server] Parsed message:', parsedMessage); // Remove internal log

            // Handle registration message from client
            if (parsedMessage.type === 'register' && parsedMessage.vm_user) {
                clientVmUser = parsedMessage.vm_user;
                // Store the WebSocket connection associated with the user
                // console.log(`[WS Server] Registering user: ${clientVmUser}`); // Remove internal log
                wsClients.set(clientVmUser, ws);
                console.log(`WebSocket client registered for user: ${clientVmUser}. Total clients: ${wsClients.size}`); // Keep registration confirmation

                // Set up close/error handlers specific to this registered client
                ws.on('close', () => {
                    // console.log(`[WS Server] WebSocket client disconnected for user: ${clientVmUser}`); // Remove internal log
                    // Only remove if it's still the current connection for this user
                    if (wsClients.get(clientVmUser) === ws) {
                        wsClients.delete(clientVmUser);
                        console.log(`WebSocket client mapping removed for ${clientVmUser}. Total clients: ${wsClients.size}`); // Keep removal confirmation
                    }
                 }); // <-- Correctly close the 'close' handler here

                 ws.on('error', (error) => { // <-- Start the 'error' handler
                    console.error(`WebSocket error for user ${clientVmUser || 'unknown'}:`, error); // Keep important errors
                     // Ensure cleanup on error too
                     if (clientVmUser && wsClients.get(clientVmUser) === ws) {
                         wsClients.delete(clientVmUser);
                         console.log(`WebSocket client mapping removed for ${clientVmUser} due to error. Total clients: ${wsClients.size}`); // Keep removal confirmation
                     }
                 });

            } else {
                console.log('Received unhandled WebSocket message type or format:', parsedMessage); // Keep log for unexpected messages
            }
        } catch (e) {
            console.warn('Received non-JSON WebSocket message or parse error:', message.toString(), e); // Keep important warnings
        }
    });

     // Initial close/error handlers for unregistered clients
     if (!clientVmUser) {
         ws.on('close', () => console.log('Unregistered WebSocket client disconnected')); // Keep this log
         ws.on('error', (error) => console.error('Unregistered WebSocket client error:', error)); // Keep this error
     }
});

// console.log("[WS Server] WebSocket server initialized."); // Remove internal log

// --- Server Startup ---
server.listen(PORT, async () => {
    console.log(`Host service HTTP/WebSocket server listening on port ${PORT}`);
    await initializeBots(); // Login bots after server starts listening
    console.log("Service ready.");
});

// --- Graceful Shutdown ---
process.on('SIGINT', async () => {
    console.log("\nSIGINT received. Shutting down...");
    // Close WebSocket connections
    console.log("Closing WebSocket connections...");
    wsClients.forEach((ws) => {
        ws.close();
    });
    wss.close(); // Close the WebSocket server itself

    // Logout Discord bots
    console.log("Logging out Discord bots...");
    for (const [vmUser, client] of discordClients.entries()) {
        console.log(`Destroying client for ${vmUser}...`);
        await client.destroy();
    }
    discordClients.clear();

    // Close HTTP server
    console.log("Closing HTTP server...");
    server.close(() => {
        console.log("HTTP Server closed.");
        process.exit(0);
    });

    // Force exit after a timeout if server doesn't close
    setTimeout(() => {
        console.error("Shutdown timed out. Forcing exit.");
        process.exit(1);
    }, 5000); // 5 second timeout
});
