#!/usr/bin/env node

/**
 * Claude SDK Wrapper for Fantasy Manager
 * 
 * This Node.js script provides a simple interface to the Anthropic SDK
 * that can be called from Elixir, replacing the problematic CLI calls.
 */

const Anthropic = require('@anthropic-ai/sdk');

// Initialize the Anthropic client with multiple auth strategies
let anthropic;

try {
  // First try: use ANTHROPIC_API_KEY if available
  if (process.env.ANTHROPIC_API_KEY) {
    anthropic = new Anthropic({
      apiKey: process.env.ANTHROPIC_API_KEY
    });
  } else {
    // For now, we'll require an API key
    // In the future, we could try to extract from claude-code session
    throw new Error('ANTHROPIC_API_KEY environment variable is required');
  }
} catch (error) {
  console.error(`[ERROR] Failed to initialize Anthropic client: ${error.message}`);
  process.exit(1);
}

async function callClaude(prompt, options = {}) {
  try {
    const model = options.model || 'claude-3-5-haiku-20241022';
    const maxTokens = options.maxTokens || 4000;
    const temperature = options.temperature || 0.7;
    
    // Debug messages only to stderr (commented out for clean output)
    // console.error(`[DEBUG] Calling Claude API with model: ${model}`);
    // console.error(`[DEBUG] Prompt length: ${prompt.length}`);
    
    const message = await anthropic.messages.create({
      model: model,
      max_tokens: maxTokens,
      temperature: temperature,
      messages: [{
        role: 'user',
        content: prompt
      }]
    });
    
    // Extract text content from the response
    const content = message.content
      .filter(block => block.type === 'text')
      .map(block => block.text)
      .join('\n');
    
    // console.error(`[DEBUG] Response length: ${content.length}`);
    
    // Return in a format similar to claude CLI
    const response = {
      type: "result",
      subtype: "success", 
      is_error: false,
      result: content,
      usage: message.usage
    };
    
    console.log(JSON.stringify(response));
    
  } catch (error) {
    const errorResponse = {
      type: "result",
      subtype: "error",
      is_error: true,
      error: error.message,
      result: ""
    };
    
    console.log(JSON.stringify(errorResponse));
    process.exit(1);
  }
}

// Parse command line arguments
const args = process.argv.slice(2);

if (args.length === 0) {
  console.error('Usage: node claude_sdk_wrapper.js [options] "prompt"');
  process.exit(1);
}

// Simple argument parsing
let prompt = '';
let options = {};

// Find the prompt (last non-option argument)
for (let i = 0; i < args.length; i++) {
  const arg = args[i];
  
  if (arg === '--model' && i + 1 < args.length) {
    options.model = args[i + 1];
    i++; // skip the next argument
  } else if (arg === '--max-tokens' && i + 1 < args.length) {
    options.maxTokens = parseInt(args[i + 1]);
    i++; // skip the next argument 
  } else if (arg === '--temperature' && i + 1 < args.length) {
    options.temperature = parseFloat(args[i + 1]);
    i++; // skip the next argument
  } else if (!arg.startsWith('--')) {
    // This is the prompt
    prompt = arg;
  }
}

if (!prompt) {
  console.error('Error: No prompt provided');
  process.exit(1);
}

// Call Claude with the provided prompt
callClaude(prompt, options);