package main

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"log"
	"net/http"

	_ "github.com/lib/pq"
)

// Replace with your PostgreSQL connection string
const dbURL = "postgres://postgres:postgres@141.148.219.156:5432/real-estate-ledger?sslmode=disable"

// Property struct represents a property record
type Property struct {
	PropertyID     int    `json:"property_id"`
	OwnerUsername  string `json:"owner_username"`
	OwnerName      string `json:"owner_name"`
	Address        string `json:"address"`
	PropertyType   string `json:"property_type"`
	DateOfPurchase string `json:"date_of_purchase"`
}

// RegisterPropertyHandler handles the registration of a new property
func RegisterPropertyHandler(w http.ResponseWriter, r *http.Request) {
	var property Property

	err := json.NewDecoder(r.Body).Decode(&property)
	if err != nil {
		http.Error(w, "Invalid JSON data", http.StatusBadRequest)
		return
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	query := "INSERT INTO property (OwnerUsername, OwnerName, Address, PropertyType, DateOfPurchase) VALUES ($1, $2, $3, $4, $5)"
	_, err = db.Exec(query, property.OwnerUsername, property.OwnerName, property.Address, property.PropertyType, property.DateOfPurchase)
	if err != nil {
		http.Error(w, "Error inserting property", http.StatusInternalServerError)
		return
	}

	property.PropertyID = 0 // Set PropertyID to 0 as it's auto-generated
	json.NewEncoder(w).Encode(property)
}

// UpdatePropertyOwnerHandler updates the owner of a specific property
func UpdatePropertyOwnerHandler(w http.ResponseWriter, r *http.Request) {
	var property Property

	err := json.NewDecoder(r.Body).Decode(&property)
	if err != nil {
		http.Error(w, "Invalid JSON data", http.StatusBadRequest)
		return
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	query := "UPDATE property SET OwnerUsername = $1, OwnerName = $2 WHERE PropertyID = $3"
	_, err = db.Exec(query, property.OwnerUsername, property.OwnerName, property.PropertyID)
	if err != nil {
		http.Error(w, "Error updating property owner", http.StatusInternalServerError)
		return
	}

	json.NewEncoder(w).Encode(property)
}

// GetPropertyDetailsHandler retrieves property details by property ID
func GetPropertyDetailsHandler(w http.ResponseWriter, r *http.Request) {
	propertyID := r.URL.Query().Get("property_id")
	if propertyID == "" {
		http.Error(w, "Property ID is required", http.StatusBadRequest)
		return
	}

	db, err := sql.Open("postgres", dbURL)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	query := "SELECT * FROM property WHERE PropertyID = $1"
	row := db.QueryRow(query, propertyID)

	var property Property
	err = row.Scan(&property.PropertyID, &property.OwnerUsername, &property.OwnerName, &property.Address, &property.PropertyType, &property.DateOfPurchase)
	if err != nil {
		if err == sql.ErrNoRows {
			http.Error(w, "Property not found", http.StatusNotFound)
		} else {
			http.Error(w, "Error fetching property details", http.StatusInternalServerError)
		}
		return
	}

	json.NewEncoder(w).Encode(property)
}

func main() {
	http.HandleFunc("/register-property", RegisterPropertyHandler)
	http.HandleFunc("/update-property-owner", UpdatePropertyOwnerHandler)
	http.HandleFunc("/get-property-details", GetPropertyDetailsHandler)

	fmt.Println("Server listening on port 8080")
	http.ListenAndServe(":8080", nil)
}
