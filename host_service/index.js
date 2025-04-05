import http from 'http';
import { Client, GatewayIntentBits, Partials, ChannelType } from 'discord.js';
import { URL } from 'url'; // Use URL module for parsing
import dotenv from 'dotenv';
import path from 'path';
import { fileURLToPath } from 'url';

// Get the directory name of the current module
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// Load environment variables from .env file located in the same directory as the script
dotenv.config({ path: path.resolve(__dirname, '.env') });


// --- Configuration ---
const PORT = 3000; // Port for the HTTP server
const ADMIN_DISCORD_ID = process.env.ADMIN_DISCORD_ID; // Your Discord User ID from env
const MAX_MESSAGES_FETCH = 10; // Max messages to fetch when checking DMs

if (!ADMIN_DISCORD_ID) {
    console.error("Error: ADMIN_DISCORD_ID environment variable is not set.");
    process.exit(1);
}

// In-memory store for last checked message timestamp per user (simple approach)
// Key: vm_user, Value: timestamp of the last message fetched for them
const lastMessageTimestamps = {};

// --- Helper Functions ---

// Gets the bot token for a specific VM user from environment variables
function getBotToken(vmUser) {
    const token = process.env[`BOT_TOKEN_${vmUser}`];
    if (!token) {
        console.error(`Error: Bot token not found for user ${vmUser}. Set BOT_TOKEN_${vmUser} environment variable.`);
    }
    return token;
}

// Creates and logs in a Discord client instance for a specific token
async function loginBot(token) {
    if (!token) return null;

    const client = new Client({
        intents: [
            GatewayIntentBits.Guilds, // Needed for user fetching?
            GatewayIntentBits.DirectMessages,
            GatewayIntentBits.MessageContent // Needed to read DM content
        ],
        partials: [Partials.Channel], // Required to receive DMs
    });

    return new Promise((resolve, reject) => {
        client.once('ready', () => {
            console.log(`Logged in as ${client.user.tag} (temporary client)`);
            resolve(client);
        });
        client.once('error', (err) => {
             console.error(`Login error for token associated with client: ${err.message}`);
             reject(err); // Reject promise on login error
        });

        client.login(token).catch(err => {
            console.error(`Failed to login with token: ${err.message}`);
            // Ensure client resources are cleaned up if login fails immediately
             client.destroy();
             reject(err); // Reject promise if login throws
        });
    });
}

// --- HTTP Server Logic ---

const server = http.createServer(async (req, res) => {
    const requestUrl = new URL(req.url, `http://${req.headers.host}`);
    const { method, url } = req;
    const pathParts = requestUrl.pathname.split('/').filter(part => part); // Split path and remove empty parts

    console.log(`Received ${method} request for ${requestUrl.pathname}`);

    // --- Send Message Endpoint ---
    if (method === 'POST' && pathParts[0] === 'message') {
        let body = '';
        req.on('data', chunk => {
            body += chunk.toString();
        });
        req.on('end', async () => {
            try {
                const { vm_user, target, message } = JSON.parse(body);

                if (!vm_user || !target || !message) {
                    res.writeHead(400, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: 'Missing vm_user, target, or message in request body' }));
                    return;
                }

                // --- Target Handling (Simplified: Only Admin DM for now) ---
                // In a future version, parse target for @user or #channel
                let targetUserId = null;
                if (target.startsWith('@') && target.toLowerCase() === '@admin') { // Assuming a convention
                     targetUserId = ADMIN_DISCORD_ID;
                } else if (/^\d+$/.test(target)) { // Allow sending directly via ID
                     targetUserId = target;
                }
                 else {
                    // Basic check if target is the admin's ID directly
                    if (target === ADMIN_DISCORD_ID) {
                         targetUserId = ADMIN_DISCORD_ID;
                    } else {
                         console.warn(`Target '${target}' is not recognized as admin or direct ID. Sending to Admin ID as default.`);
                         targetUserId = ADMIN_DISCORD_ID; // Default to admin for now
                         // TODO: Add channel support later if needed
                    }
                }


                const token = getBotToken(vm_user);
                if (!token) {
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: `Bot token not configured for user ${vm_user}` }));
                    return;
                }

                let discordClient = null;
                try {
                    console.log(`Attempting to log in bot for ${vm_user} to send message...`);
                    discordClient = await loginBot(token);
                    if (!discordClient) throw new Error("Failed to initialize Discord client.");


                    const targetUser = await discordClient.users.fetch(targetUserId);
                    if (!targetUser) {
                        throw new Error(`Could not find target user with ID ${targetUserId}`);
                    }

                    await targetUser.send(`[${vm_user}]: ${message}`);
                    console.log(`Message sent successfully from ${vm_user} to ${targetUser.tag}`);

                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, message: 'Message sent' }));

                } catch (error) {
                    console.error(`Error sending message for ${vm_user}:`, error);
                    res.writeHead(500, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ error: `Failed to send message: ${error.message}` }));
                } finally {
                    if (discordClient) {
                        console.log(`Logging out bot for ${vm_user} after sending.`);
                        discordClient.destroy(); // Logout after use
                    }
                }

            } catch (e) {
                console.error("Error processing POST /message:", e);
                res.writeHead(400, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ error: 'Invalid JSON body or processing error' }));
            }
        });
    }
    // --- Receive Messages Endpoint ---
    else if (method === 'GET' && pathParts[0] === 'messages' && pathParts[1]) {
        const vm_user = decodeURIComponent(pathParts[1]);
        const token = getBotToken(vm_user);

        if (!token) {
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: `Bot token not configured for user ${vm_user}` }));
            return;
        }

        let discordClient = null;
        try {
            console.log(`Attempting to log in bot for ${vm_user} to receive messages...`);
            discordClient = await loginBot(token);
             if (!discordClient) throw new Error("Failed to initialize Discord client.");

            // Fetch the DM channel between the Admin and this specific Bot
            const adminUser = await discordClient.users.fetch(ADMIN_DISCORD_ID);
            if (!adminUser) {
                 throw new Error(`Could not fetch admin user profile (ID: ${ADMIN_DISCORD_ID})`);
            }

            const dmChannel = await adminUser.createDM(); // Get DM channel with the bot
             if (!dmChannel || dmChannel.type !== ChannelType.DM) {
                 throw new Error(`Could not establish DM channel with admin user.`);
             }


            // Fetch message history
            // Fetch only messages *after* the last timestamp we recorded for this user
            const fetchOptions = { limit: MAX_MESSAGES_FETCH };
            const lastTimestamp = lastMessageTimestamps[vm_user];
            if (lastTimestamp) {
                // Fetch messages *after* the snowflake derived from the timestamp
                // Note: Discord uses Snowflakes which incorporate timestamps.
                // A simple timestamp comparison might miss messages sent in the same millisecond.
                // Fetching slightly more and filtering client-side is safer.
                // Let's fetch last N and filter by timestamp > lastTimestamp for simplicity here.
                 console.log(`Fetching messages for ${vm_user} after timestamp: ${new Date(lastTimestamp).toISOString()}`);
            } else {
                 console.log(`Fetching initial messages for ${vm_user}`);
            }


            const messages = await dmChannel.messages.fetch(fetchOptions);

            // Filter messages: only those sent BY the admin USER, and newer than last check
            const newMessages = messages
                .filter(msg => msg.author.id === ADMIN_DISCORD_ID && (!lastTimestamp || msg.createdTimestamp > lastTimestamp))
                .map(msg => ({
                    timestamp: msg.createdTimestamp,
                    author: msg.author.tag, // Should always be the admin
                    content: msg.content
                }))
                .sort((a, b) => a.timestamp - b.timestamp); // Ensure chronological order

            // Update the last message timestamp for this user
            if (newMessages.length > 0) {
                lastMessageTimestamps[vm_user] = newMessages[newMessages.length - 1].timestamp;
                 console.log(`Updated last timestamp for ${vm_user} to ${new Date(lastMessageTimestamps[vm_user]).toISOString()}`);
            } else if (!lastTimestamp && messages.size > 0) {
                 // If no *new* messages but messages exist, set timestamp to the latest fetched admin message
                 const latestAdminMsg = messages
                     .filter(msg => msg.author.id === ADMIN_DISCORD_ID)
                     .sort((a, b) => b.createdTimestamp - a.createdTimestamp) // Sort descending
                     .first(); // Get the latest
                 if (latestAdminMsg) {
                     lastMessageTimestamps[vm_user] = latestAdminMsg.createdTimestamp;
                     console.log(`Set initial timestamp for ${vm_user} to ${new Date(lastMessageTimestamps[vm_user]).toISOString()}`);
                 }
            }


            console.log(`Found ${newMessages.length} new messages for ${vm_user}`);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify(newMessages));

        } catch (error) {
            console.error(`Error fetching messages for ${vm_user}:`, error);
            res.writeHead(500, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ error: `Failed to fetch messages: ${error.message}` }));
        } finally {
            if (discordClient) {
                 console.log(`Logging out bot for ${vm_user} after receiving.`);
                discordClient.destroy(); // Logout after use
            }
        }
    }
    // --- Not Found ---
    else {
        res.writeHead(404, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify({ error: 'Not Found' }));
    }
});

server.listen(PORT, () => {
    console.log(`Host service listening on port ${PORT}`);
    console.log(`Ensure ADMIN_DISCORD_ID and BOT_TOKEN_<username> environment variables are set.`);
});

process.on('SIGINT', () => {
    console.log("Shutting down server...");
    server.close(() => {
        console.log("Server closed.");
        process.exit(0);
    });
});
