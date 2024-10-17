package main

import (
	"crypto/sha256"
	"database/sql"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	"github.com/gorilla/mux"
	_ "github.com/lib/pq" // PostgreSQL driver
	"github.com/rs/cors"
)

var db *sql.DB

type User struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

type Property struct {
	PropertyID     int    `json:"property_id"`
	OwnerUsername  string `json:"owner_username"`
	OwnerName      string `json:"owner_name"`
	Address        string `json:"address"`
	PropertyType   string `json:"property_type"`
	DateOfPurchase string `json:"date_of_purchase"`
}

func hashPassword(password string) string {
	hash := sha256.New()
	hash.Write([]byte(password))
	return hex.EncodeToString(hash.Sum(nil))
}

// Login API
func login(w http.ResponseWriter, r *http.Request) {
	var user User
	json.NewDecoder(r.Body).Decode(&user)

	var storedHash string
	err := db.QueryRow("SELECT password_hash FROM users WHERE username=$1", user.Username).Scan(&storedHash)
	if err != nil {
		http.Error(w, "User not found", http.StatusUnauthorized)
		return
	}

	hashedPassword := hashPassword(user.Password)
	if hashedPassword != storedHash {
		http.Error(w, "Invalid password", http.StatusUnauthorized)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Login successful")
}

// Register Property API
func registerProperty(w http.ResponseWriter, r *http.Request) {
	var property Property
	json.NewDecoder(r.Body).Decode(&property)

	_, err := db.Exec("INSERT INTO property (OwnerUsername, OwnerName, Address, PropertyType, DateOfPurchase) VALUES ($1, $2, $3, $4, $5)",
		property.OwnerUsername, property.OwnerName, property.Address, property.PropertyType, property.DateOfPurchase)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusCreated)
	fmt.Fprintf(w, "Property registered successfully")
}

// Update Property API
func updateProperty(w http.ResponseWriter, r *http.Request) {
	var property Property
	json.NewDecoder(r.Body).Decode(&property)

	_, err := db.Exec("UPDATE property SET OwnerUsername=$1, OwnerName=$2 WHERE PropertyID=$3",
		property.OwnerUsername, property.OwnerName, property.PropertyID)
	if err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
		return
	}

	w.WriteHeader(http.StatusOK)
	fmt.Fprintf(w, "Property updated successfully")
}

// Get Property API
func getProperty(w http.ResponseWriter, r *http.Request) {
	params := mux.Vars(r)
	propertyID := params["id"]

	var property Property
	err := db.QueryRow("SELECT PropertyID, OwnerUsername, OwnerName, Address, PropertyType, DateOfPurchase FROM property WHERE PropertyID=$1", propertyID).
		Scan(&property.PropertyID, &property.OwnerUsername, &property.OwnerName, &property.Address, &property.PropertyType, &property.DateOfPurchase)
	if err != nil {
		http.Error(w, "Property not found", http.StatusNotFound)
		return
	}

	json.NewEncoder(w).Encode(property)
}

func main() {
	var err error
	connStr := "user=postgres dbname=real-estate-ledger password=postgres sslmode=disable"
	db, err = sql.Open("postgres", connStr)
	if err != nil {
		log.Fatal(err)
	}

	router := mux.NewRouter()

	// Routes
	router.HandleFunc("/login", login).Methods("POST")
	router.HandleFunc("/register-property", registerProperty).Methods("POST")
	router.HandleFunc("/update-property", updateProperty).Methods("PUT")
	router.HandleFunc("/get-property/{id}", getProperty).Methods("GET")

	// CORS configuration
	c := cors.New(cors.Options{
		AllowedOrigins: []string{"*"}, // Allow all origins
		AllowedMethods: []string{"GET", "POST", "PUT", "DELETE"},
		AllowedHeaders: []string{"*"},
	})

	handler := c.Handler(router)

	log.Println("Server running on port http://localhost:8080/")
	http.ListenAndServe("0.0.0.0:8080", handler)
}
