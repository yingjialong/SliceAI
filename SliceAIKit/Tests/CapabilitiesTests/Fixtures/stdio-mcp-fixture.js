#!/usr/bin/env node
const fs = require("fs");
const readline = require("readline");
const rl = readline.createInterface({ input: process.stdin });
const mode = process.argv[2] || "";
const statePath = process.argv[3] || "";
let initialized = false;
let toolsListed = false;

function send(id, result) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, result }) + "\n");
}

function sendError(id, code, message) {
  process.stdout.write(JSON.stringify({ jsonrpc: "2.0", id, error: { code, message } }) + "\n");
}

function shouldFailFirstInitialize() {
  if (mode !== "first-init-error" || !statePath) {
    return false;
  }

  if (fs.existsSync(statePath)) {
    return false;
  }

  fs.writeFileSync(statePath, "failed-once");
  return true;
}

function countInitializeAndReply(id) {
  const current = fs.existsSync(statePath) ? Number(fs.readFileSync(statePath, "utf8")) : 0;
  fs.writeFileSync(statePath, String(current + 1));
  setTimeout(() => {
    initialized = true;
    send(id, { protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "fixture", version: "1.0.0" } });
  }, 80);
}

function sendToolList(id) {
  toolsListed = true;
  send(id, { tools: [{ name: "echo", title: "Echo Query", description: "Echo query", inputSchema: { type: "object" } }] });
}

function writeChunkedStderrAndReply(msg) {
  process.stderr.write("Cookie: session=");
  setTimeout(() => {
    process.stderr.write("secret\n");
    send(msg.id, { content: [{ type: "text", text: msg.params.arguments.query }], isError: false });
  }, 20);
}

function sendToolCall(msg) {
  const delay = msg.params.arguments.delayCallMs || 0;
  setTimeout(() => {
    send(msg.id, { content: [{ type: "text", text: msg.params.arguments.query }], isError: false });
  }, delay);
}

rl.on("line", (line) => {
  const msg = JSON.parse(line);
  if (msg.method === "initialize") {
    if (shouldFailFirstInitialize()) {
      sendError(msg.id, -32001, "initialize failed once");
      return;
    }
    if (mode === "count-initialize" && statePath) {
      countInitializeAndReply(msg.id);
      return;
    }
    initialized = true;
    send(msg.id, { protocolVersion: "2025-06-18", capabilities: { tools: {} }, serverInfo: { name: "fixture", version: "1.0.0" } });
  } else if (msg.method === "notifications/initialized") {
    // Notification: no response.
  } else if (msg.method === "tools/list") {
    if (!initialized) {
      sendError(msg.id, -32002, "initialize required before tools/list");
      return;
    }
    if (mode === "delayed-list") {
      setTimeout(() => sendToolList(msg.id), 250);
      return;
    }
    sendToolList(msg.id);
  } else if (msg.method === "tools/call") {
    if (!initialized) {
      sendError(msg.id, -32002, "initialize required before tools/call");
      return;
    }
    if (!toolsListed) {
      sendError(msg.id, -32000, "tools/list required before tools/call");
      return;
    }
    if (msg.params.arguments.writeStderr) {
      process.stderr.write("Bearer secret-token sk-1234567890abcdef Authorization: token Cookie: session=secret\n");
    }
    if (msg.params.arguments.writeChunkedStderr) {
      writeChunkedStderrAndReply(msg);
      return;
    }
    sendToolCall(msg);
  }
});
