-- Database: real-estate-ledger

-- DROP DATABASE IF EXISTS "real-estate-ledger";

CREATE DATABASE "real-estate-ledger"
    WITH
    OWNER = postgres
    ENCODING = 'UTF8'
    LC_COLLATE = 'English_India.1252'
    LC_CTYPE = 'English_India.1252'
    LOCALE_PROVIDER = 'libc'
    TABLESPACE = pg_default
    CONNECTION LIMIT = -1
    IS_TEMPLATE = False;

-- Enable the pgcrypto extension for hashing
CREATE EXTENSION IF NOT EXISTS pgcrypto;

-- Create the users table
CREATE TABLE users (
    username VARCHAR(50) PRIMARY KEY,
    password_hash TEXT NOT NULL
);

CREATE TABLE property (
    PropertyID SERIAL PRIMARY KEY,
    OwnerUsername VARCHAR(255) NOT NULL,
    OwnerName VARCHAR(255) NOT NULL,
    Address TEXT NOT NULL,
    PropertyType VARCHAR(100),
    DateOfPurchase DATE
);
