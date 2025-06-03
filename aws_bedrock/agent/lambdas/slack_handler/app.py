import json
import os
import boto3
import hmac
import hashlib
import time
import re
import logging
from slack_sdk import WebClient
from slack_sdk.errors import SlackApiError

# Configure logging
logger = logging.getLogger()
logger.setLevel(logging.INFO)

# Initialize AWS clients
bedrock_agent_runtime = boto3.client('bedrock-agent-runtime')
secrets_client = boto3.client('secretsmanager')

# Get environment variables
AGENT_ID = os.environ.get('AGENT_ID')
AGENT_ALIAS_ID = os.environ.get('AGENT_ALIAS_ID')
SLACK_TOKENS_SECRET = os.environ.get('SLACK_TOKENS_SECRET')

# Global variables
slack_token = None
slack_signing_secret = None
slack_app_token = None

def get_slack_tokens():
    """Get Slack tokens from AWS Secrets Manager"""
    global slack_token, slack_signing_secret, slack_app_token
    
    if slack_token and slack_signing_secret and slack_app_token:
        return
        
    try:
        response = secrets_client.get_secret_value(SecretId=SLACK_TOKENS_SECRET)
        secret_data = json.loads(response['SecretString'])
        
        slack_token = secret_data.get('SLACK_BOT_TOKEN')
        slack_signing_secret = secret_data.get('SLACK_SIGNING_SECRET')
        slack_app_token = secret_data.get('SLACK_APP_TOKEN')
        
        if not slack_token or not slack_signing_secret or not slack_app_token:
            logger.error("One or more Slack tokens are missing from the secret")
    
    except Exception as e:
        logger.error(f"Error retrieving Slack tokens: {str(e)}")

def verify_slack_request(event):
    """Verify that the request came from Slack"""
    get_slack_tokens()
    
    if not slack_signing_secret:
        logger.error("Slack signing secret not available")
        return False
        
    # Get the Slack signature and timestamp
    slack_signature = event.get('headers', {}).get('X-Slack-Signature')
    slack_request_timestamp = event.get('headers', {}).get('X-Slack-Request-Timestamp')
    
    if not slack_signature or not slack_request_timestamp:
        logger.error("Missing Slack signature or timestamp")
        return False
    
    # Check if the request timestamp is within five minutes
    current_timestamp = int(time.time())
    if abs(current_timestamp - int(slack_request_timestamp)) > 60 * 5:
        logger.error("Request timestamp is older than 5 minutes")
        return False
    
    # Recreate the signature
    body = event.get('body', '')
    base_string = f"v0:{slack_request_timestamp}:{body}"
    
    my_signature = 'v0=' + hmac.new(
        slack_signing_secret.encode('utf-8'),
        base_string.encode('utf-8'),
        hashlib.sha256
    ).hexdigest()
    
    # Compare signatures
    if hmac.compare_digest(my_signature, slack_signature):
        return True
        
    logger.error("Slack signature verification failed")
    return False

def handle_slack_event(event_data):
    """Handle Slack events and route to appropriate handler"""
    event_type = event_data.get('type')
    
    # Handle URL verification (for setting up Slack Events API)
    if event_type == 'url_verification':
        return {
            'statusCode': 200,
            'headers': {'Content-Type': 'text/plain'},
            'body': event_data.get('challenge', '')
        }
    
    # Handle events from the Events API
    if event_type == 'event_callback':
        inner_event = event_data.get('event', {})
        event_subtype = inner_event.get('type')
        
        # Handle message events
        if event_subtype == 'message':
            return handle_message_event(inner_event, event_data)
            
        # Handle app_mention events
        elif event_subtype == 'app_mention':
            return handle_app_mention_event(inner_event, event_data)
    
    return {
        'statusCode': 200,
        'body': json.dumps({'status': 'no_action'})
    }

def handle_message_event(message_event, event_data):
    """Handle direct messages to the bot"""
    # Ignore messages from bots to prevent loops
    if message_event.get('bot_id'):
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'ignored_bot_message'})
        }
    
    # Get message text and channel
    message_text = message_event.get('text', '').strip()
    channel = message_event.get('channel')
    user = message_event.get('user')
    ts = message_event.get('ts')
    
    if not message_text or not channel:
        logger.error("Missing message text or channel")
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'missing_data'})
        }
    
    # Send typing indicator
    send_typing_indicator(channel)
    
    # Process message with Bedrock Agent
    try:
        # Create a session ID based on channel and timestamp
        session_id = f"slack-{channel}-{int(time.time())}"
        
        # Add user info to the message
        full_message = f"User {user} asks: {message_text}"
        
        # Send to Bedrock Agent
        response = bedrock_agent_runtime.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=full_message
        )
        
        agent_response = response.get('completion', 'Sorry, I could not process your request.')
        
        # Reply in thread if ts is provided, otherwise send as a new message
        send_slack_message(channel, agent_response, thread_ts=ts)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'success'})
        }
        
    except Exception as e:
        logger.error(f"Error processing message with Bedrock Agent: {str(e)}")
        error_message = "Sorry, I encountered an error while processing your request."
        send_slack_message(channel, error_message, thread_ts=ts)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'error', 'message': str(e)})
        }

def handle_app_mention_event(mention_event, event_data):
    """Handle mentions of the bot in channels"""
    # Get message text and channel
    message_text = mention_event.get('text', '').strip()
    channel = mention_event.get('channel')
    user = mention_event.get('user')
    ts = mention_event.get('ts')
    
    if not message_text or not channel:
        logger.error("Missing message text or channel")
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'missing_data'})
        }
    
    # Remove bot mention from the message
    # Pattern matches <@BOT_USER_ID> or similar mention formats
    message_text = re.sub(r'<@[A-Z0-9]+>', '', message_text).strip()
    
    # Send typing indicator
    send_typing_indicator(channel)
    
    # Process message with Bedrock Agent
    try:
        # Create a session ID based on channel and timestamp
        session_id = f"slack-{channel}-{int(time.time())}"
        
        # Add user info to the message
        full_message = f"User {user} asks: {message_text}"
        
        # Send to Bedrock Agent
        response = bedrock_agent_runtime.invoke_agent(
            agentId=AGENT_ID,
            agentAliasId=AGENT_ALIAS_ID,
            sessionId=session_id,
            inputText=full_message
        )
        
        agent_response = response.get('completion', 'Sorry, I could not process your request.')
        
        # Always reply in thread for channel mentions
        send_slack_message(channel, agent_response, thread_ts=ts)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'success'})
        }
        
    except Exception as e:
        logger.error(f"Error processing mention with Bedrock Agent: {str(e)}")
        error_message = "Sorry, I encountered an error while processing your request."
        send_slack_message(channel, error_message, thread_ts=ts)
        
        return {
            'statusCode': 200,
            'body': json.dumps({'status': 'error', 'message': str(e)})
        }

def send_typing_indicator(channel):
    """Send a typing indicator to the channel"""
    get_slack_tokens()
    
    try:
        client = WebClient(token=slack_token)
        client.chat_postEphemeral(
            channel=channel,
            user=channel,  # This will only work for DMs
            text="Thinking...",
            thread_ts=None
        )
    except Exception as e:
        logger.warning(f"Could not send typing indicator: {str(e)}")

def send_slack_message(channel, text, thread_ts=None):
    """Send a message to a Slack channel"""
    get_slack_tokens()
    
    try:
        client = WebClient(token=slack_token)
        
        # Split long messages if necessary (Slack has a limit)
        max_length = 3000
        messages = [text[i:i+max_length] for i in range(0, len(text), max_length)]
        
        for message in messages:
            response = client.chat_postMessage(
                channel=channel,
                text=message,
                thread_ts=thread_ts
            )
            
    except SlackApiError as e:
        logger.error(f"Error sending Slack message: {str(e)}")

def lambda_handler(event, context):
    """Main Lambda handler function"""
    try:
        # Log the event for debugging
        logger.info(f"Received event: {json.dumps(event)}")
        
        # Check if it's a Slack event
        if 'body' in event:
            # Parse the event body
            body = event.get('body', '{}')
            if event.get('isBase64Encoded', False):
                import base64
                body = base64.b64decode(body).decode('utf-8')
                
            body_json = json.loads(body)
            
            # Verify the request came from Slack
            if not verify_slack_request(event):
                return {
                    'statusCode': 403,
                    'body': json.dumps({'error': 'Invalid Slack signature'})
                }
            
            # Handle the event
            return handle_slack_event(body_json)
        
        return {
            'statusCode': 400,
            'body': json.dumps({'error': 'Invalid request format'})
        }
        
    except Exception as e:
        logger.error(f"Error processing Lambda event: {str(e)}")
        return {
            'statusCode': 500,
            'body': json.dumps({'error': str(e)})
        }