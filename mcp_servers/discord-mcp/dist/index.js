"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
const mcp_js_1 = require("@modelcontextprotocol/sdk/server/mcp.js");
const stdio_js_1 = require("@modelcontextprotocol/sdk/server/stdio.js");
const types_js_1 = require("@modelcontextprotocol/sdk/types.js");
const zod_1 = require("zod");
const discord_js_1 = require("discord.js");
const discordClient = new discord_js_1.Client({
    intents: [
        discord_js_1.GatewayIntentBits.Guilds,
        discord_js_1.GatewayIntentBits.GuildMessages,
        discord_js_1.GatewayIntentBits.MessageContent,
    ],
});
// Schema for send-message tool parameters
const SendMessageParamsSchema = zod_1.z.object({
    channel: zod_1.z.string(),
    message: zod_1.z.string(),
});
// Schema for the 'send-message' method itself
const SendMessageMethodSchema = zod_1.z.object({
    method: zod_1.z.literal('send-message'),
    params: SendMessageParamsSchema,
    // id: z.union([z.string(), z.number(), z.null()]).optional() // MCP requests usually have an ID, handled by ServerRequest type
});
const serverInfo = { name: "discord-mcp-ts-server", version: "1.0.0" };
// Removed onTransportError from Server constructor options
const rpc = new mcp_js_1.McpServer(serverInfo);
const serverTransport = new stdio_js_1.StdioServerTransport(process.stdin, process.stdout);
// Transport specific error handling (if available, consult SDK docs for StdioServerTransport)
// For now, relying on onclose and global handlers. Add specific error event if found.
// transport.on('error', (err: Error) => { console.error('MCP Transport Error:', err); });
async function initializeServer() {
    try {
        await rpc.connect(serverTransport);
        console.error("MCP Server connected.");
    }
    catch (error) {
        console.error('Failed to connect or start MCP transport:', error);
        process.exit(1);
    }
}
// ---------- “pull” tool: Claude ➜ Discord ----------
/* ---- registration ---- */
rpc.tool("discord_send_message", {
    channel: zod_1.z.string(),
    message: zod_1.z.string()
}, async ({ channel, message }) => {
    try {
        console.error("discord_send_message called:", channel, message); // <— visible in MCP stderr
        // 1) guild / thread / cached DM
        const ch = await discordClient.channels.fetch(channel).catch(() => null);
        if (ch && ch.isTextBased()) {
            await ch.send(message);
            return {
                content: [{ type: "text", text: "✅ Message sent" }]
            };
        }
        // 2) treat as USER ID → DM
        const user = await discordClient.users.fetch(channel);
        const dm = await user.createDM();
        await dm.send(message);
        return { content: [{ type: "text", text: "✅ DM sent" }] };
    }
    catch (err) {
        console.error("discord_send_message error:", err); // <— visible in MCP stderr
        return {
            content: [{
                    type: "text",
                    text: `❌ ${err.message}`
                }],
            isError: true
        };
    }
});
/* -------- 2. “push” handler: Discord -> Claude ------ */
discordClient.on('messageCreate', async (msg) => {
    if (msg.author.bot)
        return;
    try {
        const requestParams = {
            messages: [{
                    role: 'user',
                    content: { type: 'text', text: `[${msg.author.username}] ${msg.content}` },
                }],
            systemPrompt: 'You are a helpful bot inside this Discord channel.',
            includeContext: 'thisServer',
            maxTokens: 400,
        };
        const response = await rpc.server.request({ method: "sampling/createMessage", params: requestParams }, types_js_1.CreateMessageResultSchema);
        const result = response;
        if (result && result.content && typeof result.content.text === 'string') {
            await msg.reply(result.content.text);
        }
        else {
            console.error('Invalid response structure from sampling/createMessage:', result);
            await msg.reply("Sorry, I encountered an issue processing that request.");
        }
    }
    catch (error) {
        console.error('Error in messageCreate handler or rpc.request:', error);
    }
});
/* --------------------------------------------------- */
const token = process.env.DISCORD_BOT_TOKEN;
if (!token) {
    console.error('Error: DISCORD_BOT_TOKEN environment variable is not set.');
    process.exit(1);
}
async function main() {
    await initializeServer();
    discordClient.login(token)
        .then(() => console.error('Discord MCP (TypeScript with SDK) ready'))
        .catch(error => {
        console.error('Failed to login to Discord:', error);
        process.exit(1);
    });
    serverTransport.onclose = () => {
        console.error('MCP transport closed.');
    };
}
process.on('unhandledRejection', (reason, promise) => {
    console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
process.on('uncaughtException', (error) => {
    console.error('Uncaught Exception:', error);
    process.exit(1);
});
main().catch(error => {
    console.error("Error during main execution:", error);
    process.exit(1);
});
