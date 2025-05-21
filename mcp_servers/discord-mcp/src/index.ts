import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CreateMessageResultSchema } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { Client, GatewayIntentBits, Message } from 'discord.js';

const discordClient = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
});

// Schema for send-message tool parameters
const SendMessageParamsSchema = z.object({
  channel: z.string(),
  message: z.string(),
});
// Infer type for send-message tool parameters
type SendMessageParams = z.infer<typeof SendMessageParamsSchema>;

// Schema for the 'send-message' method itself
const SendMessageMethodSchema = z.object({
  method: z.literal('send-message'),
  params: SendMessageParamsSchema,
  // id: z.union([z.string(), z.number(), z.null()]).optional() // MCP requests usually have an ID, handled by ServerRequest type
});
type SendMessageRequest = z.infer<typeof SendMessageMethodSchema>;

// Infer the type for the result of sampling/createMessage
type SamplingResult = z.infer<typeof CreateMessageResultSchema>; // This is the result part of the response

// Define a more specific type for the content we expect in sampling/createMessage's result
interface ExpectedTextContent {
  type: 'text';
  text: string;
}

// This represents the expected structure of the 'result' field within the SamplingResult
interface ExpectedSamplingResult {
  content?: ExpectedTextContent;
}

const serverInfo = { name: "discord-mcp-ts-server", version: "1.0.0" };

// Removed onTransportError from Server constructor options
const rpc = new McpServer(serverInfo);
const serverTransport = new StdioServerTransport(process.stdin, process.stdout);

// Transport specific error handling (if available, consult SDK docs for StdioServerTransport)
// For now, relying on onclose and global handlers. Add specific error event if found.
// transport.on('error', (err: Error) => { console.error('MCP Transport Error:', err); });

async function initializeServer() {
  try {
    await rpc.connect(serverTransport);

    console.error("MCP Server connected.");
  } catch (error) {
    console.error('Failed to connect or start MCP transport:', error);
    process.exit(1);
  }
}

// ---------- “pull” tool: Claude ➜ Discord ----------
/* ---- registration ---- */
rpc.tool(
  "discord_send_message",
  {                         // params shape
    channel: z.string(),
    message: z.string()
  },
  async ({ channel, message }) => {     // handler becomes 4th arg
    try {
      console.error("discord_send_message called:", channel, message); // <— visible in MCP stderr
      // 1) guild / thread / cached DM
      const ch = await discordClient.channels.fetch(channel).catch(() => null);
      if (ch && ch.isTextBased()) {
        await (ch as any).send(message);
        return {
          content: [{ type: "text", text: "✅ Message sent" }]
        };
      }
  
      // 2) treat as USER ID → DM
      const user = await discordClient.users.fetch(channel);
      const dm   = await user.createDM();
      await dm.send(message);
      return { content: [{ type: "text", text: "✅ DM sent" }] };
    } catch (err) {
      console.error("discord_send_message error:", err);       // <— visible in MCP stderr
      return {
        content: [{
          type: "text",
          text: `❌ ${ (err as Error).message }`
        }],
        isError: true
      };
    }
  }  
);

/* -------- 2. “push” handler: Discord -> Claude ------ */
discordClient.on('messageCreate', async (msg: Message) => {
  if (msg.author.bot) return;

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

    const response = await rpc.server.request(
      { method: "sampling/createMessage", params: requestParams },
      CreateMessageResultSchema
    );

    const result = response as ExpectedSamplingResult;

    if (result && result.content && typeof result.content.text === 'string') {
      await msg.reply(result.content.text);
    } else {
      console.error('Invalid response structure from sampling/createMessage:', result);
      await msg.reply("Sorry, I encountered an issue processing that request.");
    }
  } catch (error) {
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
