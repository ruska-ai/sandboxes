const { McpServer } = require("@modelcontextprotocol/sdk/server/mcp.js");
const { StreamableHTTPServerTransport } = require("@modelcontextprotocol/sdk/server/streamableHttp.js");
const express = require("express");
const { z } = require("zod");
const { exec, execSync } = require("child_process");
const crypto = require("crypto");
const path = require("path");

// Resolve executor user UID/GID at startup
const EXEC_UID = parseInt(execSync("id -u executor").toString().trim(), 10);
const EXEC_GID = parseInt(execSync("id -g executor").toString().trim(), 10);

const API_KEY = process.env.API_KEY || "";
const SANDBOX_ID = crypto.randomUUID();

// Helper: build tool response with structured _meta
function makeResult(text, exitCode) {
  return {
    content: [{ type: "text", text }],
    _meta: { exit_code: exitCode, sandbox_id: SANDBOX_ID },
  };
}

function log(level, msg, meta = {}) {
  const entry = {
    time: new Date().toISOString(),
    level,
    msg,
    ...meta,
  };
  console.log(JSON.stringify(entry));
}

// Auth middleware
function authMiddleware(req, res, next) {
  if (API_KEY && req.headers["x-api-key"] !== API_KEY) {
    log("warn", "Auth rejected", { ip: req.ip });
    return res.status(401).json({ error: "Unauthorized" });
  }
  next();
}

// Request logging middleware
function requestLogger(req, res, next) {
  const start = Date.now();
  res.on("finish", () => {
    log("info", "request", {
      method: req.method,
      path: req.path,
      status: res.statusCode,
      ms: Date.now() - start,
      session: req.headers["mcp-session-id"] || null,
    });
  });
  next();
}

// Default cwd for all exec() calls
const EXEC_CWD = "/workspace";
const EXEC_ENV = { HOME: "/home/executor", PATH: "/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin", TERM: "xterm" };
const EXEC_OPTS = { uid: EXEC_UID, gid: EXEC_GID, cwd: EXEC_CWD, env: EXEC_ENV };

// Max timeout cap (120 seconds)
const MAX_TIMEOUT_MS = 120000;

// Helper: run a command as executor user and return {stdout, exitCode}
function runAsExecutor(cmd, timeoutMs = MAX_TIMEOUT_MS) {
  return new Promise((resolve) => {
    exec(cmd, { ...EXEC_OPTS, timeout: timeoutMs, maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
      resolve({ stdout: stdout || "", stderr: stderr || "", exitCode: error ? (error.code ?? 1) : 0 });
    });
  });
}

// ---- Tool Handlers ----

function executeHandler({ cmd, timeout }) {
  const timeoutMs = Math.min((timeout || 120) * 1000, MAX_TIMEOUT_MS);
  log("info", "execute called", { cmd, timeoutMs });
  return new Promise((resolve) => {
    exec(cmd, { ...EXEC_OPTS, timeout: timeoutMs, maxBuffer: 1024 * 1024 * 10 }, (error, stdout, stderr) => {
      const output = [];
      if (stdout) output.push(`stdout:\n${stdout}`);
      if (stderr) output.push(`stderr:\n${stderr}`);
      if (error && !stderr) output.push(`error: ${error.message}`);
      if (error) output.push(`exit_code: ${error.code ?? 1}`);
      const exitCode = error ? (error.code ?? 1) : 0;
      log(error ? "error" : "info", "execute result", { cmd, exitCode });
      resolve(makeResult(output.join("\n") || "(no output)", exitCode));
    });
  });
}

async function readHandler({ path: filePath, offset, limit }) {
  const off = offset || 0;
  const lim = limit || 2000;
  try {
    const { stdout, exitCode } = await runAsExecutor(`cat '${filePath.replace(/'/g, "'\\''")}'`);
    if (exitCode !== 0) return makeResult(`Error: file not found or unreadable: ${filePath}`, 1);
    const lines = stdout.split("\n");
    const slice = lines.slice(off, off + lim);
    const formatted = slice.map((line, i) => {
      const lineNum = String(off + i + 1).padStart(6, " ");
      return `${lineNum}\t${line}`;
    }).join("\n");
    return makeResult(formatted, 0);
  } catch (e) {
    return makeResult(`Error: ${e.message}`, 1);
  }
}

async function writeHandler({ path: filePath, content }) {
  try {
    const dir = path.dirname(filePath);
    await runAsExecutor(`mkdir -p '${dir.replace(/'/g, "'\\''")}'`);
    // Write content via stdin to handle special characters safely
    const encoded = Buffer.from(content).toString("base64");
    const { exitCode } = await runAsExecutor(`echo '${encoded}' | base64 -d > '${filePath.replace(/'/g, "'\\''")}'`);
    if (exitCode !== 0) return makeResult(`Error writing to ${filePath}`, 1);
    return makeResult(`Written to ${filePath}`, 0);
  } catch (e) {
    return makeResult(`Error: ${e.message}`, 1);
  }
}

async function editHandler({ path: filePath, old_string, new_string, replace_all }) {
  try {
    const { stdout, exitCode } = await runAsExecutor(`cat '${filePath.replace(/'/g, "'\\''")}'`);
    if (exitCode !== 0) return makeResult(`Error: file not found at ${filePath}`, 3);
    const content = stdout;
    const occurrences = content.split(old_string).length - 1;
    if (occurrences === 0) return makeResult(`Error: old_string not found in ${filePath}`, 1);
    if (occurrences > 1 && !replace_all) return makeResult(`Error: ${occurrences} occurrences found, use replace_all=true`, 2);
    const updated = replace_all ? content.replaceAll(old_string, new_string) : content.replace(old_string, new_string);
    const encoded = Buffer.from(updated).toString("base64");
    await runAsExecutor(`echo '${encoded}' | base64 -d > '${filePath.replace(/'/g, "'\\''")}'`);
    const replaced = replace_all ? occurrences : 1;
    return makeResult(`Replaced ${replaced} occurrence(s) in ${filePath}`, 0);
  } catch (e) {
    return makeResult(`Error: ${e.message}`, 1);
  }
}

async function grepHandler({ pattern, path: searchPath, glob: globPattern }) {
  let cmd = `grep -rHnF '${pattern.replace(/'/g, "'\\''")}'`;
  if (globPattern) cmd += ` --include='${globPattern.replace(/'/g, "'\\''")}'`;
  cmd += ` '${(searchPath || EXEC_CWD).replace(/'/g, "'\\''")}'`;
  const { stdout, exitCode } = await runAsExecutor(cmd);
  if (exitCode !== 0 || !stdout.trim()) return makeResult("", 1);
  const lines = stdout.trim().split("\n").map((line) => {
    const match = line.match(/^(.+?):(\d+):(.*)$/);
    if (!match) return null;
    return JSON.stringify({ path: match[1], line: parseInt(match[2], 10), text: match[3] });
  }).filter(Boolean);
  return makeResult(lines.join("\n"), 0);
}

async function globHandler({ pattern, path: searchPath }) {
  const base = searchPath || EXEC_CWD;
  const cmd = `find '${base.replace(/'/g, "'\\''")}'  -name '${pattern.replace(/'/g, "'\\''")}'  -not -path '*/node_modules/*' -not -path '*/.git/*' 2>/dev/null`;
  const { stdout } = await runAsExecutor(cmd);
  if (!stdout.trim()) return makeResult("", 0);
  const entries = [];
  for (const filePath of stdout.trim().split("\n")) {
    try {
      const { stdout: statOut } = await runAsExecutor(`stat -c '%F|%s|%Y' '${filePath.replace(/'/g, "'\\''")}'`);
      const [type, size, mtime] = statOut.trim().split("|");
      entries.push(JSON.stringify({
        path: filePath,
        is_dir: type === "directory",
        size: parseInt(size, 10),
        mtime: new Date(parseInt(mtime, 10) * 1000).toISOString(),
      }));
    } catch (_) {
      entries.push(JSON.stringify({ path: filePath, is_dir: false, size: 0, mtime: null }));
    }
  }
  return makeResult(entries.join("\n"), 0);
}

async function lsHandler({ path: dirPath }) {
  const { stdout, exitCode } = await runAsExecutor(`ls -1a '${dirPath.replace(/'/g, "'\\''")}'`);
  if (exitCode !== 0) return makeResult(`Error: path not found: ${dirPath}`, 1);
  const names = stdout.trim().split("\n").filter((name) => name !== "." && name !== "..");
  const entries = [];
  for (const name of names) {
    const fullPath = path.join(dirPath, name);
    const { stdout: statOut } = await runAsExecutor(`stat -c '%F' '${fullPath.replace(/'/g, "'\\''")}'`);
    entries.push(JSON.stringify({ path: fullPath, is_dir: statOut.trim() === "directory" }));
  }
  return makeResult(entries.join("\n"), 0);
}

async function uploadFileHandler({ path: filePath, content_base64 }) {
  try {
    const dir = path.dirname(filePath);
    await runAsExecutor(`mkdir -p '${dir.replace(/'/g, "'\\''")}'`);
    const { exitCode } = await runAsExecutor(`echo '${content_base64}' | base64 -d > '${filePath.replace(/'/g, "'\\''")}'`);
    if (exitCode !== 0) return makeResult(`Error uploading to ${filePath}`, 1);
    const decoded = Buffer.from(content_base64, "base64");
    return makeResult(`Written ${decoded.length} bytes to ${filePath}`, 0);
  } catch (e) {
    return makeResult(`Error: ${e.message}`, 1);
  }
}

async function downloadFileHandler({ path: filePath }) {
  try {
    const { stdout, exitCode } = await runAsExecutor(`base64 '${filePath.replace(/'/g, "'\\''")}'`);
    if (exitCode !== 0) return makeResult(`Error: file not found: ${filePath}`, 1);
    return makeResult(stdout.trim(), 0);
  } catch (e) {
    return makeResult(`Error: ${e.message}`, 1);
  }
}

// ---- Tool Registration ----

function registerTools(server) {
  // execute + backward-compat alias
  server.tool("execute", "Execute a shell command and return stdout/stderr", {
    cmd: z.string().describe("The shell command to execute"),
    timeout: z.number().optional().describe("Timeout in seconds (default 120, max 120)"),
  }, executeHandler);
  server.tool("exec_command", "Execute a shell command (alias for execute)", {
    cmd: z.string().describe("The shell command to execute"),
    timeout: z.number().optional().describe("Timeout in seconds (default 120, max 120)"),
  }, executeHandler);

  // read
  server.tool("read", "Read file with line numbers", {
    path: z.string().describe("Absolute file path"),
    offset: z.number().optional().describe("0-based line offset (default 0)"),
    limit: z.number().optional().describe("Max lines to return (default 2000)"),
  }, readHandler);

  // write
  server.tool("write", "Write content to file", {
    path: z.string().describe("Absolute file path"),
    content: z.string().describe("Content to write"),
  }, writeHandler);

  // edit
  server.tool("edit", "Replace string in file", {
    path: z.string().describe("Absolute file path"),
    old_string: z.string().describe("String to find"),
    new_string: z.string().describe("Replacement string"),
    replace_all: z.boolean().optional().describe("Replace all occurrences (default false)"),
  }, editHandler);

  // grep
  server.tool("grep", "Search for pattern in files", {
    pattern: z.string().describe("Fixed string pattern to search"),
    path: z.string().optional().describe("Search path (default /workspace)"),
    glob: z.string().optional().describe("File glob filter"),
  }, grepHandler);

  // glob
  server.tool("glob", "Find files by glob pattern", {
    pattern: z.string().describe("File name glob pattern"),
    path: z.string().optional().describe("Search path (default /workspace)"),
  }, globHandler);

  // ls
  server.tool("ls", "List directory contents", {
    path: z.string().describe("Directory path"),
  }, lsHandler);

  // upload_file
  server.tool("upload_file", "Upload base64 file", {
    path: z.string().describe("Absolute file path"),
    content_base64: z.string().describe("Base64-encoded file content"),
  }, uploadFileHandler);

  // download_file
  server.tool("download_file", "Download file as base64", {
    path: z.string().describe("Absolute file path"),
  }, downloadFileHandler);
}

// Create top-level server (unused directly but kept for reference)
const server = new McpServer({ name: "exec-server", version: "1.0.0" });
registerTools(server);

const app = express();

app.use(requestLogger);
app.use("/mcp", express.json());
app.use("/mcp", authMiddleware);

// Transport map for session management
const transports = new Map();

app.post("/mcp", async (req, res) => {
  try {
    const sessionId = req.headers["mcp-session-id"];
    const rpcMethod = req.body?.method;

    if (sessionId && transports.has(sessionId)) {
      log("info", "Existing session request", { session: sessionId, rpcMethod });
      const transport = transports.get(sessionId);
      await transport.handleRequest(req, res, req.body);
      return;
    }

    // New session
    log("info", "Creating new session", { rpcMethod });

    const transport = new StreamableHTTPServerTransport({
      sessionIdGenerator: () => crypto.randomUUID(),
    });

    transport.onclose = () => {
      if (transport.sessionId) {
        log("info", "Session closed", { session: transport.sessionId });
        transports.delete(transport.sessionId);
        log("info", "Active sessions", { count: transports.size });
      }
    };

    const serverInstance = new McpServer({ name: "exec-server", version: "1.0.0" });
    registerTools(serverInstance);

    await serverInstance.connect(transport);
    await transport.handleRequest(req, res, req.body);

    if (transport.sessionId) {
      transports.set(transport.sessionId, transport);
      log("info", "Session created", { session: transport.sessionId });
      log("info", "Active sessions", { count: transports.size });
    }
  } catch (err) {
    log("error", "MCP error", { error: err.message, stack: err.stack });
    if (!res.headersSent) {
      res.status(500).json({ error: "Internal server error" });
    }
  }
});

app.get("/mcp", async (req, res) => {
  const sessionId = req.headers["mcp-session-id"];
  if (!sessionId || !transports.has(sessionId)) {
    log("warn", "GET with invalid session", { session: sessionId });
    return res.status(400).json({ error: "Invalid or missing session ID" });
  }
  const transport = transports.get(sessionId);
  await transport.handleRequest(req, res);
});

app.delete("/mcp", async (req, res) => {
  const sessionId = req.headers["mcp-session-id"];
  if (!sessionId || !transports.has(sessionId)) {
    log("warn", "DELETE with invalid session", { session: sessionId });
    return res.status(400).json({ error: "Invalid or missing session ID" });
  }
  log("info", "Session delete requested", { session: sessionId });
  const transport = transports.get(sessionId);
  await transport.handleRequest(req, res);
});

app.get("/health", (req, res) => {
  res.json({ status: "ok", sessions: transports.size, sandbox_id: SANDBOX_ID });
});

const PORT = process.env.PORT || 3005;
app.listen(PORT, () => {
  log("info", "Server started", { port: PORT, auth: !!API_KEY });
});
