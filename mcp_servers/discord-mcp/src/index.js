import { Server } from '@modelcontextprotocol/sdk/server/index.js';
import { StdioServerTransport } from '@modelcontextprotocol/sdk/server/stdio.js';
import { Client, GatewayIntentBits, TextChannel, DMChannel, NewsChannel } from 'discord.js';

const discord = new Client({
  intents: [
    GatewayIntentBits.Guilds,
    GatewayIntentBits.GuildMessages,
    GatewayIntentBits.MessageContent,
  ],
});

async function main() {
  const rpc = new Server({ name: "discord-mcp-server", version: "1.0.0" });
  const transport = new StdioServerTransport(process.stdin, process.stdout);

  try {
    await rpc.connect(transport);
    console.log('MCP Server connected and transport started.');
  } catch (error) {
    console.error('Failed to connect or start MCP transport:', error);
    process.exit(1);
  }

  /* -------- 1. “pull” tool: Claude -> Discord -------- */
  rpc.registerTool('send-message', async ({ channel, message }) => {
    try {
      const ch = await discord.channels.fetch(channel);
      if (ch) {
        if (ch instanceof TextChannel || ch instanceof DMChannel || ch instanceof NewsChannel) {
          await ch.send(message);
        } else if (ch.isTextBased && typeof ch.send === 'function') {
          await ch.send(message);
        } else {
          console.warn(`Channel ${channel} (ID: ${ch.id}) is not a recognized text-based channel type with a send method.`);
        }
      } else {
        console.warn(`Channel ${channel} not found.`);
      }
    } catch (error) {
      console.error(`Error fetching channel ${channel} or sending message:`, error);
    }
  });

  /* -------- 2. “push” handler: Discord -> Claude ------ */
  discord.on('messageCreate', async (msg) => {
    if (msg.author.bot) return; // ignore self & other bots

    try {
      const { result } = await rpc.request('sampling/createMessage', {
        messages: [{
          role: 'user',
          content: { type: 'text', text: `[${msg.author.username}] ${msg.content}` },
        }],
        systemPrompt: 'You are a helpful bot inside this Discord channel.',
        includeContext: 'thisServer',
        maxTokens: 400,
      });

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

  discord.login(token)
    .then(() => console.log('Discord MCP (JS) ready'))
    .catch(error => {
      console.error('Failed to login to Discord:', error);
      process.exit(1);
    });

  // Basic error handling for the RPC server itself (from Protocol class)
  rpc.onTransportError = (err) => { // Server itself doesn't have 'on' directly, transport errors are handled via onTransportError
    console.error('MCP Transport Error:', err);
  };

  // Handle transport closure
  transport.onclose = () => {
    console.log('MCP transport closed.');
  };
}

process.on('unhandledRejection', (reason, promise) => {
  console.error('Unhandled Rejection at:', promise, 'reason:', reason);
});
process.on('uncaughtException', (error) => {
  console.error('Uncaught Exception:', error);
  process.exit(1); // Consider exiting on uncaught exceptions
});

main().catch(error => {
  console.error("Error during main execution:", error);
  process.exit(1);
});
