FROM srlynch1/terraform-ai-tools:latest

USER root

# Install bun system-wide, claude-code for node user, and setup config
ENV BUN_INSTALL="/usr/local"
RUN curl -fsSL https://bun.sh/install | bash && \
    su node -c 'BUN_INSTALL="/home/node/.local" bun install -g @anthropic-ai/claude-code' && \
    mkdir -p /home/node/.claude && \
    touch /home/node/.claude/.claude.json && \
    chmod 700 /home/node/.claude && \
    chmod 600 /home/node/.claude/.claude.json && \
    chown -R node:node /home/node/.claude

COPY scripts/claude-statusline.sh /usr/local/bin/claude-statusline.sh
RUN chmod +x /usr/local/bin/claude-statusline.sh && \
    echo 'alias clauded="claude --dangerously-skip-permissions"' >> /home/node/.zshrc && \
    chown node:node /home/node/.zshrc

USER node
ENV PATH="/home/node/.local/bin:${PATH}"
