package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	_ "github.com/lib/pq"
	"github.com/rs/cors"
)

// User struct to hold login data
type User struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// Database connection function
func connectDB() (*sql.DB, error) {
	connStr := "host=141.148.219.156 user=postgres dbname=real-estate-ledger password=postgres sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		return nil, err
	}
	return db, nil
}

// Verify credentials function
func verifyCredentials(db *sql.DB, username, password string) bool {
	// Query to get the stored hash from the database
	var storedHash string
	err := db.QueryRow("SELECT password_hash FROM users WHERE username=$1", username).Scan(&storedHash)
	if err != nil {
		if err == sql.ErrNoRows {
			// No user found
			return false
		}
		log.Printf("Database error: %v", err)
		return false
	}

	// Hash the incoming password
	hashedPassword := sha256.Sum256([]byte(password))
	passwordHash := hex.EncodeToString(hashedPassword[:])

	// Compare the stored hash with the incoming hash
	return storedHash == passwordHash
}

// Handler function for login
func loginHandler(db *sql.DB) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "Invalid request method", http.StatusMethodNotAllowed)
			return
		}

		var user User
		// Decode the incoming JSON request into the user struct
		if err := json.NewDecoder(r.Body).Decode(&user); err != nil {
			http.Error(w, "Bad request", http.StatusBadRequest)
			return
		}

		// Verify credentials
		if verifyCredentials(db, user.Username, user.Password) {
			// On successful authentication, return a success message
			w.WriteHeader(http.StatusOK)
			fmt.Fprintf(w, "Login successful for user: %s", user.Username)
		} else {
			// On failure, return an error message
			http.Error(w, "Invalid username or password", http.StatusUnauthorized)
		}
	}
}

func main() {

	// Create a CORS middleware
	corsHandler := cors.New(cors.Options{
		AllowedOrigins:   []string{"*"}, // Replace with your frontend domain
		AllowedMethods:   []string{"GET", "POST", "PUT", "DELETE"},
		AllowedHeaders:   []string{"Content-Type", "Authorization"},
		AllowCredentials: true,
	}).Handler

	// Connect to the database
	db, err := connectDB()
	if err != nil {
		log.Fatalf("Failed to connect to the database: %v", err)
	}
	defer db.Close()

	// Set up the handler for the login route
	http.HandleFunc("/login", loginHandler(db))

	// Start the server on port 8080
	log.Println("Server started on http://141.148.219.156:8080")
	if err := http.ListenAndServe("0.0.0.0:8080", corsHandler(nil)); err != nil {
		log.Fatalf("Server failed to start: %v", err)
	}
}
