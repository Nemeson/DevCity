{
  "$schema": "https://json.schemastore.org/opencode.json",
  "version": "1.0.0",
  "description": "OpenCode MCP-Client-Konfiguration (Template). Wird von MCPConfig.psm1 pro Tool gemerged.",
  "mcpServers": {
    "context7": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@upstash/context7-mcp@latest"],
      "env": {}
    },
    "atlassian": {
      "type": "stdio",
      "command": "docker",
      "args": ["run", "-i", "--rm", "ghcr.io/atlassian/atlassian-mcp-server:latest"],
      "env": {
        "ATLASSIAN_URL": "{{secret:atlassian_url}}",
        "ATLASSIAN_API_TOKEN": "{{secret:atlassian_token}}"
      }
    },
    "codebase-memory": {
      "type": "stdio",
      "command": "node",
      "args": ["{{MCP_DIR}}/codebase-memory-mcp/dist/index.js"],
      "env": {
        "MEMORY_STORE_PATH": "{{memory_store_path}}"
      }
    },
    "jenkins": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "jenkins-mcp-client@latest"],
      "env": {
        "JENKINS_URL": "{{secret:jenkins_url}}",
        "JENKINS_USER": "{{secret:jenkins_user}}",
        "JENKINS_TOKEN": "{{secret:jenkins_token}}"
      }
    }
  }
}