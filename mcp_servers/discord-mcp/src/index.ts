import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { CreateMessageResultSchema, InitializeRequestSchema, type ServerRequest } from '@modelcontextprotocol/sdk/types.js';
import { z } from 'zod';
import { Client, GatewayIntentBits, TextChannel, DMChannel, NewsChannel, Message } from 'discord.js';

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
const rpc = new Server(serverInfo);
const transport = new StdioServerTransport(process.stdin, process.stdout);

// Transport specific error handling (if available, consult SDK docs for StdioServerTransport)
// For now, relying on onclose and global handlers. Add specific error event if found.
// transport.on('error', (err: Error) => { console.error('MCP Transport Error:', err); });

async function initializeServer() {
  try {
    await rpc.connect(transport);
    console.log('MCP Server connected and transport started.');
  } catch (error) {
    console.error('Failed to connect or start MCP transport:', error);
    process.exit(1);
  }
}

/* -------- 1. “pull” tool: Claude -> Discord -------- */
rpc.setRequestHandler(
  SendMessageMethodSchema, // Use the new schema for the method
  async (request: SendMessageRequest) => { // request is now typed by SendMessageMethodSchema
    // No need to parse request.params manually if the SDK handles it based on the schema
    const { channel, message } = request.params; 
    try {
      const ch = await discordClient.channels.fetch(channel);
      if (ch) {
        if (ch instanceof TextChannel || ch instanceof DMChannel || ch instanceof NewsChannel) {
          await ch.send(message);
        } else if (ch.isTextBased() && typeof (ch as any).send === 'function') {
          await (ch as any).send(message);
        } else {
          console.warn(`Channel ${channel} (ID: ${ch.id}) is not a recognized text-based channel type with a send method.`);
        }
      } else {
        console.warn(`Channel ${channel} not found.`);
      }
      return { success: true }; 
    } catch (error) {
      console.error(`Error in send-message handler:`, error);
      const errorMessage = (error as Error).message;
      return { success: false, error: errorMessage }; // Simplified error response
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

    // Corrected rpc.request call
    const response = await rpc.request(
      { method: 'sampling/createMessage', params: requestParams }, 
      CreateMessageResultSchema
    );

    // 'response' is now typed as SamplingResult (which is z.infer<typeof CreateMessageResultSchema>)
    // This type directly represents the 'result' field of an MCP response.
    const result = response as ExpectedSamplingResult; // Cast to our more specific expected structure for content

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
    .then(() => console.log('Discord MCP (TypeScript with SDK) ready'))
    .catch(error => {
      console.error('Failed to login to Discord:', error);
      process.exit(1); 
    });

  transport.onclose = () => {
    console.log('MCP transport closed.');
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
