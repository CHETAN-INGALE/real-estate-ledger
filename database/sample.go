package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"

	_ "github.com/lib/pq"
)

func main() {
	// Database connection string
	connStr := "host=141.148.219.156 user=postgres dbname=real-estate-ledger password=postgres sslmode=disable"
	db, err := sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	// Query to fetch all users
	rows, err := db.Query("SELECT username, password_hash FROM users")
	if err != nil {
		log.Fatal(err)
	}
	defer rows.Close()

	// Create a slice to hold the query results
	type User struct {
		Username     string `json:"username"`
		PasswordHash string `json:"password_hash"`
	}

	var users []User

	// Iterate through the rows and append each user to the slice
	for rows.Next() {
		var user User
		err := rows.Scan(&user.Username, &user.PasswordHash)
		if err != nil {
			log.Fatal(err)
		}
		users = append(users, user)
	}

	// Check for any errors encountered during iteration
	err = rows.Err()
	if err != nil {
		log.Fatal(err)
	}

	// Convert the slice to JSON format
	usersJSON, err := json.Marshal(users)
	if err != nil {
		log.Fatal(err)
	}

	// Convert JSON byte array to string
	jsonString := string(usersJSON)

	// Print the JSON string
	fmt.Println(jsonString)
}
