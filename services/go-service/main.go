package main

import (
	"encoding/json"
	"fmt"
	"log"
	"net/http"
	"os"
	"strings"
	"time"
)

type Response struct {
	Service   string    `json:"service"`
	Message   string    `json:"message"`
	Timestamp time.Time `json:"timestamp"`
	User      string    `json:"user,omitempty"`
}

func main() {
	serviceName := getEnv("SERVICE_NAME", "go-service")
	servicePort := getEnv("SERVICE_PORT", "8080")

	http.HandleFunc("/", handleRoot)
	http.HandleFunc("/health", handleHealth)
	http.HandleFunc("/api/data", handleAPIData)
	http.HandleFunc("/admin/users", handleAdminUsers)
	http.HandleFunc("/users/", handleUserResource) // ReBAC endpoint

	addr := ":" + servicePort
	log.Printf("%s starting on %s", serviceName, addr)
	if err := http.ListenAndServe(addr, nil); err != nil {
		log.Fatal(err)
	}
}

func handleRoot(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "Hello from Go service! This is a public endpoint.",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

func handleHealth(w http.ResponseWriter, r *http.Request) {
	respond(w, map[string]string{"status": "healthy"})
}

func handleAPIData(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "API data endpoint - requires user or admin role",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

func handleAdminUsers(w http.ResponseWriter, r *http.Request) {
	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   "Admin endpoint - requires admin role",
		Timestamp: time.Now(),
		User:      getUser(r),
	})
}

// ReBAC: Resource-based access control
// Pattern: /users/{user_id}/profile or /users/{user_id}/data
func handleUserResource(w http.ResponseWriter, r *http.Request) {
	parts := strings.Split(strings.Trim(r.URL.Path, "/"), "/")
	if len(parts) < 3 {
		http.Error(w, "Invalid path. Use: /users/{user_id}/{resource}", http.StatusBadRequest)
		return
	}

	userID := parts[1]
	resource := parts[2]

	respond(w, Response{
		Service:   getEnv("SERVICE_NAME", "go-service"),
		Message:   fmt.Sprintf("Resource-based access: user %s's %s (OPA validates ownership)", userID, resource),
		Timestamp: time.Now(),
		User:      userID,
	})
}

func getUser(r *http.Request) string {
	auth := r.Header.Get("Authorization")
	if auth != "" {
		return "authenticated-user"
	}
	return "anonymous"
}

func respond(w http.ResponseWriter, data interface{}) {
	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(data)
}

func getEnv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}