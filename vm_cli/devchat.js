#!/usr/bin/env node

import http from 'http';
import https from 'https'; // Keep for potential future HTTPS use
import WebSocket from 'ws'; // Import WebSocket

// --- Configuration ---
// Default to localhost for host testing. Set DEVCHAT_HOST_IP=10.0.2.2 inside the VM.
const HOST_SERVICE_IP = process.env.DEVCHAT_HOST_IP || 'localhost';
const HOST_SERVICE_PORT = process.env.DEVCHAT_HOST_PORT || 3000;
const HOST_SERVICE_PROTOCOL = process.env.DEVCHAT_HOST_PROTOCOL || 'http'; // 'http' or 'https'
const WS_PROTOCOL = HOST_SERVICE_PROTOCOL === 'https' ? 'wss' : 'ws';
const WS_URL = `${WS_PROTOCOL}://${HOST_SERVICE_IP}:${HOST_SERVICE_PORT}`;
const REPLY_TIMEOUT_MS = 1800000; // 30 minutes (1800 * 1000) timeout for waiting for reply notification
// --- End Configuration ---

const args = process.argv.slice(2); // Remove 'node' and script path
const target = args[0];
const message = args.slice(1).join(' '); // Join remaining args as message
const vmUser = process.env.USER || process.env.DEV_USER || 'unknown_vm_user'; // Get username from VM env

if (!vmUser || vmUser === 'unknown_vm_user') {
    console.error("Error: Could not determine the VM username from $USER or $DEV_USER environment variables.");
    process.exit(1);
}

if (!target || !message) {
    console.log("Usage:");
    console.log("  devchat <target> <message>");
    console.log("  (Target can be @admin or Discord User ID)");
    process.exit(1);
}

// --- HTTP Request Helper (Unchanged) ---
const makeRequest = (options, postData = null) => {
    return new Promise((resolve, reject) => {
        const protocol = options.protocol === 'https:' ? https : http;
        const req = protocol.request(options, (res) => {
            let data = '';
            res.on('data', (chunk) => {
                data += chunk;
            });
            res.on('end', () => {
                try {
                    let parsedData;
                    try {
                        parsedData = JSON.parse(data);
                    } catch (e) {
                        parsedData = data;
                    }

                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(parsedData);
                    } else {
                        const error = new Error(`Request failed with status ${res.statusCode}`);
                        error.statusCode = res.statusCode;
                        error.body = parsedData;
                        reject(error);
                    }
                } catch (e) {
                     reject(new Error(`Error processing response: ${e.message}`));
                }
            });
        });

        req.on('error', (e) => {
            reject(new Error(`Request error: ${e.message}`));
        });

        if (postData) {
            req.write(postData);
        }
        req.end();
    });
};

// --- Fetch Messages Function (from old 'receive') ---
async function fetchMessages(user) {
     const options = {
        hostname: HOST_SERVICE_IP,
        port: HOST_SERVICE_PORT,
        path: `/messages/${encodeURIComponent(user)}`,
        method: 'GET',
        protocol: `${HOST_SERVICE_PROTOCOL}:`,
    };
    console.log(`\nFetching reply for ${user}...`);
    const messages = await makeRequest(options);

    if (Array.isArray(messages) && messages.length > 0) {
        console.log("\n--- Reply Received ---");
        // Assuming the most recent message is the reply we are waiting for
        const msg = messages[messages.length - 1];
        const date = new Date(msg.timestamp).toLocaleString();
        console.log(`[${date}] From ${msg.author}: ${msg.content}`);
        console.log("--------------------\n");
    } else if (Array.isArray(messages)) {
        console.log("No new messages found (unexpected after notification).");
    } else {
         console.log("Received unexpected response when fetching messages:", messages);
    }
}


// --- Main Logic ---
async function run() {
    // 1. Send the message via HTTP POST
    const postData = JSON.stringify({
        vm_user: vmUser,
        target: target,
        message: message
    });
    const postOptions = {
        hostname: HOST_SERVICE_IP,
        port: HOST_SERVICE_PORT,
        path: '/message',
        method: 'POST',
        protocol: `${HOST_SERVICE_PROTOCOL}:`,
        headers: {
            'Content-Type': 'application/json',
            'Content-Length': Buffer.byteLength(postData)
        }
    };

    try {
        console.log(`Sending message as ${vmUser} to ${target}...`);
        const response = await makeRequest(postOptions, postData);
        console.log("Send confirmation:", response.message || response); // Keep confirmation
    } catch (error) {
        console.error(`Error sending message: ${error.message}`);
         if (error.body) {
             console.error("Server Error Body:", JSON.stringify(error.body, null, 2));
         }
        process.exit(1);
    }

    // 2. Connect WebSocket and wait for reply notification
    // Keep this log as it indicates the waiting phase
    console.log(`\nWaiting for reply notification... (Timeout: ${REPLY_TIMEOUT_MS / 1000 / 60} minutes)`);
    const ws = new WebSocket(WS_URL);
    let replyReceived = false;
    let timeoutId;

    const cleanupAndExit = (exitCode = 0) => {
        clearTimeout(timeoutId);
        if (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING) {
            ws.close();
        }
        process.exit(exitCode);
    };

    ws.on('open', () => {
        // console.log('[CLI WS] WebSocket connection established.'); // Remove internal log
        // Send registration message to server
        try {
            const registrationMsg = JSON.stringify({ type: 'register', vm_user: vmUser });
            // console.log(`[CLI WS] Sending registration: ${registrationMsg}`); // Remove internal log
            ws.send(registrationMsg);
            // console.log('[CLI WS] Registration message sent.'); // Remove internal log
        } catch (e) {
             console.error('[CLI WS] Error sending registration:', e);
             cleanupAndExit(1);
             return;
        }

        // Set timeout after connection is open
        // console.log('[CLI WS] Setting reply timeout...'); // Remove internal log
        timeoutId = setTimeout(() => {
            if (!replyReceived) {
                console.error('\nError: Timed out waiting for reply notification.');
                cleanupAndExit(1);
            }
        }, REPLY_TIMEOUT_MS);
    });

    ws.on('message', async (data) => {
        try {
            // console.log('[CLI WS] Received WebSocket message data:', data.toString()); // Remove internal log
            const wsMessage = JSON.parse(data.toString());
            // console.log('[CLI WS] Parsed WebSocket message:', wsMessage); // Remove internal log

            // Check if it's the notification we expect
            if (wsMessage.type === 'reply_notification' && wsMessage.recipient === vmUser) {
                // console.log('[CLI WS] Correct reply notification received!'); // Remove internal log
                replyReceived = true;
                clearTimeout(timeoutId); // Clear timeout as we got the notification
                ws.close(); // Close the WebSocket connection

                // 3. Fetch the actual reply message via HTTP GET
                try {
                    await fetchMessages(vmUser);
                    cleanupAndExit(0); // Success
                } catch (fetchError) {
                    console.error(`Error fetching reply message: ${fetchError.message}`);
                    if (fetchError.body) {
                        console.error("Server Error Body:", JSON.stringify(fetchError.body, null, 2));
                    }
                    cleanupAndExit(1); // Exit with error after fetch failure
                }
            }
        } catch (e) {
            // Keep this warning, it's useful if the server sends bad data
            console.warn('Received non-JSON WebSocket message or parse error:', data.toString());
        }
    });

    ws.on('error', (error) => {
        // Keep this error message
        console.error(`WebSocket error: ${error.message}`, error);
        cleanupAndExit(1);
    });

    ws.on('close', (code, reason) => {
        // Keep this log, indicates connection closure
        console.log(`WebSocket connection closed. Code: ${code}, Reason: ${reason ? reason.toString() : 'N/A'}`);
        // If the connection closed *before* we received the reply, it's an error (unless timeout handled it)
        if (!replyReceived) {
             // Avoid double exit if timeout already triggered
            if (timeoutId) { // Check if timeout is still pending
                 clearTimeout(timeoutId);
                 console.error('WebSocket closed unexpectedly before reply notification was received.');
                 process.exit(1); // Use process.exit directly as cleanupAndExit might try to close again
            }
        }
        // If replyReceived is true, the 'message' handler already called cleanupAndExit
    });
}

run();
