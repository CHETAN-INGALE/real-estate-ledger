-- Example of inserting a user with a SHA-256 hashed password (without salt)
INSERT INTO users (username, password_hash)
VALUES ('Amol', encode(digest('password', 'sha256'), 'hex'));