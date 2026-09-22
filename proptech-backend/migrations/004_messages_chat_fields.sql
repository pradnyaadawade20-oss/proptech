-- Needed for chat/messages module:
-- is_read on messages: lets us compute ChatConversation.unreadCount
-- avatar_url on users: lets us return ChatConversation.avatarUrl

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS is_read BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE users
    ADD COLUMN IF NOT EXISTS avatar_url TEXT;