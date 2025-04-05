#!/usr/bin/env node

// vm_cli/devchat.js
import http from 'http';
import https from 'https'; // Needed if host service uses HTTPS later

// --- Configuration ---
// Default host IP as seen from VirtualBox NAT network. Make configurable if needed.
const HOST_SERVICE_IP = process.env.DEVCHAT_HOST_IP || '10.0.2.2';
const HOST_SERVICE_PORT = process.env.DEVCHAT_HOST_PORT || 3000;
const HOST_SERVICE_PROTOCOL = process.env.DEVCHAT_HOST_PROTOCOL || 'http'; // 'http' or 'https'
// --- End Configuration ---

const args = process.argv.slice(2); // Remove 'node' and script path
const command = args[0];
const vmUser = process.env.USER || process.env.DEV_USER || 'unknown_vm_user'; // Get username from VM env

if (!vmUser || vmUser === 'unknown_vm_user') {
    console.error("Error: Could not determine the VM username from $USER or $DEV_USER environment variables.");
    process.exit(1);
}

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
                    // Attempt to parse JSON, but handle plain text too
                    let parsedData;
                    try {
                        parsedData = JSON.parse(data);
                    } catch (e) {
                        parsedData = data; // Keep as string if not JSON
                    }

                    if (res.statusCode >= 200 && res.statusCode < 300) {
                        resolve(parsedData);
                    } else {
                        // Include status code and body in error
                        const error = new Error(`Request failed with status ${res.statusCode}`);
                        error.statusCode = res.statusCode;
                        error.body = parsedData;
                        reject(error);
                    }
                } catch (e) {
                     // Error during response processing
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

// --- Command Handling ---

async function run() {
    if (command === 'send' && args.length >= 3) {
        const target = args[1];
        const message = args.slice(2).join(' '); // Join remaining args as message

        const postData = JSON.stringify({
            vm_user: vmUser,
            target: target,
            message: message
        });

        const options = {
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
            const response = await makeRequest(options, postData);
            console.log("Server response:", response.message || response); // Display success message or full response
        } catch (error) {
            console.error(`Error sending message: ${error.message}`);
             if (error.body) {
                 console.error("Server Error Body:", JSON.stringify(error.body, null, 2));
             }
            process.exit(1);
        }

    } else if (command === 'receive') {
        const options = {
            hostname: HOST_SERVICE_IP,
            port: HOST_SERVICE_PORT,
            path: `/messages/${encodeURIComponent(vmUser)}`,
            method: 'GET',
            protocol: `${HOST_SERVICE_PROTOCOL}:`,
        };

        try {
            console.log(`Checking for messages for ${vmUser}...`);
            const messages = await makeRequest(options);

            if (Array.isArray(messages) && messages.length > 0) {
                console.log("\n--- New Messages ---");
                messages.forEach(msg => {
                    const date = new Date(msg.timestamp).toLocaleString();
                    console.log(`[${date}] From ${msg.author}: ${msg.content}`);
                });
                console.log("--------------------\n");
            } else if (Array.isArray(messages)) {
                console.log("No new messages.");
            } else {
                 console.log("Received unexpected response:", messages);
            }
        } catch (error) {
            console.error(`Error receiving messages: ${error.message}`);
             if (error.body) {
                 console.error("Server Error Body:", JSON.stringify(error.body, null, 2));
             }
            process.exit(1);
        }

    } else {
        console.log("Usage:");
        console.log("  devchat send <target> <message>   (Target can be @admin or Discord User ID)");
        console.log("  devchat receive");
        process.exit(1);
    }
}

run();
